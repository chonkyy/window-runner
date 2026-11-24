class_name StyleRpg
extends RefCounted
## POCKET QUEST (FM 92.7): a late-80s handheld-console sound chip. Four channels, as on the hardware:
##   LEAD  pulse 1: the tune (12.5 / 25 / 50 % duty), vibrato that creeps in on held notes, no reverb
##   PAD   pulse 2: broken chords (alberti 8ths, 16th arps or offbeat pulses), the other duty
##   BASS  the 4-bit wavetable channel (32 steps x 16 levels: the gritty "wave" bass), octave bounces
##   DRUMS 15-bit LFSR noise (long mode = snare/kick hiss, short "metallic" mode = hats) + a pulse-sweep kick
## Volume envelopes are stepped to 16 levels like the chip's, so notes have that crisp, slightly stair-cased
## decay. Melodies use the full major/minor scale with the shared form generator (Music.melody).

const GROOVES := {
	# kick/snare/hat: x = hit, o = soft (o on the hat row = longer, open). bass = [[step, length, interval]]
	"town": {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "..x...x...x...x.",
		"bass": [[0, 3, 0], [4, 3, 7], [8, 3, 12], [12, 3, 7]]},
	"march": {"kick": "x...x...x...x...", "snare": "....x..o....x.oo", "hat": "x.x.x.x.x.x.x.x.",
		"bass": [[0, 2, 0], [4, 2, 7], [8, 2, 0], [12, 2, 7]]},
	"gallop": {"kick": "x...x...x...x...", "snare": "....x.......x..o", "hat": "x.xxx.xxx.xxx.xx",
		"bass": [[0, 2, 0], [2, 2, 12], [4, 2, 0], [6, 2, 12], [8, 2, 0], [10, 2, 12], [12, 2, 7], [14, 2, 12]]},
	"lull": {"kick": "x...............", "snare": "................", "hat": "....o.......o...",
		"bass": [[0, 7, 0], [8, 7, 7]]},
	"cave": {"kick": "x.........x.....", "snare": "........x.......", "hat": "x...x...x...x..x",
		"bass": [[0, 3, 0], [3, 3, 0], [6, 2, 7], [8, 3, 0], [11, 3, 0], [14, 2, -1]]},
}
## Pad figures: each step lists which voicing note (0 = lowest) plays on that 16th, "." = nothing.
const FIGURES := {
	"alberti": "0.2.1.2.0.2.1.2.",
	"arp16": "0123210101232101",
	"pulse8": "..1...2...1...2.",
	"roll": "0.1.2.3.2.1.0...",
}
const RHYTHMS_SPARSE := ["x-----x-x-------", "x---x---x-------", "x-----x-----x---", "x-------x---x-x-",
	"x---x-x-x-------", "x-x-x-------x---"]
const RHYTHMS_BUSY := ["x-x-x-x-x---x---", "x-xxx-x-x---x-x-", "x--x--x-x---x---", "x-x-x---x-x-x---",
	"x---x-x-x-x-x-x-", "x--xx--xx-x-x---", "x-x-x-xxx-------", "xxx-x-x-x---x-x-"]
## The wave channel's sample: 32 steps, 4-bit. A soft square with rounded edges (round, woody bass).
const WAVE := [8, 11, 13, 14, 15, 15, 15, 15, 15, 15, 15, 15, 14, 13, 11, 8,
	7, 4, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 7]
const GAINS := [0.42, 0.5, 0.5, 0.6]
const LEAD_LO := 69
const LEAD_HI := 88


static func render(stems: Array, song: Dictionary, step: int, rng: RandomNumberGenerator) -> Array:
	var tl := Music.timeline(song, Music.bars_of(song))
	_pad(stems[Music.PAD], song, tl, step)
	if Music.abort:
		return GAINS
	_bass(stems[Music.BASS], song, tl, step)
	_drums(stems[Music.DRUMS], song, tl.size(), step)
	if Music.abort:
		return GAINS
	_lead(stems[Music.LEAD], song, tl, step, rng)
	for b in stems:                               # the little speaker's top end (and tames the aliasing)
		Music.seamless(b, func(c: PackedFloat32Array) -> void: Synth.lp(c, 9000.0))
	return GAINS


## Stepped chip envelope: start at vol, fall `fall` per second while held (to `floor`), then a quick release;
## the level is quantised to the hardware's 16 steps.
static func env(b: PackedFloat32Array, vol: float, fall: float, held: float, floor_v := 0.0, rel := 0.03) -> PackedFloat32Array:
	var nh := mini(Synth.frames(held), b.size())
	var nr := maxi(Synth.frames(rel), 1)
	var v := vol
	for i in b.size():
		if i < nh:
			v = maxf(vol - fall * float(i) / Synth.RATE, floor_v)
		var lvl := v if i < nh else v * maxf(1.0 - float(i - nh) / nr, 0.0)
		b[i] *= floorf(lvl * 15.0 + 0.5) / 15.0
	return b


static func pulse(f: float, sec: float, duty: float, vib := 0.0, vib_in := 0.2) -> PackedFloat32Array:
	return Synth.tone(Synth.SQUARE, f, sec, -1.0, duty, vib, 5.6, null, vib_in)


# --- PAD: pulse 2, broken chords ---

