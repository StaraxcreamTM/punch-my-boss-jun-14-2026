shader_type canvas_item;

// Turns the photographic office into a flatter, illustrated "cartoon" backdrop:
// posterizes colours into bands, boosts saturation, and adds a subtle warm push.

uniform float levels : hint_range(2.0, 32.0) = 9.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.25;
uniform float warmth : hint_range(-0.1, 0.1) = 0.02;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Posterize into flat colour bands.
	c.rgb = floor(c.rgb * levels + 0.5) / levels;
	// Punch up saturation.
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(g), c.rgb, saturation);
	// Slight warm grade.
	c.r += warmth;
	c.b -= warmth;
	COLOR = c;
}
