#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Pixel sun: a grid of rounded square "pixels" lit by an organic, noise-driven disc.
// Heat is banded into Mistral's five rainbow colours (yellow core → red rim), so the
// shape always reads as the brand's stripes even while it moves.
//
// Moods (0…1, blended on the Swift side):
//   connect — an amber comet orbits the rim
//   listen  — rings drift inward, the disc leans toward the user's voice
//   think   — a slow spiral of heat swirls through the core
//   speak   — rings radiate outward with the agent's voice

constant half3 kYellow = half3(1.000h, 0.847h, 0.000h); // #FFD800
constant half3 kAmber  = half3(1.000h, 0.686h, 0.000h); // #FFAF00
constant half3 kOrange = half3(1.000h, 0.510h, 0.020h); // #FF8205
constant half3 kFlame  = half3(0.980h, 0.314h, 0.059h); // #FA500F
constant half3 kRed    = half3(0.882h, 0.020h, 0.000h); // #E10500
constant half3 kDust   = half3(1.000h, 0.980h, 0.922h); // #FFFAEB

static float hash31(float3 p) {
    p = fract(p * float3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

static float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i);
    float n100 = hash31(i + float3(1, 0, 0));
    float n010 = hash31(i + float3(0, 1, 0));
    float n110 = hash31(i + float3(1, 1, 0));
    float n001 = hash31(i + float3(0, 0, 1));
    float n101 = hash31(i + float3(1, 0, 1));
    float n011 = hash31(i + float3(0, 1, 1));
    float n111 = hash31(i + float3(1, 1, 1));
    return mix(
        mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
        mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
        u.z);
}

static float fbm(float3 p) {
    float sum = 0.0;
    float amplitude = 0.55;
    for (int octave = 0; octave < 3; octave++) {
        sum += amplitude * noise3(p);
        p = p * 2.03 + 7.1;
        amplitude *= 0.5;
    }
    return sum; // ~0…0.96
}

// 0 = rim (red) … 1 = core (yellow), quantised into the five bands.
static half3 rainbow(float heat) {
    int band = int(clamp(floor(heat * 5.0), 0.0, 4.0));
    switch (band) {
        case 4: return kYellow;
        case 3: return kAmber;
        case 2: return kOrange;
        case 1: return kFlame;
        default: return kRed;
    }
}

[[ stitchable ]] half4 pixelSun(
    float2 position, half4 color,
    float2 size, float time, float cell,
    float energy, float connect, float listen, float think, float speak
) {
    // Cell geometry: every pixel in a cell shares one sample, so the image is truly pixelated.
    float2 index = floor(position / cell);
    float2 center = (index + 0.5) * cell;
    float2 local = position / cell - index - 0.5;           // -0.5…0.5 inside the cell
    float corner = 0.10;
    float2 q = abs(local) - (0.5 - 0.11 - corner);          // 11% gap on each side
    float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
    float aa = 1.0 / cell;
    float mask = 1.0 - smoothstep(-aa, aa, sdf);

    float radius = 0.5 * min(size.x, size.y);
    float2 p = (center - 0.5 * size) / radius;              // -1…1, aspect-correct
    float r = length(p);
    float angle = atan2(p.y, p.x);

    // Organic rim: noise sampled on the unit circle so it never tears at the seam.
    float flow = time * (0.18 + 0.30 * speak + 0.12 * listen);
    float2 dir = float2(cos(angle), sin(angle));
    float rimNoise = fbm(float3(dir * 1.35, flow));
    float bodyNoise = fbm(float3(p * 1.8, flow * 1.4 + 3.0));

    float breathe = 0.035 * sin(time * 1.25) * (1.0 - connect * 0.6);
    float core = 0.50 + breathe + 0.13 * energy + 0.05 * listen - 0.06 * connect;
    float edge = core + (rimNoise - 0.45) * (0.20 + 0.32 * energy);
    float body = 1.0 - smoothstep(edge - 0.015, edge + 0.015, r);

    // Heat: hot centre, cooler rim, noise for licks of flame; thinking adds a spiral.
    float heat = 1.0 - r / max(edge, 0.05);
    heat += (bodyNoise - 0.45) * 0.55;
    heat += think * 0.22 * sin(angle * 2.0 - r * 9.0 + time * 3.2);
    heat = clamp(heat * 0.95 + 0.12 + 0.10 * energy, 0.0, 0.999);

    float outside = step(edge, r);
    float falloff = 1.0 - smoothstep(edge, edge + 0.55, r);

    // Speaking: crisp rings travelling outward, brightest close to the disc.
    float outward = smoothstep(0.82, 1.0, sin((r - time * 0.85) * 15.0));
    float speakRings = outward * speak * (0.35 + 0.85 * energy) * falloff * outside;

    // Listening: finer rings drawn inward, as if the sun is taking the voice in.
    float inward = smoothstep(0.86, 1.0, sin((r + time * 0.65) * 21.0));
    float listenRings = inward * listen * (0.20 + 0.90 * energy) * falloff * outside;

    // Connecting: a comet orbits just outside the rim.
    float orbitR = core + 0.20;
    float comet = pow(0.5 + 0.5 * cos(angle - time * 3.4), 18.0);
    float ring = 1.0 - smoothstep(0.0, 0.07, abs(r - orbitR));
    float orbit = comet * ring * connect;

    // Sparks: a few cells near the rim flicker on.
    float spark = step(0.988, hash31(float3(index, floor(time * 9.0))))
                * (1.0 - smoothstep(edge, edge + 0.35, r)) * outside * (0.4 + 0.6 * energy);

    float glow = max(max(speakRings, listenRings), max(orbit, spark));

    // Quantise brightness so halos read as pixel steps rather than gradients.
    float halo = floor(glow * 4.0 + 0.5) / 4.0;

    half3 rgb;
    float alpha;
    if (body > 0.5) {
        rgb = rainbow(heat);
        alpha = 1.0;
    } else if (halo > 0.0) {
        // The corona cools away from the rim (flame → red); the orbiting comet runs hotter.
        float heatOut = 0.05 + 0.30 * (1.0 - smoothstep(edge, edge + 0.45, r)) + 0.50 * orbit;
        rgb = rainbow(clamp(heatOut, 0.0, 0.999));
        alpha = halo;
    } else {
        // Faint dust grid so the pixel structure is always visible.
        // Faded out inside the inscribed circle so the view's square bounds never show.
        float dust = 0.055 * (1.0 - smoothstep(0.35, 0.95, r));
        rgb = kDust;
        alpha = dust;
    }

    float a = alpha * mask;
    return half4(rgb * half(a), half(a)); // premultiplied
}
