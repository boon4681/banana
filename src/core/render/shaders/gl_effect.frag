#version 330 core
in vec2 v_uv;
in vec4 v_color;
out vec4 frag;
uniform sampler2D u_tex;
uniform mat4 u_color;
uniform vec4 u_offset;
uniform vec2 u_step;
uniform int u_taps;
uniform float u_sigma;
uniform vec4 u_tint;
uniform bool u_shadow;
uniform int u_clip_count;
uniform mat3 u_clip[4];
uniform vec2 u_clip_size[4];
uniform vec4 u_clip_radius[4];
uniform vec4 u_clip_radius_y[4];

float clip_coverage() {
	float a = 1.0;
	for (int i = 0; i < 4; i++) {
		if (i >= u_clip_count) break;
		vec2 q = (u_clip[i] * vec3(gl_FragCoord.xy, 1.0)).xy;
		vec2 half_size = u_clip_size[i] * 0.5;
		vec2 c = q - half_size;
		vec4 rx = u_clip_radius[i];
		vec4 ry = u_clip_radius_y[i];
		vec2 r = c.x < 0.0 ? (c.y < 0.0 ? vec2(rx.x, ry.x) : vec2(rx.w, ry.w)) : (c.y < 0.0 ? vec2(rx.y, ry.y) : vec2(rx.z, ry.z));
		vec2 d = abs(c) - half_size + r;
		float sd = max(d.x - r.x, d.y - r.y);
		if (d.x > 0.0 && d.y > 0.0 && r.x > 0.0 && r.y > 0.0) {
			vec2 n = d / r;
			float k = length(n);
			sd = (k - 1.0) * k / max(length(n / r), 1e-6);
		}
		a *= clamp(0.5 - sd, 0.0, 1.0);
	}
	return a;
}

// convert an sRGB color to linear, alpha and coverage are already linear
vec3 srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
	vec4 sum = texture(u_tex, v_uv);
	if (u_taps > 0) {
		float total = 1.0;
		for (int i = 1; i <= 24; i++) {
			if (i > u_taps) break;
			float w = exp(-0.5 * float(i * i) / (u_sigma * u_sigma));
			sum += (texture(u_tex, v_uv + u_step * float(i)) + texture(u_tex, v_uv - u_step * float(i))) * w;
			total += 2.0 * w;
		}
		sum /= total;
	}
	vec4 c;
	if (u_shadow) {
		vec3 tint = u_tint.a > 0.0 ? srgb_to_linear(u_tint.rgb / u_tint.a) * u_tint.a : vec3(0.0);
		c = vec4(tint, u_tint.a) * sum.a;
	} else {
		vec4 straight = sum.a > 0.0 ? vec4(sum.rgb / sum.a, sum.a) : vec4(0.0);
		// css color matrices work on straight sRGB but layers are stored linear and premultiplied
		straight.rgb = linear_to_srgb(straight.rgb);
		c = clamp(u_color * straight + u_offset, 0.0, 1.0);
		c.rgb = srgb_to_linear(c.rgb);
		c.rgb *= c.a;
	}
	c *= v_color.a;
	if (u_clip_count > 0) c *= clip_coverage();
	frag = c;
}
