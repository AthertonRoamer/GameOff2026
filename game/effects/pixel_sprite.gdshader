shader_type canvas_item;

// The pixel art shader you pasted, run over the whole screen. The picture is redrawn on a coarse grid of square pixels, and each pixel is then
// replaced by the colour of the neighbour (of its 8) that it looks most like (the "bender" mix at 0), which cleans up soft edges and single stray
// pixels. Same maths as the pasted version, but reading the finished frame instead of one sprite's texture, so the grid is in screen pixels and
// there is no node rotation to follow.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float pixel_size : hint_range(1.0, 16.0) = 4.0; // one big pixel, in screen pixels
uniform float bender : hint_range(0.0, 1.0) = 0.0;

vec3 cell_colour(vec2 cell, vec2 res) {
	return texture(screen_tex, (cell + 0.5) * pixel_size / res).rgb;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(SCREEN_UV * res / pixel_size);

	vec3 color_c = cell_colour(cell, res);
	vec3 color_up = cell_colour(cell + vec2(0.0, -1.0), res);
	vec3 color_down = cell_colour(cell + vec2(0.0, 1.0), res);
	vec3 color_right = cell_colour(cell + vec2(1.0, 0.0), res);
	vec3 color_left = cell_colour(cell + vec2(-1.0, 0.0), res);
	vec3 color_up_right = cell_colour(cell + vec2(1.0, -1.0), res);
	vec3 color_down_right = cell_colour(cell + vec2(1.0, 1.0), res);
	vec3 color_down_left = cell_colour(cell + vec2(-1.0, 1.0), res);
	vec3 color_up_left = cell_colour(cell + vec2(-1.0, -1.0), res);

	float l1 = length(color_c - color_up);
	float l2 = length(color_c - color_down);
	float l3 = length(color_c - color_right);
	float l4 = length(color_c - color_left);
	float l5 = length(color_c - color_up_right);
	float l6 = length(color_c - color_down_right);
	float l7 = length(color_c - color_down_left);
	float l8 = length(color_c - color_up_left);

	float min_l = min(min(min(l1, l2), min(l3, l4)), min(min(l5, l6), min(l7, l8)));

	vec3 result = color_c;
	result = abs(min_l - l1) < 0.00001 ? mix(color_up, color_c, bender) : color_c;
	result = abs(min_l - l2) < 0.00001 ? mix(color_down, result, bender) : result;
	result = abs(min_l - l3) < 0.00001 ? mix(color_right, result, bender) : result;
	result = abs(min_l - l4) < 0.00001 ? mix(color_left, result, bender) : result;
	result = abs(min_l - l5) < 0.00001 ? mix(color_up_right, result, bender) : result;
	result = abs(min_l - l6) < 0.00001 ? mix(color_down_right, result, bender) : result;
	result = abs(min_l - l7) < 0.00001 ? mix(color_down_left, result, bender) : result;
	result = abs(min_l - l8) < 0.00001 ? mix(color_up_left, result, bender) : result;

	COLOR = vec4(result, 1.0);
}
