shader_type canvas_item;
// 预警：圆 / 线 / 扇。底色 #7A2A2A，边缘 #C8584A。stroke_tex 可选。

uniform float shape_id = 0.0;
uniform float fill = 0.0;
uniform vec4 base_color : source_color = vec4(0.478431, 0.164706, 0.164706, 0.18);
uniform vec4 rim_color : source_color = vec4(0.784314, 0.345098, 0.290196, 0.4);
uniform float arc_deg = 90.0;
uniform float use_stroke = 0.0;
uniform sampler2D stroke_tex : repeat_enable, filter_linear;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float inside = 0.0;
	float rim = 0.0;
	if (shape_id < 0.5) {
		float d = length(p);
		inside = 1.0 - smoothstep(0.96, 1.0, d);
		rim = smoothstep(0.82, 0.94, d) * inside;
	} else if (shape_id < 1.5) {
		float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
		inside = 1.0;
		rim = 1.0 - smoothstep(0.0, 0.18, edge);
	} else {
		float d = length(p);
		float ang = atan(p.y, p.x);
		float half_arc = radians(arc_deg) * 0.5;
		float in_arc = 1.0 - smoothstep(half_arc - 0.02, half_arc, abs(ang));
		inside = in_arc * (1.0 - smoothstep(0.96, 1.0, d));
		rim = in_arc * smoothstep(0.82, 0.94, d) * (1.0 - smoothstep(0.96, 1.02, d));
	}
	vec4 col = vec4(base_color.rgb, base_color.a * inside);
	col = mix(col, vec4(rim_color.rgb, rim_color.a), rim);
	if (use_stroke > 0.5) {
		col.rgb *= texture(stroke_tex, UV).rgb;
	}
	COLOR = col;
}
