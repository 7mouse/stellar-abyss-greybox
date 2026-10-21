shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float brightness = -0.14;
uniform float contrast = 1.28;
uniform float vignette = 0.62;
uniform float vignette_radius = 0.48;
uniform float vignette_soft = 0.70;
uniform float fog = 0.40;
uniform float fog_start = 0.28;
uniform vec4 fog_color : source_color = vec4(0.08, 0.10, 0.09, 1.0);
uniform vec4 vignette_color : source_color = vec4(0.01, 0.012, 0.01, 1.0);

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	col = (col - 0.5) * max(contrast, 0.01) + 0.5 + brightness;
	col = clamp(col, vec3(0.0), vec3(1.0));
	vec2 p = SCREEN_UV - vec2(0.5);
	p.x *= 1.7777778;
	float dist = length(p);
	float vig = smoothstep(vignette_radius, vignette_radius + max(vignette_soft, 0.01), dist) * vignette;
	float fg = smoothstep(fog_start, fog_start + 0.9, dist) * fog;
	col = mix(col, vignette_color.rgb, clamp(vig, 0.0, 1.0));
	col = mix(col, fog_color.rgb, clamp(fg, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
