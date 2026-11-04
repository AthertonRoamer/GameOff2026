shader_type canvas_item;

// Pixel art for a sprite, from the shader you pasted. The sprite is redrawn on a coarse pixel grid and each pixel is replaced by the colour of the
// neighbour it looks most like (the "bender" mix at 0), which cleans up the soft edges that scaling leaves. The grid is kept lined up with the
// screen's axes while the sprite turns (the shader works out the node's rotation and snaps in that frame), so the pixels do not swim.
//
// Changes from the pasted version, so it works on the game's sprites:
//  - the pixel size is set in the sprite's own art pixels (art_pixels_per_pixel), not as a count across the quad, so a 256 px frame and a 353 px frame
//    get pixels of the same size, and non-square textures (the doors) get square pixels
//  - `region` is the part of the texture the sprite shows (an animation frame is a rectangle of a sheet), in 0-1 texture coordinates; the
//    skin sets it every frame. The default is the whole texture
//  - only the node's rotation is used, not its scale (the characters are drawn at 0.25 scale, which the pasted matrix maths does not expect)

uniform float art_pixels_per_pixel = 8.0;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0); // x, y, width, height of the shown part of the texture

varying mat2 rot;
varying mat2 inv_rot;

void vertex() {
	rot = mat2(normalize(MODEL_MATRIX[0].xy), normalize(MODEL_MATRIX[1].xy));
	inv_rot = transpose(rot);
}

void fragment() {
	vec2 region_px = region.zw / TEXTURE_PIXEL_SIZE; // size of the shown part, in art pixels
	vec2 cells = max(floor(region_px / art_pixels_per_pixel + 0.5), vec2(1.0));
	vec2 pixel_size = 1.0 / cells; // one pixel, in the sprite's own 0-1 coordinates

	vec2 local = (UV - region.xy) / region.zw - 0.5;
	vec2 snapped = inv_rot * (floor(rot * (local * cells)) + 0.5) / cells + 0.5;

	vec2 lo = region.xy;
	vec2 hi = region.xy + region.zw;
	vec2 step_uv = pixel_size * region.zw;
	vec2 uv = clamp(region.xy + snapped * region.zw, lo, hi);

	vec4 color_1 = texture(TEXTURE, uv);
	color_1.a = step(0.5, color_1.a);

	vec3 color_c = color_1.rgb;
	vec3 color_up = texture(TEXTURE, clamp(uv + vec2(0.0, step_uv.y), lo, hi)).rgb;
	vec3 color_down = texture(TEXTURE, clamp(uv - vec2(0.0, step_uv.y), lo, hi)).rgb;
	vec3 color_right = texture(TEXTURE, clamp(uv + vec2(step_uv.x, 0.0), lo, hi)).rgb;
	vec3 color_left = texture(TEXTURE, clamp(uv - vec2(step_uv.x, 0.0), lo, hi)).rgb;
	vec3 color_up_right = texture(TEXTURE, clamp(uv + step_uv, lo, hi)).rgb;
	vec3 color_down_right = texture(TEXTURE, clamp(uv + vec2(step_uv.x, -step_uv.y), lo, hi)).rgb;
	vec3 color_down_left = texture(TEXTURE, clamp(uv - step_uv, lo, hi)).rgb;
	vec3 color_up_left = texture(TEXTURE, clamp(uv + vec2(-step_uv.x, step_uv.y), lo, hi)).rgb;

	float l1 = length(color_c - color_up);
	float l2 = length(color_c - color_down);
	float l3 = length(color_c - color_right);
	float l4 = length(color_c - color_left);
	float l5 = length(color_c - color_up_right);
	float l6 = length(color_c - color_down_right);
	float l7 = length(color_c - color_down_left);
	float l8 = length(color_c - color_up_left);

	float min_l = min(min(min(l1, l2), min(l3, l4)), min(min(l5, l6), min(l7, l8)));

	float bender = 0.0;

	COLOR = color_1;
	COLOR = abs(min_l - l1) < 0.00001 ? vec4(mix(color_up, color_c, bender), color_1.a) : color_1;
	COLOR = abs(min_l - l2) < 0.00001 ? vec4(mix(color_down, COLOR.rgb, bender), COLOR.a) : COLOR;
	COLOR = abs(min_l - l3) < 0.00001 ? vec4(mix(color_right, COLOR.rgb, bender), COLOR.a) : COLOR;
	COLOR = abs(min_l - l4) < 0.00001 ? vec4(mix(color_left, COLOR.rgb, bender), COLOR.a) : COLOR;
	COLOR = abs(min_l - l5) < 0.00001 ? vec4(mix(color_up_right, COLOR.rgb, bender), COLOR.a) : COLOR;
	COLOR = abs(min_l - l6) < 0.00001 ? vec4(mix(color_down_right, COLOR.rgb, bender), COLOR.a) : COLOR;
	COLOR = abs(min_l - l7) < 0.00001 ? vec4(mix(color_down_left, COLOR.rgb, bender), COLOR.a) : COLOR;
	COLOR = abs(min_l - l8) < 0.00001 ? vec4(mix(color_up_left, COLOR.rgb, bender), COLOR.a) : COLOR;
}
