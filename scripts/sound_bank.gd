class_name SoundBank
extends RefCounted
## Every game sound as a Synth recipe: the audio "sprite sheet" (Phase 4). build(name) renders it once and caches
## the AudioStreamWAV (Mutex-guarded, so Sound can warm the bank on a worker thread). Each sound has its own
## seeded rng, so it is identical every launch. Names in LOOPS are seamless loops (value = cross-fade seconds).
## Pitched sounds (slice_hit, hop, bonus, fanfare, ui_*, ninja_pop, lamp_fixed ding, score_punch) are tuned to C,
## so Sound.note() can move them into the current song's key.

const NAMES := [
	# runner
	"jump", "double_jump", "drop", "wire_land", "land_street", "roof_land", "bounce", "slash", "slash_spin",
	"step_wire", "step_street", "step_roof",
	# deaths
	"crash", "horn", "thud", "oof", "bell", "moto_rev", "squawk", "zap", "body_thud",
	# scoring / feedback
	"slice_hit", "feathers", "hop", "bonus", "ninja_pop", "lamp_clang", "spark_crackle", "lamp_fixed",
	"trunk_pop", "clatter", "tick",
	# menus
	"ui_start", "confirm", "ui_tick", "ui_back", "splash_chime", "score_punch", "fanfare", "zoom_whoosh", "zoom_out", "push_whoosh",
	# car radio
	"radio_tune", "radio_static",
	# world
	"coo", "chirp", "chirp2",
	# loops
	"flutter", "transformer_hum", "lamp_buzz", "engine_car", "engine_big", "moto", "car_engine_ext", "car_drone",
	"amb_city", "amb_wind", "amb_crickets", "amb_rain_light", "amb_rain_heavy",
	# weather
	"thunder",
]

## Loop name -> cross-fade seconds (the buffer is rendered that much longer than the loop).
const LOOPS := {
	"flutter": 0.1, "transformer_hum": 0.2, "lamp_buzz": 0.1, "engine_car": 0.15, "engine_big": 0.15,
	"moto": 0.1, "car_engine_ext": 0.2, "car_drone": 0.4, "amb_city": 0.8, "amb_wind": 0.8, "amb_crickets": 0.4,
	"radio_static": 0.3, "amb_rain_light": 0.6, "amb_rain_heavy": 0.6,
}

## Peak level after normalisation (default 0.8); the mix is set per call / per bus on top of this.
const LEVEL := {
	"step_wire": 0.5, "step_street": 0.5, "step_roof": 0.5, "tick": 0.6, "ui_tick": 0.6, "coo": 0.6,
	"chirp": 0.5, "chirp2": 0.5, "crash": 0.95, "zap": 0.9, "amb_city": 0.7, "amb_wind": 0.7, "car_drone": 0.8,
	"amb_rain_light": 0.6, "amb_rain_heavy": 0.7, "thunder": 0.9,
}

const C5 := 523.25
const C6 := 1046.5

static var _cache := {}
static var _mutex := Mutex.new()


static func build(name: String) -> AudioStreamWAV:
	_mutex.lock()
	var s: AudioStreamWAV = _cache.get(name)
	_mutex.unlock()
	if s:
		return s
	var r := RandomNumberGenerator.new()
	r.seed = hash(name)
	var b := _render(name, r)
	if b.is_empty():
		push_warning("SoundBank: no recipe for '%s'" % name)
		b = Synth.empty(0.01)
	var xf: float = LOOPS.get(name, 0.0)
	s = Synth.to_wav(Synth.fades(b, 0.002, 0.004) if not LOOPS.has(name) else b, LEVEL.get(name, 0.8),
		LOOPS.has(name), xf)
	_mutex.lock()
	_cache[name] = s
	_mutex.unlock()
	return s


## Drop every built sound (Sound calls this at quit).
static func clear() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


## Already built (by the warm-up thread), else null. Never blocks on rendering.
static func cached(name: String) -> AudioStreamWAV:
	_mutex.lock()
	var s: AudioStreamWAV = _cache.get(name)
	_mutex.unlock()
	return s


# --- building blocks (each returns a normalised layer) ---

## Band-passed noise sweep with a percussive envelope.
static func _whoosh(r: RandomNumberGenerator, sec: float, f0: float, f1: float, q := 1.0, attack := 0.01,
		curve := 2.0) -> PackedFloat32Array:
	return Synth.norm(Synth.perc(Synth.bp(Synth.noise(sec, r), f0, f1, q), attack, curve))


