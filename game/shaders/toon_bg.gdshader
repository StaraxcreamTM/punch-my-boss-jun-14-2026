shader_type canvas_item;

// Turns the photographic office into an inked cartoon backdrop:
// 1) posterizes colours into flat bands, 2) boosts saturation + brightness,
// 3) adds dark "ink" lines on strong edges (Sobel) for a comic/cel look.

uniform float levels : hint_range(2.0, 32.0) = 9.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.3;
uniform float edge_strength : hint_range(0.0, 3.0) = 1.1;
uniform float edge_width : hint_range(0.5, 3.0) = 1.7;
uniform vec4 ink_color : source_color = vec4(0.05, 0.03, 0.07, 1.0);

const vec3 LW = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE * edge_width;
	vec4 c = texture(TEXTURE, UV);

	// Posterize into flat colour bands.
	c.rgb = floor(c.rgb * levels + 0.5) / levels;
	// Punch up saturation and lift brightness a touch.
	float g = dot(c.rgb, LW);
	c.rgb = mix(vec3(g), c.rgb, saturation);
	c.rgb = clamp(c.rgb * 1.12, 0.0, 1.0);

	// Sobel edge detection on luminance -> ink lines (sampled inline).
	float tl = dot(texture(TEXTURE, UV + ps * vec2(-1.0, -1.0)).rgb, LW);
	float tt = dot(texture(TEXTURE, UV + ps * vec2(0.0, -1.0)).rgb, LW);
	float tr = dot(texture(TEXTURE, UV + ps * vec2(1.0, -1.0)).rgb, LW);
	float ll = dot(texture(TEXTURE, UV + ps * vec2(-1.0, 0.0)).rgb, LW);
	float rr = dot(texture(TEXTURE, UV + ps * vec2(1.0, 0.0)).rgb, LW);
	float bl = dot(texture(TEXTURE, UV + ps * vec2(-1.0, 1.0)).rgb, LW);
	float bb = dot(texture(TEXTURE, UV + ps * vec2(0.0, 1.0)).rgb, LW);
	float br = dot(texture(TEXTURE, UV + ps * vec2(1.0, 1.0)).rgb, LW);
	float gx = -tl - 2.0 * ll - bl + tr + 2.0 * rr + br;
	float gy = -tl - 2.0 * tt - tr + bl + 2.0 * bb + br;
	float edge = sqrt(gx * gx + gy * gy) * edge_strength;
	edge = smoothstep(0.55, 1.1, edge);  // only the bold edges get inked

	c.rgb = mix(c.rgb, ink_color.rgb, edge);
	COLOR = c;
}
