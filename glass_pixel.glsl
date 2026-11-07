// TouchDesigner GLSL MAT — Pixel shader
// Realtime "chrome glass" look: Fresnel-driven environment reflection + fake chromatic
// refraction + thin-film iridescent rim + specular hotspot.
//
// Drop this in a GLSL MAT's Pixel shader DAT, glass_vertex.glsl in the Vertex shader DAT.
// Add the custom parameters listed at the bottom of this file to the MAT's Custom page —
// TD auto-generates the matching uniforms (hover a custom par in TD to see its exact
// uniform name if your version differs slightly from the names used below).

in Vertex {
	vec4 color;
	vec3 worldSpacePos;
	vec3 worldSpaceNorm;
	vec2 texCoord0;
} iVert;

// --- env + iridescence textures (wire these in the MAT's Sampler page) ---
uniform sampler2D sEnvMap;        // equirect env: a Ramp TOP (vertical gradient) or an HDRI photo
uniform sampler2D sIridLut;       // 1D-ish rainbow gradient (thin-film look), sampled by fresnel
uniform sampler2D sBackground;    // scene rendered WITHOUT the glass object — the refraction source
uniform sampler2D sNormalMap;     // tangent-space normal map, optional — unwired is a safe no-op
uniform sampler2D sRoughnessMap;  // grayscale roughness, optional — unwired defaults to 0 (sharp)

// --- custom uniforms ---
// TD's Vectors page on this build only creates vec4 uniforms, so everything below is vec4
// and the code swizzles out .x (floats) or .xyz (colors/directions) where it's used. Only
// fill in as many of the 4 value boxes as the comment says; leave the rest at 0 — the extra
// component(s) are never read.
uniform vec4 uTintcolor;       // .xyz transmitted-light tint (colored glass)
uniform vec4 uRimcolor;        // .xyz rim light color (cyan in ref 1, warm in ref 3)
uniform vec4 uFresnelpower;    // .x grazing-angle falloff, 2-6 typical (higher = tighter rim)
uniform vec4 uIor;             // .x fake IOR, drives chromatic offset, ~1.1-1.6
uniform vec4 uReflectivity;    // .x 0-1, overall mirror strength at grazing angles
uniform vec4 uIridamount;      // .x 0-1, how much thin-film color to add at the rim
uniform vec4 uSpecpower;       // .x specular tightness, 64-512
uniform vec4 uEnvrotate;       // .x radians, spins the environment reflection
uniform vec4 uLightdir;        // .xyz world-space direction TO the key light
uniform vec4 uRefractstrength; // .x 0-0.3 typical, how far the background bends through N
uniform vec4 uChromaspread;    // .x 0-1, R/B separation vs G — the dispersion fringe width
uniform vec4 uNormalstrength;  // .x 0-1, how much sNormalMap perturbs N — 0 = off (safe default)
uniform vec4 uRoughness;       // .x 0-1, multiplies sRoughnessMap — 0 = mirror sharp (safe default)
uniform vec4 uMaxenvlod;       // .x top mip level of sEnvMap — set to its log2(resolution), e.g. 8-10
uniform vec4 uMaxbglod;        // .x top mip level of sBackground — same idea, blurs refraction
uniform vec4 uFrostmilk;       // .x 0-1, soft white haze mixed into the refraction at high roughness

layout(location = 0) out vec4 oFragColor[TD_NUM_COLOR_BUFFERS];

#define TWO_PI 6.28318530718
#define PI 3.14159265359

vec2 envUV(vec3 r)
{
	float s = sin(uEnvrotate.x);
	float c = cos(uEnvrotate.x);
	r.xz = mat2(c, -s, s, c) * r.xz;
	return vec2(atan(r.z, r.x) / TWO_PI + 0.5, acos(clamp(r.y, -1.0, 1.0)) / PI);
}

