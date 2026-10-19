#version 300 es
// Inverted colours, for Settings > Appearance > Color filter: light text on
// dark for a page that has no dark mode. See grayscale.frag for how Hyprland
// runs it.
precision mediump float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 pixel = texture(tex, v_texcoord);
    fragColor = vec4(vec3(1.0) - pixel.rgb, pixel.a);
}
