package utils

// Full-screen post-process: CRT scanlines plus a cheap single-pass "neon"
// glow. True bloom needs a downsample/blur pass over a separate bright-pass
// texture; this instead re-samples a small ring around each pixel directly
// on the source texture and only adds back the part of each sample brighter
// than glowThreshold, so it's one pass and only the bright neon lines
// (ship, saws, tracers, bot bodies) bloom instead of the whole frame washing
// out. glowIntensity is kept low by default on purpose — "not too much".
CRT_SHADER :: `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform float screenWidth;
uniform float screenHeight;
uniform float intensity;     // scanline darken strength (0..1)
uniform float lineSpacing;   // px between scanlines
uniform float glowIntensity; // how much of the bloom is added back (0..1)
uniform float glowThreshold; // luminance a sample must clear to bloom at all

out vec4 finalColor;

float luminance(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

void main()
{
    vec2 texel = vec2(1.0 / screenWidth, 1.0 / screenHeight);
    vec4 texelColor = texture(texture0, fragTexCoord);

    vec3 glow = vec3(0.0);
    const int SAMPLES = 8;
    for (int i = 0; i < SAMPLES; i++) {
        float angle = 6.28318530718 * float(i) / float(SAMPLES);
        vec2 offset = vec2(cos(angle), sin(angle)) * texel * 2.5;
        vec3 s = texture(texture0, fragTexCoord + offset).rgb;
        glow += s * smoothstep(glowThreshold, 1.0, luminance(s));
    }
    glow /= float(SAMPLES);

    vec3 color = texelColor.rgb + glow * glowIntensity;

    float pixelY = fragTexCoord.y * screenHeight;
    float line = mod(pixelY, lineSpacing);
    float darken = (line < 1.0) ? (1.0 - intensity) : 1.0;
    color *= darken;

    finalColor = vec4(color, texelColor.a) * colDiffuse * fragColor;
}
`
