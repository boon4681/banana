#version 330 core
uniform sampler2DMS u_tex;
uniform int u_samples;
out vec4 frag;

void main() {
    // fetching from an sRGB texture decode it, so samples average as light not as stored numbers
    // a blit leave that choice to the driver
    ivec2 at = ivec2(gl_FragCoord.xy);
    vec4 sum = vec4(0.0);
    for (int i = 0; i < u_samples; i++) sum += texelFetch(u_tex, at, i);
    frag = sum / float(u_samples);
}
