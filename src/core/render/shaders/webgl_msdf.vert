#version 300 es
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;
uniform vec2 u_resolution;
uniform mat3 u_transform;
out vec2 v_uv;
out vec4 v_color;
void main() {
	vec2 pos = (u_transform * vec3(a_pos, 1.0)).xy;
	vec2 ndc = vec2(pos.x / u_resolution.x * 2.0 - 1.0,
	                1.0 - pos.y / u_resolution.y * 2.0);
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_uv = a_uv;
	v_color = a_color;
}