// Builds a tangent frame on the fly from screen-space derivatives — no tangent/bitangent
// vertex attributes needed. Standard trick (Schuler, "normal mapping without precomputed
// tangents"). p = world-space position, uv = the surface's own texture coordinate.
mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv)
{
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
	return mat3(T * invmax, B * invmax, N);
}

void main()
{
	vec3 N = normalize(iVert.worldSpaceNorm);

	// --- normal map: mix(flat, mapSample, strength) so strength=0 is always a true no-op,
	// regardless of whether sNormalMap is wired to anything ---
	vec3 mapN = mix(vec3(0.0, 0.0, 1.0), texture(sNormalMap, iVert.texCoord0).xyz * 2.0 - 1.0, uNormalstrength.x);
	mat3 TBN = cotangentFrame(N, iVert.worldSpacePos, iVert.texCoord0);
	N = normalize(TBN * mapN);

	// --- roughness: 0 = mirror sharp (matches current look exactly), 1 = fully blurred/soft ---
	float roughness = clamp(texture(sRoughnessMap, iVert.texCoord0).r * uRoughness.x, 0.0, 1.0);
	float envLod = roughness * uMaxenvlod.x;
	float bgLod = roughness * uMaxbglod.x;
	float specPowerEff = mix(uSpecpower.x, 4.0, roughness);

	vec3 V = normalize(uTDMats[0].camInverse[3].xyz - iVert.worldSpacePos);

	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	float fresnel = pow(1.0 - NdotV, uFresnelpower.x);

	// --- reflection, with a cheap per-channel chromatic split (fake dispersion) ---
	vec3 Rr = reflect(-V, N);
	vec3 Rg = normalize(reflect(-V, N + 0.0 * N));
	vec3 Rb = Rr;

	float disp = (uIor.x - 1.0) * 0.08;
	vec3 Rchroma_r = normalize(Rr - disp * N);
	vec3 Rchroma_b = normalize(Rb + disp * N);

	float envR = textureLod(sEnvMap, envUV(Rchroma_r), envLod).r;
	float envG = textureLod(sEnvMap, envUV(Rr), envLod).g;
	float envB = textureLod(sEnvMap, envUV(Rchroma_b), envLod).b;
	vec3 envColor = vec3(envR, envG, envB);

	// --- refraction: bend the background behind the glass through the surface normal,
	// with a per-channel offset so the fringe separates like real dispersion ---
	vec2 screenUV = gl_FragCoord.xy / vec2(textureSize(sBackground, 0));
	vec2 offR = N.xy * uRefractstrength.x * (1.0 + uChromaspread.x);
	vec2 offG = N.xy * uRefractstrength.x;
	vec2 offB = N.xy * uRefractstrength.x * (1.0 - uChromaspread.x);
	vec3 refrColor;
	refrColor.r = textureLod(sBackground, clamp(screenUV + offR, 0.0, 1.0), bgLod).r;
	refrColor.g = textureLod(sBackground, clamp(screenUV + offG, 0.0, 1.0), bgLod).g;
	refrColor.b = textureLod(sBackground, clamp(screenUV + offB, 0.0, 1.0), bgLod).b;
	refrColor *= uTintcolor.xyz;
	// frosted haze: real frosted glass doesn't just blur what's behind it, it also scatters
	// light back out toward a soft white — fresnel-weighted so it shows more at the rim
	refrColor = mix(refrColor, vec3(1.0), roughness * uFrostmilk.x * (0.3 + 0.7 * fresnel));

	// --- body: face-on shows refracted background, grazing angle shows full env reflection ---
	vec3 base = mix(refrColor, envColor, fresnel * uReflectivity.x + (1.0 - uReflectivity.x) * 0.15);

	// --- thin-film iridescence, strongest right at the fresnel edge ---
	vec3 irid = texture(sIridLut, vec2(fresnel, 0.5)).rgb;
	base += irid * uIridamount.x * fresnel;

	// --- rim light add, same fresnel curve as the reference stripes/glints ---
	base += uRimcolor.xyz * fresnel;

	// --- specular hotspot ---
	vec3 H = normalize(V + normalize(uLightdir.xyz));
	float spec = pow(clamp(dot(N, H), 0.0, 1.0), specPowerEff);
	base += vec3(spec);

	vec4 outColor = TDOutputSwizzle(vec4(base, 1.0));
	oFragColor[0] = outColor;
}

