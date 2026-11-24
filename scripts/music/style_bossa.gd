class_name StyleBossa
extends RefCounted
## CAFE LOUNGE (FM 106.9): bossa nova and late-night jazz.
##   PAD   "guitar": nylon-string chords (Karplus-Strong, rolled with the thumb) in the bossa comp rhythm, or
##         "rhodes": soft FM electric piano comping (charleston on the swing tunes)
##   BASS  upright bass: "bossa" root-fifth 2-feel, or "walk" = a walking line (chord tones + chromatic approach)
##   DRUMS "bossa": rim-click clave, soft kick, shaker 16ths. "swing": ride pattern, brush swish, hi-hat on 2 & 4
##   LEAD  "vibes" (vibraphone: sine bars + tremolo) or "flute" (breathy sine with vibrato)
## Song keys: groove ("bossa"|"samba"|"swing"|"ballad"), pad, bass, lead.

const GROOVES := {
	"bossa": {"comp": "x-.x-.x---.x-.x-", "kick": "x..x....x..x....", "rim": "x..x..x...x..x..",
		"bass": [[0, 5, 0], [6, 2, 7], [8, 5, 7], [14, 2, 0]]},
	"samba": {"comp": "x.xx.x.x.xx.x.x.", "kick": "x..xx..xx..xx..x", "rim": "x..x..x...x.x...",
		"bass": [[0, 3, 0], [3, 1, 0], [4, 3, 7], [7, 1, 7], [8, 3, 0], [11, 1, 0], [12, 3, 7], [15, 1, 7]]},
	"swing": {"comp": "x-----x---------", "ride": "x...x.x.x...x.x.", "foot": "....x.......x...",
		"bass": []},
	"ballad": {"comp": "x-------x-------", "ride": "x...x.x.x...x.x.", "foot": "....x.......x...",
		"bass": []},
}
const RHYTHMS_SPARSE := ["x-----x---------", "x-----------x---", "x--x--x---------", "..x-------x-----",
	"x-------x-------"]
const RHYTHMS_BUSY := ["x--x--x---x-x---", "x-x-x---x--x----", "..x-x-x---x-----", "x--x--x-x-x-----",
	"x-x---x-x-x-x---"]
const GAINS := [0.55, 0.6, 0.5, 0.5]
const LEAD_LO := 67
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


# --- PAD ---

