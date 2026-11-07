// TouchDesigner GLSL MAT — Vertex shader
// Standard TD boilerplate: deforms the SOP, passes world-space P/N + UV to the pixel shader.

// P, N, Cd, uv[] are auto-declared by TD from the SOP's attributes — don't redeclare them.

out Vertex {
	vec4 color;
	vec3 worldSpacePos;
	vec3 worldSpaceNorm;
	vec2 texCoord0;
} oVert;

void main()
{
	vec4 worldSpacePos = TDDeform(P);
	vec3 uvUnwrapCoord = TDInstanceTexCoord(TDUVUnwrapCoord());
	gl_Position = TDWorldToProj(worldSpacePos, uvUnwrapCoord);

	oVert.worldSpacePos = worldSpacePos.xyz;
	oVert.worldSpaceNorm = TDDeformNorm(N);
	oVert.color = Cd;
	oVert.texCoord0.st = uv[0].st;
}
