#version 330 core
in vec2 v_uv;
in vec4 v_color;
out vec4 frag;
uniform sampler2D u_tex;
uniform bool u_has_tex;
void main() {
	vec4 c = v_color;
	if (u_has_tex) c *= texture(u_tex, v_uv);
	frag = c;
}
