shader_type spatial;
render_mode unshaded, cull_back;

// Height pass: the world height of every surface, packed into red and green (16 bits over 0 to 2 m), so the renderer can find where a
// surface steps up and draw the ink outline there. Read back with decode_height() in env_render.gd.
varying float world_height;

void vertex() {
	world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float v = clamp(world_height / 2.0, 0.0, 0.9999);
	float scaled = v * 255.0;
	ALBEDO = vec3(floor(scaled) / 255.0, fract(scaled), 0.0);
}
