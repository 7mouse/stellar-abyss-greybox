shader_type canvas_item;

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
	vec2 p = SCREEN_UV - vec2(0.5);
	p.x *= 1.7777778;
	float dist = length(p);
	float vig = smoothstep(vignette_radius, vignette_radius + max(vignette_soft, 0.01), dist) * vignette;
	float fg = smoothstep(fog_start, fog_start + 0.9, dist) * fog;
	float a = clamp(vig + fg, 0.0, 1.0);
	vec3 col = mix(vignette_color.rgb, fog_color.rgb, fg / max(vig + fg, 0.001));
	COLOR = vec4(col, a);
}
