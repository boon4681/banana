#version 300 es
precision highp float;
uniform sampler2D u_tex;
out vec4 frag;
vec3 linear_to_srgb(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
    // sampling the sRGB texture decode the stored linear premultiplied color
    vec4 c = texelFetch(u_tex, ivec2(gl_FragCoord.xy), 0);
    vec3 straight = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);
    frag = vec4(linear_to_srgb(straight) * c.a, c.a);
}
