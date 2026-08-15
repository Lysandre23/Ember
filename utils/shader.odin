package utils

SHADER :: `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

uniform float screenHeight;
uniform float intensity;   // force de l'assombrissement des lignes (0.0 a 1.0)
uniform float lineSpacing; // espacement des lignes en pixels (2.0 = classique)

out vec4 finalColor;

void main()
{
    vec4 texelColor = texture(texture0, fragTexCoord);

    float pixelY = fragTexCoord.y * screenHeight;
    float line = mod(pixelY, lineSpacing);

    // une ligne sombre nette toutes les "lineSpacing" pixels
    float darken = (line < 1.0) ? (1.0 - intensity) : 1.0;

    finalColor = vec4(texelColor.rgb * darken, texelColor.a) * colDiffuse * fragColor;
}
`