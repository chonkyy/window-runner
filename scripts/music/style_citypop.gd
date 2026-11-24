class_name StyleCityPop
extends RefCounted
## CITY POP (FM 101.5): glossy 80s city pop / boogie-funk.
##   PAD   FM electric piano (body at ratio 1 + a bell "tine" at ratio 14) comping rootless 7th/9th voicings in a
##         syncopated pattern, short brass stabs at the ends of phrases
##   BASS  plucked finger/slap bass (Karplus-Strong + a sine sub), syncopated 16ths with octave pops
##   DRUMS tight kick, crisp snare + clap, closed/open hats (16ths with accents), shaker in the gaps
##   LEAD  "synth": two detuned pulses + saw, chorus-y; or "sax": a breathy saw through a formant, with growl
## Song keys: groove, lead ("synth"|"sax"), brass (bool).

const GROOVES := {
	# hat row: x = closed, o = open, . = none. comp: x = chord hit, - = hold, . = rest
	"boogie": {"kick": "x.....x...x.....", "snare": "....x.......x...", "hat": "x.x.x.xox.x.x.xo",
		"comp": "..x-..x-..x-.x--", "bass": [[0, 3, 0], [3, 1, 12], [6, 2, 0], [8, 2, 7], [10, 1, 12], [11, 1, 0],
			[14, 2, -1]]},
	"bright": {"kick": "x.......x.x.....", "snare": "....x.......x...", "hat": "xxxxxxxxxxxxxxxx",
		"comp": "x--.x-.x--.x.x--", "bass": [[0, 2, 0], [3, 1, 0], [4, 2, 12], [7, 1, 0], [8, 2, 0], [10, 2, 7],
			[12, 2, 12], [14, 2, 7]]},
	"disco": {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "x.o.x.o.x.o.x.o.",
		"comp": ".x.x.x.x.x.x.x.x", "bass": [[0, 1, 0], [2, 1, 12], [4, 1, 0], [6, 1, 12], [8, 1, 0], [10, 1, 12],
			[12, 1, 0], [14, 1, 12]]},
	"glide": {"kick": "x.........x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.xo",
		"comp": "x-----x-----x---", "bass": [[0, 4, 0], [6, 2, 0], [8, 4, 7], [13, 1, 12], [14, 2, -1]]},
	"latenight": {"kick": "x......x..x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
		"comp": "x---..x-----..x-", "bass": [[0, 5, 0], [7, 1, 0], [10, 4, 7], [14, 2, -1]]},
}
const RHYTHMS_SPARSE := ["x-----x---x-----", "x---x-----x-----", "..x---x-----x---", "x-------x-x-----",
	"...x--x---x-----"]
const RHYTHMS_BUSY := ["x-x-x-x---x-x---", "..x-x-x-x---x-x-", "x--x-x-x--x-----", "x-x--x-x-x--x---",
	".x-x-x---x-x-x--", "x-x-x---.x-x-x--"]
const GAINS := [0.55, 0.6, 0.6, 0.48]
const LEAD_LO := 66
const LEAD_HI := 86


static func render(stems: Array, song: Dictionary, step: int, rng: RandomNumberGenerator) -> Array:
	var tl := Music.timeline(song, Music.bars_of(song))
	_pad(stems[Music.PAD], song, tl, step, rng)
	if Music.abort:
		return GAINS
	_bass(stems[Music.BASS], song, tl, step, rng)
	_drums(stems[Music.DRUMS], song, tl.size(), step, rng)
	if Music.abort:
		return GAINS
	_lead(stems[Music.LEAD], song, tl, step, rng)
	return GAINS


## FM electric piano note: body + tine, natural decay, released at `held`.
static func epiano(f: float, held: float) -> PackedFloat32Array:
	var sec := held + 0.35
	var b := Synth.fm(f, sec, 1.0, 2.0, 0.25, 0.35)
	Synth.add(b, Synth.fm(f, sec, 14.0, 1.2, 0.0, 0.03), 0, 0.22 * clampf(440.0 / f, 0.4, 1.0))
	Synth.decay(b, 0.002, 1.4)
	return Synth.adsr(b, 0.001, 0.05, 0.9, held)