/*
On the GLSL MAT's Vectors page, add 11 rows. Every row is a vec4 — type the Name as the
FULL uniform name, prefix included (don't rely on TD to auto-prepend "u" — on some builds
it silently doesn't, and the uniform just reads as zero at runtime with no warning). Fill
in only the first N value boxes listed; leave the rest at 0, they're never read:

  Name field (exact)   Fill in (x, y, z)         Notes
  ----------------------------------------------------------------------
  uTintcolor           0.9, 0.95, 0.95            transmitted-light tint (colored glass)
  uRimcolor            0, 1, 0.9                  cyan for ref 1, try 1, 0.6, 0.3 for ref 3
  uFresnelpower        3.0                        2 = soft falloff, 6 = tight hard rim
  uIor                 1.3                        1.0 = no dispersion, 1.6 = strong fringe
  uReflectivity        0.9                        push to 1.0 for the near-mirror look
  uIridamount          0.4                        0 for ref 1/3, ~0.4-0.6 for ref 2 (bubbles)
  uSpecpower           200
  uEnvrotate           0
  uLightdir            0.3, 0.6, 0.4              direction TO the key light
  uRefractstrength     0.08                       0 = no see-through, 0.15-0.3 = heavy bend
  uChromaspread        0.35                       0 = no fringe, 1 = wide rainbow fringe
  uNormalstrength      0                          0 = off (safe default). ~0.1-0.4 once
                                                   sNormalMap is wired — higher reads as
                                                   heavily bumped/etched glass fast
  uRoughness           0                          0 = mirror sharp (safe default). try
                                                   0.1-0.3 for "polished but not perfect"
  uMaxenvlod           8                          match this to log2(sEnvMap's resolution),
                                                   e.g. a 1024px-tall env map -> ~10
  uMaxbglod            8                          same idea for sBackground — match to
                                                   log2(background_render's resolution)
  uFrostmilk           0                          0 = off. ~0.3-0.6 with uRoughness up at
                                                   ~0.4-0.7 gives a real frosted-glass look

On the Samplers page, add 5 rows, Name as the full name including the "s" prefix:
  sEnvMap       -> a Ramp TOP (vertical gradient) or Movie File In (HDRI), Equirect UV.
                   MUST have mipmaps enabled (Common page) or uRoughness blur does nothing.
  sIridLut      -> a small horizontal rainbow-gradient Ramp TOP (blue -> magenta -> gold -> blue)
  sBackground   -> the background Render TOP (scene rendered WITHOUT the glass geometry),
                   Pixel Format match, Extend U/V set to Clamp
  sNormalMap    -> a tangent-space normal map (Noise TOP -> a normal-map-style filter, or a
                   loaded texture). Needs the geometry to actually carry UVs.
  sRoughnessMap -> a grayscale texture, white = rough/soft, black = sharp/mirror. Optional —
                   leave it unwired and drive roughness with uRoughness.x alone if you don't
                   need it to vary across the surface.

If a sphere/geometry comes back black or a texture reads as zero despite everything looking
wired correctly, don't trust the Info DAT's "unassigned" warning as the final word — it only
checks that *some* name is typed in a row, not that it's spelled right or still resolves to
a live TOP. Isolate with a throwaway shader that outputs just that one value, e.g.
`oFragColor[0] = vec4(texture(sBackground, vec2(0.5)).rgb, 1.0);` — if that alone is black,
the binding is the problem, not the real shader logic.
*/
