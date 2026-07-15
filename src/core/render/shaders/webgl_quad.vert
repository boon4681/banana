#version 300 es
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;
out vec2 v_uv;
out vec4 v_color;
uniform vec2 u_resolution;
void main() {
	vec2 ndc = (a_pos / u_resolution) * 2.0 - 1.0;
	ndc.y = -ndc.y;
	gl_Position = vec4(ndc, 0.0, 1.0);
	v_uv = a_uv;
	v_color = a_color;
}
