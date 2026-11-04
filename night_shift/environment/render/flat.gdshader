shader_type spatial;
render_mode unshaded, cull_back;

// A flat colour with no shading: screens, status lights, anything that glows.
uniform vec3 flat_color : source_color = vec3(1.0);

void fragment() {
	ALBEDO = flat_color;
}
