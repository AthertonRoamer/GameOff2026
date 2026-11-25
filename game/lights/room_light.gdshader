shader_type canvas_item;
render_mode blend_mul, unshaded;

// Takes a room lamp's light back off where the local player cannot see it. The lamps are real scene lights (RoomLightShapes), the same for everyone, so they light
// the facility the way the flashlight does; but a lit room behind a wall should look dark to someone who has no line of sight to it. PlayerSight draws this over
// each lit lamp's shape (where its light falls), and `sight_mask` (a picture of the screen, white where the local player can see) says where to leave it alone.
//
// Where the player cannot see, the picture is the surface's colour times (darkness + lamp light): this multiplies it by darkness / (darkness + lamp light), which
// leaves the colour times the darkness, as if the lamp were off. The lamp's light at a pixel is worked out the way its texture was made (RoomLightShapes.falloff).
// Drawn with blend_mul, so where two lamps overlap their corrections multiply (close to right, and only where nobody looks).

uniform sampler2D sight_mask : filter_linear;
uniform vec4 ambient : source_color = vec4(0.176, 0.186, 0.248, 1.0);
uniform vec4 light_color : source_color = vec4(0.86, 0.93, 1.0, 1.0);
uniform float energy = 0.8;
uniform vec2 rect_pos;
uniform vec2 rect_size;
uniform float spill = 132.0;

varying vec2 world;

void vertex() {
	world = VERTEX; // drawn by a node at the origin of the world, so a vertex is a world position
}

void fragment() {
	vec2 centre = rect_pos + rect_size * 0.5;
	vec2 half_size = max(rect_size * 0.5, vec2(1.0));
	vec2 q = abs(world - centre);
	vec2 outside = max(q - half_size, vec2(0.0));
	float light = pow(1.0 - clamp(length(outside) / max(spill, 1.0), 0.0, 1.0), 2.0);
	float edge = min(max(q.x / half_size.x, q.y / half_size.y), 1.0); // 0 in the middle of the room, 1 at its walls
	light *= 1.0 - 0.18 * smoothstep(0.35, 1.0, edge);
	float seen = texture(sight_mask, SCREEN_UV).a;
	vec3 dark = max(ambient.rgb, vec3(0.01));
	vec3 off = dark / (dark + light_color.rgb * energy * light);
	COLOR = vec4(mix(off, vec3(1.0), seen), 1.0);
}
