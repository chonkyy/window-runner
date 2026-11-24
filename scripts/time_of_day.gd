class_name TimeOfDay
extends RefCounted
## Round counter + per-phase lighting presets (design §6). Phase advances every 2 rounds:
## Dawn -> Morning -> Afternoon -> Dusk -> Night -> Dawn. Static, so it survives Game's scene reload
## on restart but resets to Dawn on launch. Everything visual (and the ambience/music) reads TimeOfDay.p().

enum Phase { DAWN, MORNING, AFTERNOON, DUSK, NIGHT }
const NAMES := ["DAWN", "MORNING", "AFTERNOON", "DUSK", "NIGHT"]
const ROUNDS_PER_PHASE := 2

static var round_count := 0               ## incremented by Game._restart
static var force_phase := -1              ## debug override: `godot --path . -- --phase=N`
static var _args_read := false

## sky_*: backdrop gradient. tint: CanvasModulate on the world. far/mid/near: building colours (already
## hazed). haze: fog colour between layers. lamps: street-lamp light energy (0 = off). windows: share of
## lit building windows. reflection: wet-road reflection strength. traffic/birds: spawn-rate multipliers.
## green: backdrop tree lines (already hazed, like far/mid/near).
## Audio (Sound): city/crickets = ambience bed levels, chirps = songbird chirps per second. The music for each
## phase lives in Radio.STATIONS (one song per station per phase).
const PRESETS := [
	{   # DAWN — soft pink-orange haze, empty roads, early birds
		"sky_top": Color(0.33, 0.36, 0.62), "sky_mid": Color(0.86, 0.6, 0.66), "sky_bottom": Color(1.0, 0.76, 0.58),
		"sun": Color(1.0, 0.86, 0.62), "sun_pos": Vector2(0.8, 0.4), "sun_r": 50.0, "moon": false, "stars": 0.0,
		"cloud": Color(1.0, 0.8, 0.78, 0.55),
		"tint": Color(1.0, 0.9, 0.88),
		"far": Color(0.7, 0.55, 0.64), "mid": Color(0.52, 0.4, 0.52), "near": Color(0.34, 0.27, 0.38),
		"haze": Color(1.0, 0.74, 0.62),
		"wire": Color(0.14, 0.11, 0.16), "lamps": 0.45, "windows": 0.12, "reflection": 0.42,
		"refl_tint": Color(0.55, 0.42, 0.5), "rim": false, "traffic": 0.6, "birds": 1.3,
		"city": 0.3, "crickets": 0.0, "chirps": 0.9,
		"green": Color(0.44, 0.5, 0.46),
	},
	{   # MORNING — bright and clear, traffic picking up
		"sky_top": Color(0.3, 0.56, 0.9), "sky_mid": Color(0.56, 0.76, 0.96), "sky_bottom": Color(0.84, 0.93, 1.0),
		"sun": Color(1.0, 0.98, 0.86), "sun_pos": Vector2(0.24, 0.16), "sun_r": 40.0, "moon": false, "stars": 0.0,
		"cloud": Color(1.0, 1.0, 1.0, 0.75),
		"tint": Color(1.0, 1.0, 1.0),
		"far": Color(0.66, 0.76, 0.88), "mid": Color(0.52, 0.6, 0.74), "near": Color(0.4, 0.45, 0.56),
		"haze": Color(0.84, 0.92, 1.0),
		"wire": Color(0.12, 0.12, 0.15), "lamps": 0.0, "windows": 0.0, "reflection": 0.28,
		"refl_tint": Color(0.5, 0.6, 0.72), "rim": false, "traffic": 0.85, "birds": 1.0,
		"city": 0.55, "crickets": 0.0, "chirps": 0.6,
		"green": Color(0.4, 0.6, 0.44),
	},
	{   # AFTERNOON — peak traffic, warm light
		"sky_top": Color(0.28, 0.5, 0.86), "sky_mid": Color(0.62, 0.72, 0.88), "sky_bottom": Color(0.98, 0.88, 0.7),
		"sun": Color(1.0, 0.94, 0.74), "sun_pos": Vector2(0.62, 0.14), "sun_r": 42.0, "moon": false, "stars": 0.0,
		"cloud": Color(1.0, 0.97, 0.9, 0.7),
		"tint": Color(1.0, 0.97, 0.9),
		"far": Color(0.76, 0.72, 0.74), "mid": Color(0.6, 0.54, 0.56), "near": Color(0.46, 0.38, 0.4),
		"haze": Color(0.98, 0.88, 0.72),
		"wire": Color(0.12, 0.11, 0.13), "lamps": 0.0, "windows": 0.0, "reflection": 0.28,
		"refl_tint": Color(0.6, 0.56, 0.55), "rim": false, "traffic": 1.25, "birds": 0.9,
		"city": 0.8, "crickets": 0.0, "chirps": 0.3,
		"green": Color(0.5, 0.58, 0.38),
	},
	{   # DUSK — gradient sky, street lights flickering on, long shadows
		"sky_top": Color(0.16, 0.14, 0.38), "sky_mid": Color(0.72, 0.34, 0.46), "sky_bottom": Color(1.0, 0.56, 0.34),
		"sun": Color(1.0, 0.5, 0.28), "sun_pos": Vector2(0.18, 0.46), "sun_r": 60.0, "moon": false, "stars": 0.15,
		"cloud": Color(0.95, 0.5, 0.5, 0.55),
		"tint": Color(0.86, 0.72, 0.78),
		"far": Color(0.52, 0.32, 0.46), "mid": Color(0.32, 0.2, 0.32), "near": Color(0.19, 0.12, 0.21),
		"haze": Color(0.96, 0.52, 0.4),
		"wire": Color(0.1, 0.07, 0.12), "lamps": 0.85, "windows": 0.3, "reflection": 0.55,
		"refl_tint": Color(0.5, 0.3, 0.42), "rim": true, "traffic": 1.0, "birds": 1.0,
		"city": 0.55, "crickets": 0.2, "chirps": 0.15,
		"green": Color(0.3, 0.2, 0.28),
	},
	{   # NIGHT — dark, sodium street lights, headlights glowing, strongest wet-road reflections
		"sky_top": Color(0.02, 0.03, 0.1), "sky_mid": Color(0.06, 0.08, 0.2), "sky_bottom": Color(0.16, 0.16, 0.32),
		"sun": Color(0.92, 0.94, 1.0), "sun_pos": Vector2(0.7, 0.16), "sun_r": 26.0, "moon": true, "stars": 1.0,
		"cloud": Color(0.3, 0.32, 0.5, 0.45),
		"tint": Color(0.42, 0.46, 0.7),
		"far": Color(0.13, 0.15, 0.28), "mid": Color(0.09, 0.1, 0.2), "near": Color(0.05, 0.05, 0.12),
		"haze": Color(0.2, 0.2, 0.38),
		"wire": Color(0.04, 0.04, 0.07), "lamps": 1.25, "windows": 0.4, "reflection": 0.78,
		"refl_tint": Color(0.12, 0.14, 0.3), "rim": true, "traffic": 0.7, "birds": 0.7,
		"city": 0.3, "crickets": 0.4, "chirps": 0.0,
		"green": Color(0.06, 0.09, 0.14),
	},
]


static func phase() -> int:
	_read_args()
	if force_phase >= 0:
		return force_phase % PRESETS.size()
	return floori(round_count / float(ROUNDS_PER_PHASE)) % PRESETS.size()


static func p() -> Dictionary:
	return PRESETS[phase()]


## World tint (the CanvasModulate colour) including the weather: rain greys and darkens it. Anything that
## undoes the world tint (popups, shout bubbles) or matches it (Cabin) uses this, not p().tint.
static func tint() -> Color:
	var t: Color = p().tint
	return t * Color.WHITE.lerp(Color(0.8, 0.82, 0.88), Weather.rain)


static func phase_name() -> String:
	return NAMES[phase()]


static func lights_on() -> bool:
	return p().lamps > 0.0


static func _read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			force_phase = int(a.trim_prefix("--phase="))
