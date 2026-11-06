#version 300 es
precision highp float;
in vec2 v_uv;
in vec4 v_color;
in float v_kind;
in float v_inner;
out vec4 frag;
uniform sampler2D u_tex;
uniform bool u_has_tex;
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

float edge_coverage() {
	vec2 e = min(v_uv, 1.0 - v_uv) / max(fwidth(v_uv), vec2(1e-6)) + 0.5;
	return clamp(e.x, 0.0, 1.0) * clamp(e.y, 0.0, 1.0);
}

// convert an sRGB color to linear, alpha and coverage are already linear
vec3 srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void main() {
	vec4 c = v_color;
	int mode = int(v_kind + 0.5);
	if (mode == 3) {
		float d = length(v_uv);
		vec2 normal = v_uv / max(d, 1e-6);
		vec2 gradient = vec2(dot(normal, dFdx(v_uv)), dot(normal, dFdy(v_uv)));
		float px = max(length(gradient), 1e-6);
		float dist = (1.0 - d) / px;
		float coverage;
		if (v_inner > 0.0) {
			// evaluate the ring once, separate edge fades lose coverage on thin strokes
			dist = min(dist, (d - v_inner) / px);
			float width = min((1.0 - v_inner) / px, 1.0);
			coverage = clamp(width * (dist + 1.0 - 0.5 * width), 0.0, 1.0);
		} else {
			coverage = clamp(dist + 0.5, 0.0, 1.0);
		}
		c.a *= coverage;
	} else if (mode == 4) {
		c.a *= edge_coverage();
	} else if (mode == 5) {
		c *= texture(u_tex, clamp(v_uv, 0.0, 1.0));
		c.a *= edge_coverage();
	} else if (mode == 6) {
		c.a *= 1.0 - smoothstep(v_inner, 1.0, length(v_uv));
	} else if (u_has_tex) {
		c *= texture(u_tex, v_uv);
	}
	if (u_clip_count > 0) c.a *= clip_coverage();
	c.rgb = srgb_to_linear(c.rgb);
	frag = c;
}
