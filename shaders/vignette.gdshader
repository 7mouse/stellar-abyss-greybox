shader_type canvas_item;

uniform float strength = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float v = smoothstep(0.45, 1.15, length(p));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
