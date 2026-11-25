shader_type canvas_item;

// The lighting of a piece of furniture's top. A flashlight shines on the top of a desk as it does on the floor; the top of something much taller than a player (a rack, a
// locker, a fridge) is out of the beam's reach and catches only part of it: `top_light` is how much of every light it takes, 1 for all of it (this is the engine's own lighting)
// and less for a taller piece. The level's darkness (ambient) is not changed, only the lights on it.

uniform float top_light : hint_range(0.0, 1.0) = 1.0;

void light() {
	LIGHT = vec4(LIGHT_COLOR.rgb * COLOR.rgb * LIGHT_COLOR.a * top_light, LIGHT_COLOR.a);
}
