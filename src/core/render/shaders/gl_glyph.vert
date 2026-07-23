#version 330 core
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;
layout(location = 3) in uvec2 a_curves;
out vec2 v_uv;
out vec4 v_color;
flat out uvec2 v_curves;
uniform vec2 u_resolution;
uniform mat3 u_transform;
void main() {
	vec2 pos = (u_transform * vec3(a_pos, 1.0)).xy;
	vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
	ndc.y = -ndc.y;
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_uv = a_uv;
	v_color = a_color;
	v_curves = a_curves;
}
