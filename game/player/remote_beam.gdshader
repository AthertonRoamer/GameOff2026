shader_type canvas_item;
render_mode blend_mix;

// Another player's flashlight, drawn to look like the scene's own flashlight light (PointLight2D with game/player/flashlight/flashlight_cone.png): the beam is brightest at
// its lamp and falls off along its length (to the power 1.4, as the cone texture does) and softens towards its sides; the glow round the holder fades outwards.
// Everything is also faded by the local player's view (see PlayerSight.view_strength: a rounded zone round the player that reaches far in the direction of the mouse,
// fading out towards its edge), so a beam is seen only inside the view and fades out at its edges, with no hard cut. The geometry it is drawn on is cut to walls (the beam's
// own shadows and the view's). blend_mix: a beam is laid over the picture by its strength, so beams that cross add up smoothly and never come out brighter than white.
// Players are left out of it (a soft hole round each): they are brightened by the light themselves, see PlayerSight, so they are not seen through a haze.

uniform vec2 origin;
uniform float direction = 0.0;
uniform float beam_range = 484.0;
uniform float half_angle = 0.4887;
uniform float glow_radius = 0.0; // above 0: a glow round `origin` instead of a beam
uniform vec4 beam_color : source_color = vec4(1.0, 0.953, 0.769, 1.0);
uniform float strength = 0.5;
uniform vec2 view_apex;
uniform float view_facing = 0.0;
uniform float view_half = 0.96;
uniform float view_range = 900.0;
uniform float view_near = 16.0;
uniform float fade_start = 0.4;
uniform bool use_view = true;
uniform vec2 bodies[8];
uniform vec2 lying_a[4]; // fallen bodies: each a line from one end to the other, and how wide it is (a hole shaped like the body)
uniform vec2 lying_b[4];
uniform float lying_radius[4];
uniform float body_seen[8]; // how seen each body is, 0 to 1: the hole is that deep, so a player the local player cannot see leaves no hole
uniform float lying_seen[4];
uniform int body_count = 0;

varying vec2 world;

void vertex() {
	world = VERTEX; // drawn by a node at the origin of the world, so a vertex is a world position
}

float angle_between(float a, float b) {
	float d = a - b;
	return abs(atan(sin(d), cos(d)));
}

// how far the view reaches in a direction: far towards the mouse, only `view_near` to the sides and behind, smoothly in between
float view_reach(float angle) {
	float forward = 1.0 - smoothstep(view_half * 0.3, view_half * 1.2, angle_between(angle, view_facing));
	return view_near + (view_range - view_near) * forward;
}

float view_fade(vec2 p) {
	if (!use_view) {
		return 1.0;
	}
	vec2 d = p - view_apex;
	float dist = length(d);
	if (dist < 1.0) {
		return 1.0;
	}
	float reach = view_reach(atan(d.y, d.x));
	return 1.0 - smoothstep(reach * fade_start, reach, dist);
}

void fragment() {
	vec2 o = world - origin;
	float d = length(o);
	float light;
	if (glow_radius > 0.0) {
		light = 1.0 - smoothstep(0.0, glow_radius, d);
	} else {
		float along = pow(max(1.0 - d / beam_range, 0.0), 1.4);
		float side = 1.0 - smoothstep(half_angle * 0.55, half_angle, angle_between(atan(o.y, o.x), direction));
		light = along * side;
	}
	float keep = 1.0;
	for (int i = 0; i < 8; i++) {
		if (i >= body_count) {
			break;
		}
		keep *= 1.0 - 0.85 * body_seen[i] * (1.0 - smoothstep(5.0, 13.0, length(world - bodies[i]))); // a hole smaller than the body, so the sprite hides its edge
	}
	for (int i = 0; i < 4; i++) {
		vec2 ab = lying_b[i] - lying_a[i];
		float t = clamp(dot(world - lying_a[i], ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
		float d = length(world - (lying_a[i] + ab * t));
		keep *= 1.0 - 0.85 * lying_seen[i] * (1.0 - smoothstep(lying_radius[i] * 0.7, lying_radius[i], d));
	}	COLOR = vec4(beam_color.rgb, clamp(light * strength * view_fade(world) * keep, 0.0, 1.0));
}