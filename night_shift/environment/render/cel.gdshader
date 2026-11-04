shader_type spatial;
render_mode unshaded, cull_back;

// The character renderer's cel material (source/anim.py in the Night Shift sprite kit), ported: the shade is dot(world normal, LIGHT),
// cut into three hard bands, shadow below 0.38, base up to 0.9, highlight above. LIGHT there is (0.42, -0.42, 0.80) with the camera
// turned half a circle, which puts the light up and to the top left of the picture. Here the picture's up is -Z and its right is +X.
uniform vec3 shadow_color : source_color = vec3(0.1);
uniform vec3 base_color : source_color = vec3(0.2);
uniform vec3 highlight_color : source_color = vec3(0.3);
uniform vec3 light_dir = vec3(-0.42, 0.80, -0.42);

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float d = dot(n, normalize(light_dir));
	vec3 c = highlight_color;
	if (d < 0.9) {
		c = base_color;
	}
	if (d < 0.38) {
		c = shadow_color;
	}
	ALBEDO = c;
}
