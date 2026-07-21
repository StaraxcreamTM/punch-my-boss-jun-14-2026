shader_type canvas_item;

// Draws a bold cartoon outline around a sprite's silhouette so the boss reads
// as a drawn character sitting on top of the background.

uniform vec4 outline_color : source_color = vec4(0.09, 0.06, 0.11, 1.0);
uniform float width : hint_range(0.0, 8.0) = 3.5;

// --- skin recolouring -------------------------------------------------------
// Folded into this shader rather than a second one because a Sprite2D has only
// one material slot and every cutout piece already needs the outline.
// Skin is detected by hue/saturation/value rather than an RGB distance: the art
// has several skin shades (lit, shadowed, outlined), and a flat distance test
// either misses the shadows or bleeds into the khaki. Hair and glasses are
// excluded by the value floor - they're much darker than any skin tone.
uniform bool skin_enabled = false;
// The art's own skin tone, sampled from the source pngs (205,158,116).
// NOTE: deliberately NOT `source_color` - that hint makes Godot convert the
// value to linear space before it reaches the shader, but the HSV maths here
// works on the raw sRGB values sampled from the art.
uniform vec3 skin_base = vec3(0.804, 0.620, 0.455);
uniform vec3 skin_target = vec3(0.804, 0.620, 0.455);
uniform float skin_hue_lo = 0.015;
uniform float skin_hue_hi = 0.115;
uniform float skin_sat_min = 0.14;
uniform float skin_val_min = 0.40;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec4 recolour_skin(vec4 c) {
	if (!skin_enabled || c.a < 0.01) {
		return c;
	}
	vec3 hsv = rgb2hsv(c.rgb);
	if (hsv.x < skin_hue_lo || hsv.x > skin_hue_hi
			|| hsv.y < skin_sat_min || hsv.z < skin_val_min) {
		return c;
	}
	// Carry this pixel's shading across: take its saturation and value as
	// RATIOS against the art's base skin tone, then apply those ratios to the
	// target tone. Shadows stay proportionally dark instead of flattening.
	vec3 base = rgb2hsv(skin_base);
	vec3 t = rgb2hsv(skin_target);
	float s = clamp(hsv.y * (t.y / max(base.y, 0.001)), 0.0, 1.0);
	float v = clamp(hsv.z * (t.z / max(base.z, 0.001)), 0.0, 1.0);
	return vec4(clamp(hsv2rgb(vec3(t.x, s, v)), vec3(0.0), vec3(1.0)), c.a);
}

void fragment() {
	vec4 c = recolour_skin(texture(TEXTURE, UV));
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
