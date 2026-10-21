shader_type canvas_item;
// 技能蓄势：#CFE6EE → #5FA8A0，不用纯白。

uniform float fill = 0.0;
uniform vec4 glow_a : source_color = vec4(0.811765, 0.901961, 0.933333, 1.0);
uniform vec4 glow_b : source_color = vec4(0.372549, 0.658824, 0.627451, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 glow = mix(glow_a.rgb, glow_b.rgb, clamp(fill, 0.0, 1.0));
	COLOR = vec4(tex.rgb * glow, tex.a);
}
