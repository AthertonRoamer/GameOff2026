shader_type canvas_item;

// A screen-space pixel art pass: the picture underneath is drawn in big square pixels, its colours are cut down to a few levels per channel with an
// ordered (Bayer) dither so gradients become the stippled bands of old pixel art, and pixels that differ a lot from the one above or beside them get
// a dark edge, like an outline. Everything is in screen pixels, so the pixel size stays the same when the window is resized.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float pixel_size : hint_range(1.0, 16.0) = 4.0;
uniform float levels : hint_range(2.0, 64.0) = 24.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.6;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.35;
uniform float saturation : hint_range(0.0, 2.0) = 1.15;
uniform float contrast : hint_range(0.5, 2.0) = 1.05;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	// the 4x4 Bayer matrix, 0..15
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return float(m[i]) / 16.0 - 0.5;
}

vec3 sample_cell(vec2 cell, vec2 res) {
	vec2 uv = (cell + 0.5) * pixel_size / res;
	return texture(screen_tex, uv).rgb;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(SCREEN_UV * res / pixel_size);
	vec3 c = sample_cell(cell, res);

	// outline: compare with the cell above and to the left
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float up = dot(sample_cell(cell + vec2(0.0, -1.0), res), vec3(0.299, 0.587, 0.114));
	float left = dot(sample_cell(cell + vec2(-1.0, 0.0), res), vec3(0.299, 0.587, 0.114));
	float edge = clamp((max(abs(lum - up), abs(lum - left)) - 0.06) * 6.0, 0.0, 1.0);
	c *= 1.0 - edge * edge_strength;

	// grade, then cut the colour down with a dither
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(grey), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c += bayer4(cell) * dither_strength / levels;
	c = floor(c * levels + 0.5) / levels;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
