class_name StyleSynthwave
extends RefCounted
## NEON DRIVE (FM 97.1): 80s-soundtrack synthwave.
##   PAD   supersaw chords (detuned saws) under a slow low-pass sweep, plus a 16th arpeggio with a dotted-8th echo
##   BASS  saw bass pulsing in 8ths (straight or octave-jumping), short notes so it pumps against the kick
##   DRUMS big sine kick, gated-reverb snare + clap, 8th/16th hats, tom fill into every 8th bar
##   LEAD  detuned saw + square lead, delayed vibrato, long feedback echo
## Song keys: groove, arp (bool), sweep ([lo, hi] Hz of the pad filter), lead_echo (feedback 0..0.6).

const GROOVES := {
	"halftime": {"kick": "x.........x.....", "snare": "........x.......", "hat": "x.x.x.x.x.x.x.x.",
		"bass": [[0, 2, 0], [2, 2, 0], [4, 2, 0], [6, 2, 0], [8, 2, 0], [10, 2, 0], [12, 2, 0], [14, 2, 12]]},
	"drive": {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x.",
		"bass": [[0, 2, 0], [2, 2, 12], [4, 2, 0], [6, 2, 12], [8, 2, 0], [10, 2, 12], [12, 2, 0], [14, 2, 12]]},
	"run": {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "xxxxxxxxxxxxxxxx",
		"bass": [[0, 1, 0], [1, 1, 0], [2, 1, 12], [3, 1, 0], [4, 1, 0], [5, 1, 0], [6, 1, 12], [7, 1, 0],
			[8, 1, 0], [9, 1, 0], [10, 1, 12], [11, 1, 0], [12, 1, 0], [13, 1, 0], [14, 1, 12], [15, 1, 7]]},
	"slow": {"kick": "x.........x.....", "snare": "........x.......", "hat": "..x...x...x...x.",
		"bass": [[0, 6, 0], [6, 2, 0], [8, 4, 7], [12, 4, 0]]},
}
const ARP := [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1, 2, 3]   ## voicing index per 16th (wraps up an octave)
const RHYTHMS_SPARSE := ["x-------x---x---", "x-----x---------", "x-----------x-x-", "x---x-------x---",
	"x-------x-------"]
const RHYTHMS_BUSY := ["x---x-x-x-------", "x-x---x---x-x---", "x--x--x-----x---", "x---x---x-x-x---",
	"x-x-x-----x-----"]
const GAINS := [0.55, 0.55, 0.75, 0.5]
const LEAD_LO := 64
const LEAD_HI := 84


static func render(stems: Array, song: Dictionary, step: int, rng: RandomNumberGenerator) -> Array:
	var tl := Music.timeline(song, Music.bars_of(song))
	_pad(stems[Music.PAD], song, tl, step)
	if Music.abort:
		return GAINS
	_bass(stems[Music.BASS], song, tl, step)
	_drums(stems[Music.DRUMS], song, tl.size(), step, rng)
	if Music.abort:
		return GAINS
	_lead(stems[Music.LEAD], song, tl, step, rng)
	return GAINS


static func supersaw(f: float, sec: float) -> PackedFloat32Array:
	var b := Synth.tone(Synth.SAW, f, sec, -1.0, 0.5, 0.06, 0.3)
	Synth.add(b, Synth.tone(Synth.SAW, f * 1.0071, sec, -1.0, 0.5, 0.05, 0.4), 0, 0.8)
	Synth.add(b, Synth.tone(Synth.SAW, f * 0.9932, sec, -1.0, 0.5, 0.05, 0.5), 0, 0.8)
	Synth.add(b, Synth.tone(Synth.SQUARE, f * 0.5, sec, -1.0, 0.5), 0, 0.25)
	return b


# --- PAD ---

static func _pad(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int) -> void:
	var cache := {}
	for seg_info in Music.segments(tl):
		var seg: Array = seg_info[3]
		var held := float(int(seg_info[2]) * step) / Synth.RATE
		var v := Music.voicing(seg[2], 53, 72)
		var g := 1.0 / sqrt(v.size())
		for m in v:
			var key := "%d:%d" % [m, seg_info[2]]
			if not cache.has(key):
				cache[key] = Synth.adsr(supersaw(Synth.midi_hz(m), held + 0.5), 0.25, 0.5, 0.75, held)
				if Music.abort:
					return
			Synth.add(b, cache[key], Music.at(seg_info[0], seg_info[1], step, {}), g, true)
	var sweep: Array = song.get("sweep", [700.0, 2600.0])
	var cycles := maxf(roundf(tl.size() / 4.0), 1.0)             # one sweep per 4 bars
	var hz := cycles / (float(b.size()) / Synth.RATE)
	Music.seamless(b, func(c: PackedFloat32Array) -> void: Synth.lp_lfo(c, sweep[0], sweep[1], hz, 0.9))
	if not song.get("arp", true):
		return
	var arp := PackedFloat32Array()
	arp.resize(b.size())
	arp.fill(0.0)
	var acache := {}
	for bar in tl.size():
		for s in Music.STEPS:
			var seg := Music.chord_at(tl, bar, s)
			var v := Music.voicing(seg[2], 64, 76)
			var i: int = ARP[s]
			var m: int = v[i % v.size()] + 12 * (i / v.size())
			if not acache.has(m):
				var t := Synth.tone(Synth.SQUARE, Synth.midi_hz(m), float(step) / Synth.RATE * 1.6, -1.0, 0.3)
				Synth.add(t, Synth.tone(Synth.SAW, Synth.midi_hz(m) * 1.004, float(step) / Synth.RATE * 1.6), 0, 0.5)
				acache[m] = Synth.perc(Synth.lp(t, 3200.0, 1200.0), 0.002, 2.2)
			Synth.add(arp, acache[m], Music.at(bar, s, step, song), 0.8 if s % 4 == 0 else 0.55, true)
	var d := float(step * 3) / Synth.RATE
	Music.seamless(arp, func(c: PackedFloat32Array) -> void:
		Synth.echo(c, d, 0.42, 0.45, 0.0)
		c.resize(arp.size() * 2))
	Synth.add(b, Synth.norm(arp), 0, Synth.peak(b) * 0.42)


