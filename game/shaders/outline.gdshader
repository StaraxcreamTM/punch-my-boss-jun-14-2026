shader_type canvas_item;

// Draws a bold cartoon outline around a sprite's silhouette so the boss reads
// as a drawn character sitting on top of the background.

uniform vec4 outline_color : source_color = vec4(0.09, 0.06, 0.11, 1.0);
uniform float width : hint_range(0.0, 8.0) = 3.5;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float o = 0.0;
	o = max(o, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	o = max(o, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
	o = max(o, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	o = max(o, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
	o = max(o, texture(TEXTURE, UV + px).a);
	o = max(o, texture(TEXTURE, UV - px).a);
	o = max(o, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	o = max(o, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	if (c.a < 0.5 && o > 0.5) {
		COLOR = outline_color;
	} else {
		COLOR = c;
	}
}
