shader_type canvas_item;

// Cinematic vignette: darkens the corners of the scene to focus attention on
// the boss in the centre and give the flat backdrop some depth.

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float radius : hint_range(0.5, 1.5) = 1.15;

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * radius;
	float v = smoothstep(0.55, 1.0, d) * strength;
	COLOR = vec4(0.0, 0.0, 0.0, v);
}
