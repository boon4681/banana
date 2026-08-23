#version 330 core
in vec2 v_uv;
in vec4 v_color;
flat in uint v_mode;
out vec4 frag;
uniform sampler2D u_tex;
uniform bool u_has_tex;

float median3(float r, float g, float b) {
	return max(min(r, g), min(max(r, g), b));
}

void main() {
	vec4 c = v_color;
	if (v_mode == 1u) {
		c *= texture(u_tex, v_uv);
	} else if (v_mode == 2u) {
		vec3 sample_rgb = texture(u_tex, v_uv).rgb;
		float signed_distance = median3(sample_rgb.r, sample_rgb.g, sample_rgb.b) - 0.5;
		vec2 unit_range = vec2(4.0) / vec2(textureSize(u_tex, 0));
		vec2 screen_tex_size = vec2(1.0) / fwidth(v_uv);
		float screen_px_range = max(0.5 * dot(unit_range, screen_tex_size), 1.0);
		float coverage = clamp(screen_px_range * signed_distance + 0.5, 0.0, 1.0);
		c.a *= coverage;
	}
	frag = c;
}