# --- PAD: e-piano comping + brass stabs ---

static func _pad(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var hits := Music.parse_rhythm(groove.comp)
	var cache := {}
	for bar in tl.size():
		for h in hits:
			var s: int = h[0]
			var seg := Music.chord_at(tl, bar, s)
			var v := Music.voicing(seg[2], 55, 74, true)
			var held := float(int(h[1]) * step) / Synth.RATE * 0.9
			var o := Music.at(bar, s, step, song)
			for i in v.size():
				var key := "%d:%d" % [v[i], h[1]]
				if not cache.has(key):
					cache[key] = epiano(Synth.midi_hz(v[i]), held)
					if Music.abort:
						return
				Synth.add(b, cache[key], o + i * 70, 0.55 * rng.randf_range(0.85, 1.0), true)   # a tiny roll
	if not song.get("brass", false):
		return
	var bcache := {}
	for bar in tl.size():
		if bar % 4 != 3:
			continue
		for s in [10, 14]:                         # "bap - baaap" into the next phrase
			var seg := Music.chord_at(tl, bar, s)
			var v := Music.voicing(seg[2], 62, 79, true)
			var held := float(step * (1 if s == 10 else 2)) / Synth.RATE
			for m in v:
				var key := "%d:%d" % [m, s]
				if not bcache.has(key):
					var t := Synth.tone(Synth.SAW, Synth.midi_hz(m), held + 0.12, -1.0, 0.5, 0.1, 6.0)
					Synth.add(t, Synth.tone(Synth.SAW, Synth.midi_hz(m) * 1.006, held + 0.12), 0, 0.7)
					Synth.lp(t, 900.0, 3200.0, 1.0)         # brass "blat": filter opens
					bcache[key] = Synth.adsr(t, 0.02, 0.06, 0.7, held)
				Synth.add(b, bcache[key], Music.at(bar, s, step, song), 0.35, true)


# --- BASS ---

static func _bass(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var cache := {}
	for bar in tl.size():
		for nt in groove.bass:
			var s: int = nt[0]
			var seg := Music.chord_at(tl, bar, s)
			var iv := Music.bass_iv(seg, int(nt[2]))
			var m: int = 31 + posmod(int(seg[1]) - 7, 12) + iv
			var held := float(int(nt[1]) * step) / Synth.RATE * 0.85
			var key := "%d:%d" % [m, int(nt[1])]
			if not cache.has(key):
				var f := Synth.midi_hz(m)
				var t := Synth.pluck(f, held + 0.06, rng, 0.993, 0.75 if iv >= 12 else 0.55)
				Synth.add(t, Synth.decay(Synth.tone(Synth.SINE, f, held + 0.06), 0.002, 0.5), 0, 0.7)
				Synth.lp(t, 2200.0 if iv >= 12 else 1300.0)
				cache[key] = Synth.adsr(t, 0.001, 0.05, 0.9, held)
			Synth.add(b, cache[key], Music.at(bar, s, step, song), 1.0, true)


# --- DRUMS ---

static func _drums(b: PackedFloat32Array, song: Dictionary, bars: int, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var kick := Synth.norm(Synth.perc(Synth.tone(Synth.SINE, 130.0, 0.24, 48.0), 0.001, 2.6))
	Synth.add(kick, Synth.norm(Synth.perc(Synth.lp(Synth.noise(0.008, rng), 3000.0), 0.0005, 2.0)), 0, 0.3)
	var snare := Synth.norm(Synth.perc(Synth.bp(Synth.noise(0.16, rng), 2600.0, -1.0, 0.6), 0.001, 2.4))
	Synth.add(snare, Synth.norm(Synth.perc(Synth.tone(Synth.TRI, 230.0, 0.07, 190.0), 0.001, 2.0)), 0, 0.5)
	var clap := Synth.empty(0.12)
	for k in 3:
		Synth.add_at(clap, Synth.perc(Synth.bp(Synth.noise(0.012 if k < 2 else 0.1, rng), 1250.0, -1.0, 1.3), 0.0005,
			2.5), k * 0.01)
	Synth.add(snare, Synth.norm(clap), 0, 0.55)
	Synth.norm(snare)
	var hat := Synth.norm(Synth.perc(Synth.hp(Synth.noise(0.03, rng), 8000.0), 0.0005, 3.0))
	var open := Synth.norm(Synth.perc(Synth.hp(Synth.noise(0.2, rng), 7000.0), 0.002, 1.8))
	var shaker := Synth.norm(Synth.swell(Synth.hp(Synth.noise(0.06, rng), 5000.0), 0.35, 1.5, 2.0))
	for bar in bars:
		for s in Music.STEPS:
			var o := Music.at(bar, s, step, song)
			if groove.kick[s] == "x":
				Synth.add(b, kick, o, 1.0, true)
			if groove.snare[s] == "x":
				Synth.add(b, snare, o, 0.75, true)
			var h: String = groove.hat[s]
			var acc := 1.0 if s % 4 == 0 else (0.8 if s % 2 == 0 else 0.6)
			if h == "x":
				Synth.add(b, hat, o, 0.24 * acc * rng.randf_range(0.85, 1.0), true)
			elif h == "o":
				Synth.add(b, open, o, 0.2, true)
			elif s % 2 == 1:
				Synth.add(b, shaker, o, 0.08, true)
		if bar % 8 == 7:                            # a little snare pickup into the top
			Synth.add(b, snare, Music.at(bar, 15, step, song), 0.4, true)


# --- LEAD ---

static func _lead(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var notes := Music.melody(song, tl, rng, [RHYTHMS_SPARSE, RHYTHMS_BUSY], LEAD_LO, LEAD_HI)
	var sax: bool = song.get("lead", "synth") == "sax"
	var cache := {}
	for nt in notes:
		var held := float(int(nt[2]) * step) / Synth.RATE * 0.9
		var key := "%d:%d" % [nt[3], nt[2]]
		if not cache.has(key):
			cache[key] = _sax(Synth.midi_hz(nt[3]) * 0.5, held, rng) if sax else _synth(Synth.midi_hz(nt[3]), held)
			if Music.abort:
				return
		Synth.add(b, cache[key], Music.at(nt[0], nt[1], step, song), 1.0, true)
	var d := 0.11                                # slapback room
	var n := b.size()
	Music.seamless(b, func(c: PackedFloat32Array) -> void:
		Synth.echo(c, d, 0.25, 0.25, 0.0)
		c.resize(n * 2))


static func _synth(f: float, held: float) -> PackedFloat32Array:
	var sec := held + 0.2
	var t := Synth.tone(Synth.SQUARE, f * 1.003, sec, -1.0, 0.25, 0.2, 5.8, null, 0.2)
	Synth.add(t, Synth.tone(Synth.SQUARE, f * 0.997, sec, -1.0, 0.25, 0.2, 5.4, null, 0.2), 0, 0.9)
	Synth.add(t, Synth.tone(Synth.SAW, f, sec, -1.0, 0.5, 0.2, 5.6, null, 0.2), 0, 0.5)
	Synth.lp(t, 3400.0, -1.0, 0.8)
	return Synth.adsr(t, 0.01, 0.15, 0.8, held)


## An octave-lower breathy "sax": saw through a nasal formant, a little growl and breath noise.
static func _sax(f: float, held: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := held + 0.15
	var t := Synth.tone(Synth.SAW, f, sec, -1.0, 0.5, 0.3, 5.0, null, 0.18)
	Synth.add(t, Synth.bp(Synth.tone(Synth.SAW, f, sec, -1.0, 0.5, 0.3, 5.0, null, 0.18), 1150.0, -1.0, 2.0), 0, 1.2)
	Synth.add(t, Synth.bp(Synth.noise(sec, rng), f * 4.0, -1.0, 2.0), 0, 0.08)
	Synth.drive(t, 1.8)
	Synth.lp(t, 2600.0)
	return Synth.adsr(t, 0.035, 0.12, 0.8, held)
