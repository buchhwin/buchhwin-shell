#version 300 es
// Color filter for green-weak (deuteranopia) vision, Settings > Appearance > Color filter
// (services/hypr/ScreenEffectsLogic.js). A correction, not a simulation: the
// daltonize method works out what the eye without the one kind of cone sees
// (RGB to LMS cone space, the missing cone's answer rebuilt from the other
// two, back to RGB), takes what that loses and moves it into the channels it
// can still tell apart - so two colours that looked the same differ again.
// The same matrices as the common daltonize filters (Fidaner, Lin and
// Ozguven). See grayscale.frag for how Hyprland runs it. The marks on the
// matrix rows tell the private-data check (scripts/lib/checks.py) that two
// numbers with four decimals here are colour science, not a place.
precision mediump float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

const mat3 rgbToLms = mat3(
    17.8824, 3.45565, 0.0299566, // private-data: public
    43.5161, 27.1554, 0.184309, // private-data: public
    4.11935, 3.86714, 1.46709); // private-data: public
const mat3 lmsToRgb = mat3(
    0.0809444479, -0.0102485335, -0.000365296938, // private-data: public
    -0.130504409, 0.0540193266, -0.00412161469, // private-data: public
    0.116721066, -0.113614708, 0.693511405); // private-data: public

void main() {
    vec4 pixel = texture(tex, v_texcoord);
    vec3 lms = rgbToLms * pixel.rgb;
    // No medium-wavelength (green) cones: M is what L and S say it would be.
    vec3 seen = vec3(lms.x, 0.494207 * lms.x + 1.24827 * lms.z, lms.z);
    vec3 lost = pixel.rgb - lmsToRgb * seen;
    // What the missing cone would have shown, moved into green and blue.
    vec3 shift = vec3(0.0, 0.7 * lost.r + lost.g, 0.7 * lost.r + lost.b);
    fragColor = vec4(clamp(pixel.rgb + shift, 0.0, 1.0), pixel.a);
}
