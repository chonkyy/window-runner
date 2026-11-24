shader_type canvas_item;
// Wet-road reflection: mirrors the screen about the feet line (axis_px) into the road strip below it,
// with row-wise ripple, depth fade and world-anchored puddles that reflect more strongly.
// Drawn on a ColorRect covering the road strip, on a CanvasLayer above the world and below the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float axis_px = 620.0;      // feet line (floor_y) in screen px
uniform float strength = 0.4;
uniform float world_x = 0.0;        // camera x, keeps puddles fixed to the road
uniform vec4 tint : source_color = vec4(0.2, 0.22, 0.3, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 px = SCREEN_UV * view_size;
	float depth = px.y - axis_px;
	float d01 = clamp(depth / (view_size.y - axis_px), 0.0, 1.0);
	float row = floor(px.y / 2.0);                       // 2px rows -> chunky ripples
	float wob = sin(row * 1.7 + TIME * 4.0) * (0.5 + 2.5 * d01)
		+ sin(row * 0.55 - TIME * 2.3) * 1.5 * d01;
	vec2 src = vec2(floor(px.x + wob), 2.0 * axis_px - px.y) / view_size;
	vec3 refl = texture(screen_tex, src).rgb;
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	float puddle = smoothstep(0.45, 0.7, noise(vec2((px.x + world_x) * 0.007, row * 0.09)));
	float a = strength * (1.0 - d01 * 0.85) * (0.35 + 0.65 * puddle);
	refl = mix(refl, tint.rgb, 0.3);
	COLOR = vec4(mix(base, refl, a), 1.0);
}