static func _pad(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var hits := Music.parse_rhythm(groove.comp)
	var guitar: bool = song.get("pad", "guitar") == "guitar"
	var cache := {}
	for bar in tl.size():
		for h in hits:
			var s: int = h[0]
			var seg := Music.chord_at(tl, bar, s)
			var v := Music.voicing(seg[2], 52, 69) if guitar else Music.voicing(seg[2], 55, 74, true)
			var held := float(int(h[1]) * step) / Synth.RATE * 0.92
			var o := Music.at(bar, s, step, song)
			var roll := 150 if guitar else 40          # frames between strings
			for i in v.size():
				var key := "%d:%d" % [v[i], h[1]]
				if not cache.has(key):
					cache[key] = _nylon(Synth.midi_hz(v[i]), held, rng) if guitar else StyleCityPop.epiano(
						Synth.midi_hz(v[i]), held)
					if Music.abort:
						return
				var g := 0.5 if s % 4 == 0 else 0.4
				Synth.add(b, cache[key], o + i * roll, g * rng.randf_range(0.85, 1.0), true)
	if not guitar:
		Synth.am(b, 4.0 * float(song.bpm) / 240.0, 0.12)    # gentle Rhodes tremolo, synced to the beat


static func _nylon(f: float, held: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var t := Synth.pluck(f, held + 0.1, rng, 0.997, 0.35)
	Synth.lp(t, 2800.0)
	return Synth.adsr(t, 0.001, 0.05, 0.9, held)


# --- BASS ---

static func _upright(f: float, held: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := held + 0.12
	var t := Synth.tone(Synth.SINE, f, sec)
	Synth.add(t, Synth.tone(Synth.TRI, f, sec), 0, 0.35)
	Synth.add(t, Synth.tone(Synth.SINE, f * 2.0, sec), 0, 0.15)
	Synth.decay(t, 0.004, 0.55)
	Synth.add(t, Synth.perc(Synth.lp(Synth.noise(0.03, rng), 500.0), 0.001, 2.0), 0, 0.35)   # finger thump
	Synth.lp(t, 900.0)
	return Synth.adsr(t, 0.002, 0.05, 0.9, held)


static func _bass(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var line := _walk(song, tl) if song.get("bass", "bossa") == "walk" else _two_feel(song, tl)
	var cache := {}
	for nt in line:                               # [bar, step, length, midi]
		var held := float(int(nt[2]) * step) / Synth.RATE * 0.88
		var key := "%d:%d" % [nt[3], nt[2]]
		if not cache.has(key):
			cache[key] = _upright(Synth.midi_hz(nt[3]), held, rng)
		Synth.add(b, cache[key], Music.at(nt[0], nt[1], step, song), 1.0 if nt[1] % 4 == 0 else 0.8, true)


static func _two_feel(song: Dictionary, tl: Array) -> Array:
	var groove: Dictionary = GROOVES[song.groove]
	var out := []
	for bar in tl.size():
		for nt in groove.bass:
			var seg := Music.chord_at(tl, bar, int(nt[0]))
			var m: int = 33 + posmod(int(seg[1]) - 9, 12) + Music.bass_iv(seg, int(nt[2]))
			out.append([bar, nt[0], nt[1], m])
	return out


## Walking bass: quarter notes; a chord's first beat plays its root, the middle beats chord tones / scale steps,
## and the beat before a chord change walks in chromatically (a semitone above or below the next root).
static func _walk(song: Dictionary, tl: Array) -> Array:
	var segs := Music.segments(tl)
	var pcs := Music.scale_pcs(song)
	var out := []
	var prev := 40
	for i in segs.size():
		var bar: int = segs[i][0]
		var st: int = segs[i][1]
		var len_s: int = segs[i][2]
		var seg: Array = segs[i][3]
		var nxt: Array = segs[(i + 1) % segs.size()][3]
		var beats := len_s / 4
		for k in beats:
			var m: int
			if k == 0:
				m = _near(int(seg[1]), prev, 31, 50)
			elif k == beats - 1:
				var target := _near(int(nxt[1]), prev, 31, 50)
				m = target + (1 if (bar + k) % 2 == 0 else -1)
			elif k % 2 == 1:
				m = _near(int(seg[2][1 + (bar + k) % 2]), prev, 31, 50)    # third or fifth
			else:
				var stepwise := prev + (2 if prev < 43 else -2)
				m = Music._snap_in(stepwise, pcs, 31, 50)
			out.append([bar, st + k * 4, 4, m])
			prev = m
	return out


## The MIDI note of pitch class pc in [lo, hi] closest to `near`.
static func _near(pc: int, near: int, lo: int, hi: int) -> int:
	return Music._snap_in(near, [pc], lo, hi)


# --- DRUMS ---

static func _drums(b: PackedFloat32Array, song: Dictionary, bars: int, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	if groove.has("rim"):
		var rim := Synth.norm(Synth.perc(Synth.bp(Synth.tone(Synth.SQUARE, 1750.0, 0.025), 1800.0, -1.0, 3.0), 0.0005, 3.0))
		Synth.add(rim, Synth.norm(Synth.perc(Synth.hp(Synth.noise(0.015, rng), 3000.0), 0.0005, 3.0)), 0, 0.4)
		var kick := Synth.norm(Synth.perc(Synth.tone(Synth.SINE, 95.0, 0.22, 52.0), 0.003, 2.4))
		var shaker := Synth.norm(Synth.swell(Synth.bp(Synth.noise(0.07, rng), 6500.0, -1.0, 0.8), 0.3, 1.5, 2.2))
		for bar in bars:
			for s in Music.STEPS:
				var o := Music.at(bar, s, step, song)
				if groove.rim[s] == "x":
					Synth.add(b, rim, o, 0.45, true)
				if groove.kick[s] == "x":
					Synth.add(b, kick, o, 0.55 if s % 4 == 0 else 0.35, true)
				Synth.add(b, shaker, o, (0.16 if s % 4 == 2 else 0.09) * rng.randf_range(0.8, 1.0), true)
		return
	# swing kit: ride cymbal (inharmonic partials + sizzle), brush swish, hi-hat foot on 2 and 4
	var ride := Synth.empty(0.7)
	for p in [[3150.0, 0.5], [4870.0, 0.35], [6620.0, 0.3], [8230.0, 0.2]]:
		Synth.add(ride, Synth.decay(Synth.tone(Synth.SINE, p[0], 0.7), 0.0005, 0.35), 0, p[1])
	Synth.add(ride, Synth.decay(Synth.hp(Synth.noise(0.7, rng), 7000.0), 0.0005, 0.25), 0, 0.5)
	Synth.norm(ride)
	var foot := Synth.norm(Synth.perc(Synth.bp(Synth.noise(0.05, rng), 5000.0, -1.0, 0.8), 0.002, 2.5))
	var brush := Synth.norm(Synth.swell(Synth.bp(Synth.noise(0.32, rng), 3600.0, -1.0, 0.6), 0.55, 1.6, 1.4))
	for bar in bars:
		for s in Music.STEPS:
			var o := Music.at(bar, s, step, song)
			if groove.ride[s] == "x":
				Synth.add(b, ride, o, (0.35 if s % 8 == 4 else 0.25) * rng.randf_range(0.85, 1.0), true)
			if groove.foot[s] == "x":
				Synth.add(b, foot, o, 0.3, true)
				Synth.add(b, brush, o - Synth.frames(0.12), 0.18, true)


# --- LEAD ---

static func _lead(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var notes := Music.melody(song, tl, rng, [RHYTHMS_SPARSE, RHYTHMS_BUSY], LEAD_LO, LEAD_HI)
	var flute: bool = song.get("lead", "vibes") == "flute"
	var cache := {}
	for nt in notes:
		var held := float(int(nt[2]) * step) / Synth.RATE * 0.92
		var key := "%d:%d" % [nt[3], nt[2]]
		if not cache.has(key):
			cache[key] = _flute(Synth.midi_hz(nt[3]), held, rng) if flute else _vibes(Synth.midi_hz(nt[3]), held)
			if Music.abort:
				return
		Synth.add(b, cache[key], Music.at(nt[0], nt[1], step, song), 1.0, true)
	var n := b.size()
	Music.seamless(b, func(c: PackedFloat32Array) -> void:
		Synth.echo(c, 0.19, 0.3, 0.22, 0.0)        # a small club room
		c.resize(n * 2))


## Vibraphone: a sine bar with its 4x partial, long ring, motor tremolo; the mallet is let go at `held`.
static func _vibes(f: float, held: float) -> PackedFloat32Array:
	var sec := held + 0.5
	var t := Synth.tone(Synth.SINE, f, sec)
	Synth.add(t, Synth.decay(Synth.tone(Synth.SINE, f * 4.0, sec), 0.0005, 0.12), 0, 0.25)
	Synth.decay(t, 0.001, 1.1)
	Synth.am(t, 5.2, 0.3)
	return Synth.adsr(t, 0.001, 0.02, 1.0, held)


static func _flute(f: float, held: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sec := held + 0.15
	var t := Synth.tone(Synth.SINE, f, sec, -1.0, 0.5, 0.22, 5.0, null, 0.16)
	Synth.add(t, Synth.tone(Synth.SINE, f * 2.0, sec, -1.0, 0.5, 0.22, 5.0, null, 0.16), 0, 0.18)
	Synth.add(t, Synth.bp(Synth.noise(sec, rng), f * 2.0, -1.0, 4.0), 0, 0.12)
	Synth.add(t, Synth.perc(Synth.bp(Synth.noise(0.05, rng), 2500.0, -1.0, 1.0), 0.002, 2.0), 0, 0.12)   # chiff
	return Synth.adsr(t, 0.05, 0.1, 0.85, held)
