shader_type canvas_item;
// 品质边框：0 灰、1 苔绿、2 青、3 紫、4 金。金级 flow_speed 流光。

uniform float tier = 0.0;
uniform float flow_speed = 0.25;
uniform float time_sec = 0.0;

vec3 tier_color(float t) {
	if (t < 0.5) {
		return vec3(0.55, 0.55, 0.55);
	}
	if (t < 1.5) {
		return vec3(0.45, 0.72, 0.32);
	}
	if (t < 2.5) {
		return vec3(0.25, 0.78, 0.82);
	}
	if (t < 3.5) {
		return vec3(0.62, 0.32, 0.82);
	}
	return vec3(0.93, 0.74, 0.28);
}

void fragment() {
	vec3 c = tier_color(tier);
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border = 1.0 - smoothstep(0.0, 0.14, edge);
	if (tier >= 3.5) {
		float flow = 0.5 + 0.5 * sin((UV.x + UV.y) * 6.283185 + time_sec * flow_speed * 6.283185);
		c = mix(c, vec3(1.0, 0.92, 0.55), flow * border);
	}
	COLOR = vec4(c, border);
}