static func _blip(wave: int, f0: float, f1: float, sec: float, duty := 0.5, curve := 2.5, attack := 0.002) -> PackedFloat32Array:
	return Synth.norm(Synth.perc(Synth.tone(wave, f0, sec, f1, duty), attack, curve))


## Sine pitch drop: kicks, thuds, impacts.
static func _thump(f0: float, f1: float, sec: float, curve := 3.0) -> PackedFloat32Array:
	return Synth.norm(Synth.perc(Synth.tone(Synth.SINE, f0, sec, f1), 0.002, curve))


## Low-passed noise burst (scuffs, puffs).
static func _puff(r: RandomNumberGenerator, sec: float, f0: float, f1 := -1.0, curve := 2.5) -> PackedFloat32Array:
	return Synth.norm(Synth.perc(Synth.lp(Synth.noise(sec, r), f0, f1), 0.002, curve))


static func _hiss(r: RandomNumberGenerator, sec: float, f: float, curve := 3.0) -> PackedFloat32Array:
	return Synth.norm(Synth.perc(Synth.hp(Synth.noise(sec, r), f), 0.001, curve))


## Scratchy footstep: a burst of tiny band-passed noise grains + grit clicks, sample-held and bit-crushed for
## that lo-fi Terraria crunch. `hold`/`bits` set how dirty it gets.
static func _scratch(r: RandomNumberGenerator, sec: float, lo: float, hi: float, grains: int, hold: int,
		bits: int) -> PackedFloat32Array:
	var b := Synth.empty(sec)
	for g in grains:
		var at := r.randf_range(0.0, sec * 0.55) if g > 0 else 0.0
		var gl := r.randf_range(0.008, 0.022)
		var grain := Synth.perc(Synth.bp(Synth.noise(gl, r), r.randf_range(lo, hi), -1.0, 1.4), 0.0005, 2.2)
		Synth.add_at(b, Synth.norm(grain), at, r.randf_range(0.45, 1.0) * (1.0 - 0.5 * at / sec))
	Synth.add(b, Synth.hp(Synth.clicks(sec, r, 700.0, 2.0), lo), 0, 0.5)
	return Synth.norm(Synth.perc(Synth.crush(Synth.norm(b), hold, bits), 0.0005, 1.6))


## Sum of exponentially decaying sine partials (bells, metal, glass).
static func _ring(f: float, ratios: Array, taus: Array, gains: Array, sec: float) -> PackedFloat32Array:
	var b := Synth.empty(sec)
	for k in ratios.size():
		var p := Synth.decay(Synth.tone(Synth.SINE, f * ratios[k], sec), 0.001, taus[k])
		Synth.add(b, p, 0, gains[k])
	return Synth.norm(b)


## Notes in sequence: [[freq, start sec, length sec], ...] on one waveform, each percussive.
static func _arp(wave: int, notes: Array, duty := 0.5, curve := 2.0) -> PackedFloat32Array:
	var b := Synth.empty(0.01)
	for nt in notes:
		Synth.add_at(b, Synth.perc(Synth.tone(wave, nt[0], nt[2], -1.0, duty, 0.15, 6.0), 0.003, curve), nt[1])
	return Synth.norm(b)


## Loop length helper: whole seconds plus the cross-fade overlap.
static func _ln(name: String, sec: float) -> float:
	return sec + LOOPS.get(name, 0.0)