# --- BASS ---

static func _bass(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var cache := {}
	for bar in tl.size():
		for nt in groove.bass:
			var s: int = nt[0]
			var seg := Music.chord_at(tl, bar, s)
			var m: int = 33 + posmod(int(seg[1]) - 9, 12) + Music.bass_iv(seg, int(nt[2]))
			var held := float(int(nt[1]) * step) / Synth.RATE * 0.75
			var key := "%d:%d" % [m, int(nt[1])]
			if not cache.has(key):
				var f := Synth.midi_hz(m)
				var t := Synth.tone(Synth.SAW, f, held + 0.05)
				Synth.add(t, Synth.tone(Synth.SAW, f * 1.006, held + 0.05), 0, 0.6)
				Synth.add(t, Synth.tone(Synth.SINE, f, held + 0.05), 0, 0.8)
				Synth.lp(t, 1400.0, 260.0, 1.1)               # filter envelope: bright pluck closing down
				cache[key] = Synth.adsr(t, 0.003, 0.08, 0.7, held)
			Synth.add(b, cache[key], Music.at(bar, s, step, song), 1.0, true)


# --- DRUMS ---

static func _drums(b: PackedFloat32Array, song: Dictionary, bars: int, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var kick := Synth.norm(Synth.perc(Synth.tone(Synth.SINE, 150.0, 0.34, 44.0), 0.001, 2.2))
	Synth.add(kick, Synth.norm(Synth.perc(Synth.hp(Synth.noise(0.012, rng), 2500.0), 0.0005, 2.0)), 0, 0.35)
	Synth.drive(kick, 1.6)
	# gated reverb snare: noise + body through a dense echo "room", then chopped off hard
	var snare := Synth.norm(Synth.perc(Synth.bp(Synth.noise(0.2, rng), 1700.0, -1.0, 0.7), 0.001, 1.6))
	Synth.add(snare, Synth.norm(Synth.perc(Synth.tone(Synth.TRI, 210.0, 0.09, 170.0), 0.001, 2.0)), 0, 0.6)
	var clap := Synth.empty(0.03)
	for k in 3:
		Synth.add_at(clap, Synth.perc(Synth.bp(Synth.noise(0.012, rng), 1300.0, -1.0, 1.2), 0.0005, 2.0), k * 0.009)
	Synth.add(snare, Synth.norm(clap), 0, 0.5)
	Synth.echo(snare, 0.017, 0.55, 0.6, 0.2)
	Synth.echo(snare, 0.029, 0.5, 0.5, 0.1)
	Music.gate(Synth.norm(snare), 0.26)
	var hat := Synth.norm(Synth.perc(Synth.hp(Synth.noise(0.04, rng), 7500.0), 0.0005, 3.0))
	var toms := []
	for f in [190.0, 150.0, 115.0]:
		toms.append(Synth.norm(Synth.perc(Synth.tone(Synth.SINE, f, 0.3, f * 0.55), 0.001, 2.0)))
	for bar in bars:
		var fill := bar % 8 == 7
		for s in Music.STEPS:
			var o := Music.at(bar, s, step, song)
			if fill and s >= 10:
				if s % 2 == 0:
					Synth.add(b, toms[mini((s - 10) / 2, 2)], o, 0.7, true)
				continue
			if groove.kick[s] == "x":
				Synth.add(b, kick, o, 1.0, true)
			if groove.snare[s] == "x":
				Synth.add(b, snare, o, 0.8, true)
			if groove.hat[s] == "x":
				Synth.add(b, hat, o, (0.22 if s % 2 == 0 else 0.14) * rng.randf_range(0.85, 1.0), true)


# --- LEAD ---

static func _lead(b: PackedFloat32Array, song: Dictionary, tl: Array, step: int, rng: RandomNumberGenerator) -> void:
	var notes := Music.melody(song, tl, rng, [RHYTHMS_SPARSE, RHYTHMS_BUSY], LEAD_LO, LEAD_HI)
	var cache := {}
	for nt in notes:
		var held := float(int(nt[2]) * step) / Synth.RATE * 0.9
		var key := "%d:%d" % [nt[3], nt[2]]
		if not cache.has(key):
			var f := Synth.midi_hz(nt[3])
			var sec := held + 0.25
			var t := Synth.tone(Synth.SAW, f, sec, -1.0, 0.5, 0.22, 5.2, null, 0.25)
			Synth.add(t, Synth.tone(Synth.SQUARE, f * 1.005, sec, -1.0, 0.4, 0.22, 5.2, null, 0.25), 0, 0.6)
			Synth.lp(t, 3600.0, 2200.0, 0.9)
			cache[key] = Synth.adsr(t, 0.015, 0.2, 0.75, held)
			if Music.abort:
				return
		Synth.add(b, cache[key], Music.at(nt[0], nt[1], step, song), 1.0, true)
	var fb: float = song.get("lead_echo", 0.4)
	var d := float(step * 3) / Synth.RATE
	var n := b.size()
	Music.seamless(b, func(c: PackedFloat32Array) -> void:
		Synth.echo(c, d, fb, 0.5, 0.0)
		c.resize(n * 2))
