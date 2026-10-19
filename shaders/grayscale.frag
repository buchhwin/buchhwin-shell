#version 300 es
// Grayscale, for Settings > Appearance > Color filter (services/hypr/
// ScreenEffectsLogic.js). Hyprland runs it over every finished frame as
// decoration:screen_shader: `tex` is the frame, `v_texcoord` the place in it.
// Rec. 709 luminance - the weights sRGB's own primaries give - so a colour
// keeps the brightness the eye gave it (the mark on that line tells the
// private-data check the three weights are no place).
precision mediump float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 pixel = texture(tex, v_texcoord);
    float luma = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722)); // private-data: public
    fragColor = vec4(vec3(luma), pixel.a);
}