static func _pad(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int) -> void:
	var fig: String = FIGURES[song.get("pad", "alberti")]
	var duty: float = song.get("pad_duty", 0.25)
	var vol: float = song.get("pad_vol", 0.6)
	var cache := {}
	for bar in tl.size():
		for s in Music.STEPS:
			var ch := fig[s]
			if ch == ".":
				continue
			var seg := Music.chord_at(tl, bar, s)
			var v := Music.voicing(seg[2], 57, 69)
			var m: int = v[int(ch) % v.size()] + (12 if int(ch) >= v.size() else 0)
			var len_s := 1
			while s + len_s < Music.STEPS and fig[s + len_s] == "." and len_s < 2:
				len_s += 1
			var held := float(len_s * step) / Synth.RATE
			var key := "%d:%d" % [m, len_s]
			if not cache.has(key):
				cache[key] = env(pulse(Synth.midi_hz(m), held + 0.04, duty), vol, 2.2, held, 0.15)
			Synth.add(b, cache[key], Music.at(bar, s, step, song), 1.0, true)


# --- BASS: wave channel ---

static func wave(f: float, sec: float) -> PackedFloat32Array:
	var n := Synth.frames(sec)
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	var dt := f / Synth.RATE
	for i in n:
		b[i] = float(WAVE[int(ph * 32.0) & 31]) / 7.5 - 1.0
		ph = fmod(ph + dt, 1.0)
	return b


static func _bass(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var cache := {}
	for bar in tl.size():
		for nt in groove.bass:
			var s: int = nt[0]
			var seg := Music.chord_at(tl, bar, s)
			var m: int = 36 + int(seg[1]) + Music.bass_iv(seg, int(nt[2]))
			if m < 36 + 4:                          # keep the low notes out of the mud
				m += 12
			var held := float(int(nt[1]) * step) / Synth.RATE * 0.92
			var key := "%d:%d" % [m, int(nt[1])]
			if not cache.has(key):
				var w := wave(Synth.midi_hz(m), held + 0.02)
				cache[key] = Synth.fades(w, 0.002, 0.012)
			Synth.add(b, cache[key], Music.at(bar, s, step, song), 1.0, true)


# --- DRUMS: noise channel ---

## The chip's noise: a 15-bit LFSR clocked at `clock` Hz. short = 7-bit mode, a buzzy metallic tone.
static func lfsr(sec: float, clock: float, short: bool) -> PackedFloat32Array:
	var n := Synth.frames(sec)
	var b := PackedFloat32Array()
	b.resize(n)
	var r := 0x7fff
	var acc := 0.0
	var v := 1.0
	var inc := clock / Synth.RATE
	for i in n:
		acc += inc
		while acc >= 1.0:
			acc -= 1.0
			var bit := (r ^ (r >> 1)) & 1
			r = (r >> 1) | (bit << 14)
			if short:
				r = (r & ~0x40) | (bit << 6)
			v = 1.0 if (r & 1) == 0 else -1.0
		b[i] = v
	return b


static func _drums(b: PackedFloat32Array, song: Dictionary, bars: int, step: int) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var kick := env(lfsr(0.09, 9000.0, false), 0.6, 9.0, 0.07)
	Synth.add(kick, env(pulse(160.0, 0.09, 0.5), 1.0, 12.0, 0.08), 0, 0.9)
	var kick_sw := Synth.tone(Synth.SQUARE, 170.0, 0.09, 48.0, 0.5)
	Synth.add(kick, env(kick_sw, 1.0, 11.0, 0.08), 0, 0.8)
	var snare := env(lfsr(0.16, 26000.0, false), 1.0, 6.5, 0.15)
	var ghost := env(lfsr(0.07, 26000.0, false), 0.45, 6.0, 0.06)
	var hat := env(lfsr(0.035, 70000.0, true), 0.5, 14.0, 0.03)
	var open := env(lfsr(0.16, 70000.0, true), 0.4, 2.4, 0.15)
	for bar in bars:
		var fill := bar % 8 == 7                   # end of every 8 bars: a snare roll into the top
		for s in Music.STEPS:
			var o := Music.at(bar, s, step, song)
			var k: String = groove.kick[s]
			var sn: String = groove.snare[s]
			var h: String = groove.hat[s]
			if fill and s >= 12:
				sn = "x" if s % 2 == 0 else "o"
			if k != ".":
				Synth.add(b, kick, o, 1.0 if k == "x" else 0.5, true)
			if sn == "x":
				Synth.add(b, snare, o, 0.8, true)
			elif sn == "o":
				Synth.add(b, ghost, o, 0.7, true)
			if h == "x":
				Synth.add(b, hat, o, 0.35, true)
			elif h == "o":
				Synth.add(b, open, o, 0.3, true)


# --- LEAD: pulse 1, the tune ---

static func _lead(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var notes := Music.melody(song, tl, rng, [RHYTHMS_SPARSE, RHYTHMS_BUSY], LEAD_LO, LEAD_HI)
	var duty: float = song.get("duty", 0.5)
	var cache := {}
	for nt in notes:
		var held := float(int(nt[2]) * step) / Synth.RATE * 0.94
		var key := "%d:%d" % [nt[3], nt[2]]
		if not cache.has(key):
			var vib := 0.28 if held > 0.3 else 0.0
			cache[key] = env(pulse(Synth.midi_hz(nt[3]), held + 0.04, duty, vib, 0.22), 0.9, 0.5, held, 0.6)
			if Music.abort:
				return
		Synth.add(b, cache[key], Music.at(nt[0], nt[1], step, song), 1.0, true)
	if song.get("lead_echo", false):            # a second channel copying the tune a 16th late, quietly
		var copy := b.duplicate()
		Synth.add(b, copy, step * 3, 0.25, true)
