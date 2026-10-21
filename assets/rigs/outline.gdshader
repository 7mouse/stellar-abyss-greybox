shader_type canvas_item;
render_mode unshaded;

// 整只角色合成后再描一圈，盖住 AI 直出的锯齿和接缝（拆件规范 §12）。
uniform vec4 outline_color : source_color = vec4(0.16, 0.11, 0.08, 1.0);
uniform float outline_width : hint_range(0.5, 4.0) = 1.5;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
	float ring = base.a;
	ring = max(ring, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(px.x, px.y) * 0.707).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.707).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.707).a);
	ring = max(ring, texture(TEXTURE, UV + vec2(-px.x, -px.y) * 0.707).a);
	if (base.a > 0.12) {
		COLOR = base;
	} else {
		COLOR = vec4(outline_color.rgb, smoothstep(0.05, 0.45, ring) * outline_color.a);
	}
}