static func _render(name: String, r: RandomNumberGenerator) -> PackedFloat32Array:
	match name:
		# --- runner ---
		"jump":
			var b := _whoosh(r, 0.16, 600.0, 1900.0, 1.2, 0.012, 2.0)
			return Synth.add(b, Synth.lp(_blip(Synth.SQUARE, 300.0, 540.0, 0.08, 0.25, 3.0), 3000.0), 0, 0.35)
		"double_jump":
			var b := _whoosh(r, 0.2, 900.0, 2800.0, 1.0, 0.01, 1.8)
			Synth.add(b, _blip(Synth.TRI, 520.0, 980.0, 0.1), 0, 0.3)
			return Synth.add_at(b, _whoosh(r, 0.09, 1500.0, 3800.0, 1.5, 0.005, 2.0), 0.07, 0.6)
		"drop":
			var b := _blip(Synth.TRI, 720.0, 240.0, 0.15, 0.5, 1.8)
			return Synth.add(b, _whoosh(r, 0.15, 1400.0, 450.0, 1.0), 0, 0.5)
		"wire_land":                                  # the wire twangs: Karplus string + a soft foot thud
			var b := Synth.pluck(98.0, 0.8, r, 0.995, 0.6)
			Synth.add(b, Synth.pluck(196.5, 0.4, r, 0.99, 0.4), 0, 0.35)
			Synth.add(b, _thump(95.0, 50.0, 0.09), 0, 0.5)
			return Synth.perc(Synth.lp(b, 2600.0), 0.001, 1.2)
		"land_street":
			var b := _thump(130.0, 45.0, 0.13)
			return Synth.add(b, _puff(r, 0.06, 900.0), 0, 0.4)
		"roof_land":                                  # metal roof thunk
			var b := _thump(170.0, 80.0, 0.14)
			Synth.add(b, _ring(330.0, [1.0, 2.71, 5.12, 8.3], [0.18, 0.12, 0.07, 0.05], [1.0, 0.6, 0.4, 0.25], 0.3), 0, 0.45)
			return Synth.add(b, _puff(r, 0.03, 2500.0), 0, 0.3)
		"bounce":                                     # spring boing
			var b := Synth.norm(Synth.perc(Synth.tone(Synth.TRI, 200.0, 0.22, 560.0, 0.5, 2.0, 22.0), 0.003, 1.4))
			return Synth.add(b, _thump(120.0, 60.0, 0.06), 0, 0.25)
		"slash":
			var b := _whoosh(r, 0.13, 3600.0, 1100.0, 2.2, 0.008, 1.6)
			return Synth.add(b, _hiss(r, 0.05, 4500.0), 0, 0.35)
		"slash_spin":
			var b := _whoosh(r, 0.12, 2400.0, 1200.0, 2.0, 0.01, 1.6)
			return Synth.add_at(b, _whoosh(r, 0.14, 3800.0, 1000.0, 2.2, 0.008, 1.6), 0.1, 0.9)
		"step_wire":                                  # thin scratch on the cable + a tiny twang
			var b := _scratch(r, 0.05, 2600.0, 4800.0, 4, 2, 7)
			return Synth.add(b, Synth.pluck(196.0, 0.1, r, 0.98, 0.5), 0, 0.3)
		"step_street":                                # gritty gravel crunch (Terraria dig-style)
			var b := _scratch(r, 0.075, 1200.0, 3200.0, 6, 3, 6)
			return Synth.add(b, _puff(r, 0.03, 600.0, -1.0, 3.0), 0, 0.35)
		"step_roof":                                  # scrape on sheet metal
			var b := _scratch(r, 0.06, 1800.0, 4200.0, 5, 2, 6)
			return Synth.add(b, _ring(620.0, [1.0, 2.3], [0.03, 0.02], [1.0, 0.5], 0.06), 0, 0.3)

		# --- deaths ---
		"crash":
			var b := Synth.norm(Synth.perc(Synth.lp(Synth.noise(0.7, r), 5000.0, 500.0), 0.002, 2.2))
			Synth.add(b, _thump(95.0, 32.0, 0.35, 2.0), 0, 0.8)
			var ratios := []
			var taus := []
			var gains := []
			for k in 6:
				ratios.append(r.randf_range(1.0, 9.0))
				taus.append(r.randf_range(0.1, 0.35))
				gains.append(r.randf_range(0.4, 1.0))
			Synth.add(b, _ring(250.0, ratios, taus, gains, 0.6), 0, 0.35)
			for k in 6:                               # glass tinkle
				Synth.add_at(b, _hiss(r, 0.02, 5000.0, 2.0), r.randf_range(0.05, 0.4), 0.25)
			return Synth.drive(b, 1.8)
		"horn":                                       # BEEP BEEP: two honks of a two-tone horn
			var b := Synth.empty(0.01)
			for h in [[0.0, 0.15], [0.22, 0.24]]:
				var honk := Synth.tone(Synth.SQUARE, 415.0, h[1])
				Synth.add(honk, Synth.tone(Synth.SQUARE, 523.0, h[1]), 0, 0.8)
				Synth.fades(Synth.lp(honk, 1800.0, -1.0, 1.0), 0.008, 0.02)
				Synth.add_at(b, honk, h[0])
			return Synth.drive(Synth.norm(b), 1.5)
		"thud":
			var b := _thump(115.0, 48.0, 0.2)
			return Synth.add(b, _puff(r, 0.1, 600.0), 0, 0.5)
		"oof":                                        # voice-ish grunt: falling saw through two formants
			var src := Synth.tone(Synth.SAW, 270.0, 0.2, 150.0)
			var b := Synth.bp(src.duplicate(), 750.0, -1.0, 2.5)
			Synth.add(b, Synth.bp(src, 1300.0, -1.0, 3.0), 0, 0.6)
			return Synth.norm(Synth.perc(b, 0.015, 1.3))
		"bell":                                       # bicycle bell, ring-ring
			var b := Synth.empty(0.01)
			for t in [0.0, 0.13]:
				var ding := _ring(2350.0, [1.0, 1.47, 2.09, 2.56], [0.35, 0.25, 0.15, 0.1], [1.0, 0.6, 0.35, 0.2], 0.6)
				Synth.add_at(b, Synth.am(ding, 14.0, 0.3), t)
			return Synth.norm(b)
		"moto_rev":
			var b := Synth.norm(Synth.perc(Synth.drive(Synth.lp(Synth.am(Synth.tone(Synth.SAW, 70.0, 0.55, 190.0), 32.0, 0.6), 1600.0), 2.0), 0.02, 1.2))
			return Synth.add(b, _puff(r, 0.5, 800.0, -1.0, 1.5), 0, 0.3)
		"squawk":
			var b := Synth.tone(Synth.SQUARE, 950.0, 0.1, 1450.0, 0.35, 3.0, 28.0)
			Synth.add_at(b, Synth.tone(Synth.SQUARE, 1300.0, 0.14, 700.0, 0.35, 3.0, 28.0), 0.08)
			b = Synth.norm(Synth.perc(Synth.bp(b, 1600.0, -1.0, 1.5), 0.004, 1.5))
			return Synth.add(b, _puff(r, 0.2, 1500.0, 400.0), 0, 0.4)
		"zap":                                        # 0.6 s buzz + crackle + whine, chopped like the flicker
			var b := Synth.norm(Synth.tone(Synth.SAW, 120.0, 0.62))
			Synth.add(b, Synth.tone(Synth.SQUARE, 180.0, 0.62, -1.0, 0.3), 0, 0.6)
			Synth.add(b, Synth.norm(Synth.hp(Synth.clicks(0.62, r, 90.0), 1500.0)), 0, 0.8)
			Synth.add(b, Synth.tone(Synth.SINE, 1800.0, 0.62, 3600.0), 0, 0.2)
			Synth.am(b, 24.0, 0.5, 0.5)
			return Synth.lp(Synth.drive(Synth.perc(b, 0.002, 0.6), 2.5), 6000.0)
		"body_thud":
			var b := _thump(90.0, 40.0, 0.16)
			return Synth.add(b, _puff(r, 0.08, 500.0), 0, 0.4)

		# --- scoring / feedback ---
		"slice_hit":                                  # "shing" ringing at C6
			var b := _ring(C6, [1.0, 2.0, 3.01, 4.2], [0.25, 0.15, 0.08, 0.05], [1.0, 0.5, 0.3, 0.2], 0.4)
			Synth.add(b, _hiss(r, 0.05, 3500.0), 0, 0.5)
			return Synth.add(b, _thump(320.0, 110.0, 0.07), 0, 0.4)
		"feathers":
			return Synth.am(_puff(r, 0.28, 1400.0, 350.0, 2.5), 28.0, 0.5)
		"hop":                                        # coin-ish pling: C5 then G5
			var b := _arp(Synth.SQUARE, [[C5, 0.0, 0.07], [C5 * 1.4983, 0.045, 0.14]], 0.25, 2.2)
			Synth.lp(b, 3500.0)
			return Synth.add(b, _blip(Synth.SINE, C6, C6, 0.12), 0, 0.3)
		"bonus":                                      # mode-neutral arpeggio C5 G5 C6 G6 with echo
			var b := _arp(Synth.SQUARE, [[C5, 0.0, 0.12], [C5 * 1.4983, 0.055, 0.12], [C6, 0.11, 0.12],
				[C6 * 1.4983, 0.165, 0.18]], 0.25, 1.8)
			return Synth.echo(Synth.lp(b, 4000.0), 0.09, 0.3, 0.4, 0.3)
		"ninja_pop":                                  # poof + sparkle (the kid imagines the ninja into being)
			var b := Synth.scale(_puff(r, 0.3, 2000.0, 400.0), 0.5)
			var sp := _arp(Synth.SINE, [[C6, 0.02, 0.18], [C6 * 1.4983, 0.055, 0.18], [C6 * 2.0, 0.09, 0.22]], 0.5, 1.6)
			Synth.add(b, Synth.am(sp, 30.0, 0.4), 0, 0.8)
			return Synth.echo(b, 0.07, 0.3, 0.35, 0.25)
		"lamp_clang":
			var b := _ring(410.0, [1.0, 2.76, 5.4, 8.93], [0.5, 0.3, 0.15, 0.08], [1.0, 0.6, 0.4, 0.2], 0.9)
			return Synth.add(b, _puff(r, 0.03, 3000.0), 0, 0.4)
		"spark_crackle":
			return Synth.norm(Synth.hp(Synth.clicks(0.45, r, 140.0, 1.5), 2000.0))
		"lamp_fixed":                                 # hum stutters up, then a ding at C6
			var hum := Synth.lp(Synth.tone(Synth.SAW, 60.0, 0.45, 120.0), 900.0)
			Synth.am(hum, 26.0, 0.8, 0.5)
			var b := Synth.norm(Synth.swell(hum, 0.8, 1.5, 1.0))
			return Synth.add_at(Synth.scale(b, 0.5), _ring(C6, [1.0, 2.0, 3.0], [0.4, 0.25, 0.12], [1.0, 0.4, 0.2], 0.7), 0.32, 0.8)
		"trunk_pop":
			var b := _thump(210.0, 95.0, 0.09)
			Synth.add(b, _hiss(r, 0.02, 2500.0), 0, 0.5)
			return Synth.add(b, _blip(Synth.TRI, 320.0, 210.0, 0.18, 0.5, 1.5), 0, 0.3)
		"clatter":
			var b := Synth.empty(0.35)
			for k in 5:
				var knock := _ring(r.randf_range(450.0, 1300.0), [1.0, 2.6], [0.03, 0.02], [1.0, 0.5], 0.06)
				Synth.add_at(b, knock, r.randf_range(0.0, 0.28), 1.0 - k * 0.15)
			return b
		"tick":                                       # hazard relay click
			var b := _blip(Synth.SQUARE, 1900.0, 1900.0, 0.012, 0.5, 3.0)
			return Synth.add(b, _hiss(r, 0.008, 3000.0), 0, 0.5)

		# --- menus ---
		"ui_start":
			var b := _arp(Synth.TRI, [[C5, 0.0, 0.14], [C5 * 1.4983, 0.07, 0.14], [C6, 0.14, 0.3]], 0.5, 1.6)
			Synth.add(b, Synth.lp(_arp(Synth.SQUARE, [[C5, 0.0, 0.14], [C5 * 1.4983, 0.07, 0.14], [C6, 0.14, 0.3]], 0.5, 1.6), 2500.0), 0, 0.3)
			return Synth.echo(b, 0.11, 0.3, 0.35, 0.3)
		"confirm":
			return Synth.lp(_arp(Synth.SQUARE, [[C5 * 1.4983, 0.0, 0.07], [C6, 0.05, 0.14]], 0.25, 2.0), 3500.0)
		"ui_back":                                    # menu back / cancel: a falling blip pair
			return Synth.lp(_arp(Synth.SQUARE, [[C6, 0.0, 0.06], [C5 * 1.4983, 0.05, 0.1]], 0.25, 2.0), 3000.0)
		"splash_chime":                               # studio card: plump FM e-piano C4 G4 C5, bell on top
			var b := Synth.empty(1.6)
			for k in 3:
				var f: float = [C5 / 2.0, C5 * 1.4983 / 2.0, C5][k]
				Synth.add_at(b, Synth.perc(Synth.fm(f, 1.1, 1.0, 2.2, 0.4, 0.3), 0.004, 1.6), 0.13 * k, 0.8)
			Synth.add_at(b, Synth.perc(Synth.fm(C6, 1.2, 3.5, 1.5, 0.0, 0.25), 0.002, 2.2), 0.26, 0.25)
			return Synth.norm(Synth.echo(Synth.lp(b, 3800.0), 0.16, 0.3, 0.3, 0.5), 0.8)
		"ui_tick":
			return Synth.lp(_blip(Synth.SQUARE, C6, C6, 0.03, 0.5, 3.0), 4000.0)
		"score_punch":
			var b := _thump(110.0, 45.0, 0.25)
			var chord := Synth.tone(Synth.SQUARE, C5, 0.3)
			Synth.add(chord, Synth.tone(Synth.SQUARE, C5 * 1.4983, 0.3), 0, 0.8)
			Synth.add(chord, Synth.tone(Synth.SQUARE, C6, 0.3), 0, 0.6)
			return Synth.add(b, Synth.norm(Synth.perc(Synth.lp(chord, 2500.0), 0.003, 1.6)), 0, 0.5)
		"fanfare":                                    # NEW BEST: C5 G5 C6, then a held C6 + G6
			var b := _arp(Synth.SQUARE, [[C5, 0.0, 0.12], [C5 * 1.4983, 0.1, 0.12], [C6, 0.2, 0.12]], 0.25, 1.5)
			var hold := Synth.tone(Synth.SQUARE, C6, 0.6, -1.0, 0.5, 0.25, 5.5)
			Synth.add(hold, Synth.tone(Synth.TRI, C6 * 1.4983, 0.6, -1.0, 0.5, 0.25, 5.5), 0, 0.8)
			Synth.add_at(b, Synth.norm(Synth.adsr(hold, 0.01, 0.1, 0.7, 0.45)), 0.3, 0.8)
			return Synth.echo(Synth.lp(b, 3800.0), 0.12, 0.3, 0.35, 0.4)
		"zoom_whoosh":                                # into the window: rising swell
			var b := Synth.norm(Synth.swell(Synth.bp(Synth.noise(1.4, r), 250.0, 3200.0, 0.9), 0.82, 2.0, 2.0))
			return Synth.add(b, Synth.norm(Synth.swell(Synth.tone(Synth.SINE, 180.0, 1.4, 900.0), 0.82, 2.0, 2.0)), 0, 0.25)
		"zoom_out":
			return Synth.norm(Synth.swell(Synth.bp(Synth.noise(1.1, r), 3000.0, 250.0, 0.9), 0.15, 1.5, 2.0))
		"push_whoosh":
			return Synth.norm(Synth.swell(Synth.bp(Synth.noise(0.6, r), 300.0, 1500.0, 0.8), 0.7, 2.0, 2.0))

		# --- car radio ---
		"radio_tune":                                 # dial turned: click, static sweep, a heterodyne whistle
			var sec := 0.42
			var b := Synth.bp(Synth.noise(sec, r), 700.0, 3800.0, 0.9)
			Synth.am(Synth.swell(Synth.norm(b), 0.35, 1.2, 1.6), 23.0, 0.45)
			var whistle := Synth.tone(Synth.SINE, 2600.0, sec, 700.0, 0.5, 0.6, 9.0)
			Synth.add(b, Synth.swell(whistle, 0.5, 1.5, 2.0), 0, 0.22)
			Synth.add(b, _blip(Synth.SQUARE, 1800.0, 1700.0, 0.012, 0.5, 2.0), 0, 0.6)   # the knob's click
			return Synth.crush(Synth.norm(b), 2, 7)
		"radio_static":                               # between stations: band-limited hiss + crackle, AM wobble
			var sec := _ln(name, 2.0)
			var b := Synth.norm(Synth.bp(Synth.noise(sec, r), 1500.0, -1.0, 0.5))
			Synth.add(b, Synth.norm(Synth.hp(Synth.clicks(sec, r, 40.0), 1200.0)), 0, 0.5)
			Synth.am(b, 3.0, 0.25)
			return Synth.crush(Synth.norm(b), 2, 7)
		# --- world one-shots ---
		"coo":                                        # pigeon: "croo-OO", throaty
			var b := Synth.tone(Synth.SINE, 310.0, 0.18, 360.0)
			Synth.add_at(b, Synth.tone(Synth.SINE, 360.0, 0.3, 290.0), 0.2)
			Synth.add(b, Synth.scale(Synth.lp(Synth.tone(Synth.TRI, 310.0, 0.5, 300.0), 900.0), 0.3))
			Synth.am(b, 16.0, 0.6)
			return Synth.norm(Synth.perc(Synth.lp(b, 900.0), 0.04, 1.2))
		"chirp":
			var b := Synth.empty(0.25)
			for k in 3:
				var f := r.randf_range(2700.0, 3300.0)
				Synth.add_at(b, Synth.perc(Synth.tone(Synth.SINE, f, 0.045, f * 1.45), 0.003, 1.5), k * 0.07)
			return Synth.norm(b)
		"chirp2":                                     # trill
			var b := Synth.empty(0.32)
			for k in 8:
				Synth.add_at(b, Synth.perc(Synth.tone(Synth.SINE, 3600.0, 0.025, 4100.0), 0.002, 1.5), k * 0.035, 1.0 - k * 0.06)
			return Synth.norm(b)

		# --- loops (rendered as whole cycles of the loop length + cross-fade) ---
		"flutter":                                    # wing flaps, 9 per second
			var b := Synth.bp(Synth.noise(_ln(name, 1.0), r), 900.0, -1.0, 0.9)
			return Synth.norm(Synth.am(b, 9.0, 0.85, 0.35))
		"transformer_hum":                            # mains hum + buzz + the odd crackle: audible hazard
			var sec := _ln(name, 2.0)
			var b := Synth.empty(sec)
			for h in [[60.0, 0.3], [120.0, 1.0], [180.0, 0.4], [240.0, 0.5], [360.0, 0.2]]:
				Synth.add(b, Synth.tone(Synth.SINE, h[0], sec), 0, h[1])
			Synth.add(b, Synth.norm(Synth.lp(Synth.tone(Synth.SQUARE, 120.0, sec, -1.0, 0.1), 700.0)), 0, 0.4)
			return Synth.add(b, Synth.norm(Synth.hp(Synth.clicks(sec, r, 6.0), 2500.0)), 0, 0.5)
		"lamp_buzz":
			var sec := _ln(name, 1.0)
			var b := Synth.norm(Synth.lp(Synth.tone(Synth.SAW, 120.0, sec), 1500.0))
			Synth.add(b, Synth.norm(Synth.lp(Synth.tone(Synth.SQUARE, 240.0, sec, -1.0, 0.2), 2000.0)), 0, 0.3)
			return Synth.am(b, 10.0, 0.2)
		"engine_car":
			var sec := _ln(name, 1.0)
			var b := Synth.norm(Synth.lp(Synth.tone(Synth.SAW, 50.0, sec), 320.0))
			Synth.add(b, Synth.norm(Synth.lp(Synth.tone(Synth.SQUARE, 25.0, sec, -1.0, 0.3), 220.0)), 0, 0.5)
			Synth.am(b, 25.0, 0.3)
			return Synth.add(b, Synth.lp(Synth.brown(sec, r), 500.0), 0, 0.5)
		"engine_big":                                 # diesel: deeper, clattery
			var sec := _ln(name, 1.0)
			var b := Synth.norm(Synth.lp(Synth.tone(Synth.SAW, 34.0, sec), 350.0))
			Synth.add(b, Synth.norm(Synth.lp(Synth.tone(Synth.SQUARE, 17.0, sec, -1.0, 0.2), 250.0)), 0, 0.6)
			Synth.add(b, Synth.norm(Synth.am(Synth.bp(Synth.noise(sec, r), 1200.0, -1.0, 1.2), 34.0, 0.9, 0.2)), 0, 0.25)
			return Synth.add(b, Synth.lp(Synth.brown(sec, r), 400.0), 0, 0.5)
		"moto":
			var sec := _ln(name, 1.0)
			var b := Synth.tone(Synth.SAW, 96.0, sec)
			Synth.add(b, Synth.tone(Synth.SQUARE, 192.0, sec, -1.0, 0.3), 0, 0.5)
			return Synth.drive(Synth.norm(Synth.lp(Synth.am(b, 48.0, 0.4), 2200.0)), 2.0)
		"car_engine_ext":                             # the family car from outside: engine + tyres on the road
			var sec := _ln(name, 2.0)
			var b := Synth.norm(Synth.lp(Synth.tone(Synth.SAW, 44.0, sec), 300.0))
			Synth.add(b, Synth.norm(Synth.lp(Synth.tone(Synth.SQUARE, 22.0, sec, -1.0, 0.3), 200.0)), 0, 0.5)
			Synth.am(b, 22.0, 0.25)
			return Synth.add(b, Synth.norm(Synth.lp(Synth.noise(sec, r), 700.0)), 0, 0.45)
		"car_drone":                                  # inside the car: low rumble, road texture
			var sec := _ln(name, 4.0)
			var b := Synth.lp(Synth.brown(sec, r), 160.0)
			Synth.norm(b)
			Synth.add(b, Synth.tone(Synth.SINE, 48.0, sec), 0, 0.3)
			Synth.add(b, Synth.tone(Synth.SINE, 96.0, sec), 0, 0.15)
			Synth.add(b, Synth.norm(Synth.bp(Synth.noise(sec, r), 300.0, -1.0, 0.7)), 0, 0.2)
			return Synth.am(b, 0.5, 0.15)
		"amb_city":                                   # distant traffic: brown rumble with slow swells
			var sec := _ln(name, 8.0)
			var b := Synth.lp(Synth.brown(sec, r), 300.0)
			Synth.norm(b)
			Synth.add(b, Synth.norm(Synth.bp(Synth.noise(sec, r), 900.0, -1.0, 0.5)), 0, 0.2)
			for hz in [0.25, 0.375, 0.625]:
				Synth.am(b, hz, 0.35)
			return b
		"amb_wind":
			var sec := _ln(name, 6.0)
			var b := Synth.bp_lfo(Synth.noise(sec, r), 350.0, 1000.0, 1.0 / 6.0, 0.7)
			Synth.am(b, 1.0 / 3.0, 0.4)
			return Synth.am(b, 0.5, 0.25)
		"amb_rain_light":                             # soft hiss + sparse patter of drops on the road and the car
			var sec := _ln(name, 6.0)
			var b := Synth.lp(Synth.hp(Synth.noise(sec, r), 1800.0), 7000.0)
			Synth.norm(b)
			Synth.scale(b, 0.35)
			var drops := Synth.bp(Synth.clicks(sec, r, 55.0), 2600.0, -1.0, 1.4)
			Synth.add(b, Synth.norm(drops), 0, 0.8)
			var tick := Synth.hp(Synth.clicks(sec, r, 18.0), 4000.0)    # nearer drops: brighter ticks
			Synth.add(b, Synth.norm(tick), 0, 0.45)
			return Synth.am(b, 1.0 / 3.0, 0.15)
		"amb_rain_heavy":                             # dense wash of rain, low roar underneath, thick patter
			var sec := _ln(name, 6.0)
			var b := Synth.bp(Synth.noise(sec, r), 1400.0, -1.0, 0.45)
			Synth.norm(b)
			Synth.add(b, Synth.norm(Synth.lp(Synth.brown(sec, r), 220.0)), 0, 0.45)
			Synth.add(b, Synth.norm(Synth.bp(Synth.clicks(sec, r, 320.0), 2200.0, -1.0, 1.0)), 0, 0.5)
			Synth.add(b, Synth.norm(Synth.hp(Synth.noise(sec, r), 5000.0)), 0, 0.12)
			Synth.am(b, 0.5, 0.12)
			return Synth.am(b, 1.0 / 6.0, 0.18)
		"thunder":                                    # crack, then a long rolling rumble
			var b := Synth.lp(Synth.brown(4.5, r), 160.0)
			Synth.norm(b)
			Synth.add(b, Synth.norm(Synth.lp(Synth.brown(4.5, r), 70.0)), 0, 0.8)
			for k in 4:                                # the roll: a few swells on the way out
				Synth.am(b, r.randf_range(0.6, 1.6), 0.35)
			Synth.decay(b, 0.08, 1.6)
			var crack := Synth.decay(Synth.lp(Synth.noise(0.7, r), 1600.0), 0.004, 0.12)
			Synth.add(b, Synth.norm(crack), 0, 0.55)
			return b
		"amb_crickets":                               # three crickets at their own rates (periods divide 4 s)
			var b := Synth.empty(4.0)
			for c in [[4300.0, 0.5, 1.0], [4550.0, 0.8, 0.6], [4100.0, 1.0, 0.45]]:
				var t := r.randf_range(0.0, 0.3)
				while t < 4.0:
					var chirp := Synth.am(Synth.tone(Synth.SINE, c[0], 0.09), 32.0, 1.0, 0.5)
					Synth.add(b, Synth.fades(chirp, 0.005, 0.01), Synth.frames(t), c[2], true)
					t += c[1]
			return _periodic(Synth.norm(b), LOOPS[name])
	return PackedFloat32Array()


## A buffer that already loops (wrap-mixed) plus a copy of its first xf seconds, so to_wav's cross-fade blends
## identical material.
static func _periodic(b: PackedFloat32Array, xf: float) -> PackedFloat32Array:
	var n := b.size()
	var x := Synth.frames(xf)
	b.resize(n + x)
	for i in x:
		b[n + i] = b[i]
	return b
