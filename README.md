# TouchDesigner Glass/Chrome Shader

A realtime GLSL MAT for TouchDesigner producing a "chrome glass" look: Fresnel-driven environment reflection, fake chromatic dispersion, screen-space refraction, thin-film iridescence, roughness-based blur (with frosted-glass haze), and tangent-space normal mapping without precomputed tangents.

## Download

- **`glassShader.tox`** — the packaged, ready-to-use component. Drag it into any TouchDesigner network, or drop it into your palette folder (`Documents/Derivative/Palette/`) to have it show up in TD's own Palette browser.
- **`glass_vertex.glsl`** / **`glass_pixel.glsl`** — the underlying GLSL MAT source, if you want to build it yourself from a bare GLSL MAT or modify it directly.

## What it does

- **Fresnel-driven reflection** of an equirectangular environment texture (a Ramp TOP or an HDRI), with a fake per-channel chromatic split for a dispersion fringe at the rim.
- **Screen-space refraction** — bends a separately-rendered background (rendered without the glass object) through the surface normal, with its own per-channel chroma spread.
- **Thin-film iridescence**, sampled from a small rainbow LUT by the fresnel value — strongest right at the grazing edge.
- **Roughness**, driving mip-level blur on both the reflection and the refraction (requires mipmaps enabled on the source TOPs), plus an optional frosted-glass milky haze at high roughness.
- **Tangent-space normal mapping** without needing precomputed tangent/bitangent vertex attributes — builds the cotangent frame on the fly from screen-space derivatives (the Schüler technique).
- Rim light and a specular hotspot on top.

## Parameters

All custom uniforms are `vec4` (TD's Vectors page on this build only creates vec4 rows); only the first N components listed are ever read.

| Parameter | Fill in (x, y, z) | Notes |
|---|---|---|
| `uTintcolor` | 0.9, 0.95, 0.95 | Transmitted-light tint (colored glass) |
| `uRimcolor` | 0, 1, 0.9 | Rim light color |
| `uFresnelpower` | 3.0 | 2 = soft falloff, 6 = tight hard rim |
| `uIor` | 1.3 | Drives chromatic dispersion on the reflection, not a physically accurate refraction angle |
| `uReflectivity` | 0.9 | Overall mirror strength at grazing angles |
| `uIridamount` | 0.4 | How much thin-film color shows at the rim |
| `uSpecpower` | 200 | Specular tightness |
| `uEnvrotate` | 0 | Radians, spins the environment reflection |
| `uLightdir` | 0.3, 0.6, 0.4 | World-space direction TO the key light |
| `uRefractstrength` | 0.08 | How far the background bends through the surface normal |
| `uChromaspread` | 0.35 | Refraction R/B separation width |
| `uNormalstrength` | 0 | 0 = off (safe default) |
| `uRoughness` | 0 | 0 = mirror sharp (safe default) |
| `uMaxenvlod` | 8 | Match to log2(env map resolution) |
| `uMaxbglod` | 8 | Match to log2(background render resolution) |
| `uFrostmilk` | 0 | Frosted-glass haze amount at high roughness |

Samplers page: `sEnvMap`, `sIridLut`, `sBackground`, `sNormalMap` (optional), `sRoughnessMap` (optional).

## Known limitations

- Refraction is screen-space and single-bounce: it refracts the background once through the front surface only, with no back-face exit point. Fine for mostly-reflective glass; a thin, clearly-hollow object viewed close-up with low reflectivity would show the difference.
- `uIor` does not drive a physically accurate refraction bend — `uRefractstrength` and `uIor` are two independent knobs (bend amount vs. color-fringe spread), not coupled the way real glass behaves.
- Roughness blur requires mipmaps actually generated on `sEnvMap` and `sBackground` (a separate toggle on each TOP's Common page from the Samplers-page filter setting).

## Usage

1. Build a scene with the glass geometry, a background render pass (same camera, glass object excluded), an environment texture, and optionally an iridescence LUT and normal/roughness maps.
2. Wire everything into the component's Samplers.
3. Dial in the Vectors parameters to taste — see the table above for starting points.

Shared for free use — no license terms attached beyond that.
