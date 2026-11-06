#version 300 es
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;
layout(location = 3) in highp uint a_mode;
out vec2 v_uv;
out vec4 v_color;
out float v_kind;
out float v_inner;
uniform vec2 u_resolution;
uniform mat3 u_transform;
void main() {
	vec2 pos = (u_transform * vec3(a_pos, 1.0)).xy;
	vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
	ndc.y = -ndc.y;
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_uv = a_uv;
	v_color = a_color;
	v_kind = float(a_mode & 0xFFFFu);
	v_inner = float(a_mode >> 16) / 65535.0;
}
