class_name Music
extends RefCounted
## Procedural radio music (Phase 4). A song is a dict from Radio.STATIONS (one per station x time-of-day phase:
## style, bpm, key, scale/minor, prog, groove, swing, density, ...) rendered offline into four equal-length,
## seamlessly looping stems packed into an AudioStreamSynchronized: PAD, BASS, DRUMS, LEAD. Every style keeps
## that stem contract, so Sound's layers (menu = pad + bass, drums on the zoom, lead with speed), the tape stop and
## note() work on every station. `style` picks the arranger:
##   lofi       (here) detuned saw pads + vinyl, triangle bass, swung sine/noise drums, pentatonic square lead
##   rpg        StyleRpg: handheld-console chip (2 pulses, 4-bit wave bass, LFSR noise)
##   synthwave  StyleSynthwave: supersaw pads + arp, octave saw bass, gated snare, echoing saw lead
##   citypop    StyleCityPop: FM electric piano comping, plucky funk bass, disco kit, synth/sax lead
##   bossa      StyleBossa: nylon guitar / Rhodes comping, upright bass (bossa or walking), rim/shaker/ride, vibes/flute
## render() only touches its own data, so it runs on a worker thread; notes are rendered once per (instrument,
## pitch, length) and mixed in with wrap-around (seamless loop). Whole-stem effects go through seamless().
## The lofi arranger (8 bars, motif A, A', A, B) is the original game music and is left exactly as it was.

enum { PAD, BASS, DRUMS, LEAD }
const STEMS := 4
const BARS := 8
const STEPS := 16                         ## sixteenth notes per bar
const MAJOR_PENTA := [0, 2, 4, 7, 9]
const MINOR_PENTA := [0, 3, 5, 7, 10]
## Note sets for the newer styles' melodies (song.scale; default = the pentatonic of song.minor).
const SCALES := {
	"penta": [0, 2, 4, 7, 9], "minor_penta": [0, 3, 5, 7, 10], "major": [0, 2, 4, 5, 7, 9, 11],
	"minor": [0, 2, 3, 5, 7, 8, 10], "dorian": [0, 2, 3, 5, 7, 9, 10], "mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
}
const MINOR_SCALES := ["minor", "dorian", "minor_penta"]
## Intervals above the root. Index 1 is always the third (or the sus 4th), index 2 the fifth: the bass's
## "fifth" (iv 7) uses index 2, so diminished / half-diminished chords get their flat fifth.
const CHORDS := {
	"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "maj9": [0, 4, 7, 11, 14],
	"m9": [0, 3, 7, 10, 14], "add9": [0, 4, 7, 14], "sus": [0, 5, 7, 10],
	"maj": [0, 4, 7], "min": [0, 3, 7], "dim": [0, 3, 6], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9],
	"m7b5": [0, 3, 6, 10], "9": [0, 4, 7, 10, 14], "13": [0, 4, 7, 10, 21], "7sus4": [0, 5, 7, 10],
	"m11": [0, 3, 7, 10, 17], "6/9": [0, 4, 7, 9, 14],
}
## Drum grooves: one bar each, x = hit, o = ghost (soft). bass = [[step, length, interval above the root], ...].
const GROOVES := {
	"sparse": {"kick": "x.........x.....", "snare": "........x.......", "hat": "x...x...x...x...",
		"bass": [[0, 8, 0], [10, 6, 7]]},
	"lofi": {"kick": "x.....x...x.....", "snare": "....x.......x...", "hat": "x.o.x.o.x.o.x.o.",
		"bass": [[0, 6, 0], [6, 2, 0], [10, 4, 7], [14, 2, 12]]},
	"full": {"kick": "x.....x.x.....x.", "snare": "....x.......x..o", "hat": "xoxoxoxoxoxoxoxo",
		"bass": [[0, 4, 0], [6, 2, 0], [8, 4, 7], [12, 2, 12], [14, 2, 7]]},
	"dusk": {"kick": "x......x..x.....", "snare": "....x.......x...", "hat": "x.o.x.o.x.o.x.oo",
		"bass": [[0, 7, 0], [7, 3, 7], [10, 6, 0]]},
	"night": {"kick": "x.........x.....", "snare": "........x.......", "hat": "..x...x...x...x.",
		"bass": [[0, 10, 0], [10, 6, 7]]},
}
## Lead rhythm templates (one bar); picked by density.
const RHYTHMS_SPARSE := ["x.......x.......", "x...........x...", "....x.......x...", "x.....x.........", "..x.......x....."]
const RHYTHMS_BUSY := ["x...x...x.x.....", "..x...x.x...x...", "x..x..x...x.....", "x.x...x...x.....",
	"....x.x.x...x...", "x...x.....x.x..."]
const STEM_GAIN := [0.6, 0.45, 0.7, 0.45]
const LEAD_LO := 67                       ## lead range (MIDI)
const LEAD_HI := 86

static var abort := false                 ## set at quit: render() bails out early


## Station 0 (lo-fi) keeps the seeds it always had, so its songs are unchanged.
static func seed_for(station: int, phase: int) -> int:
	return 7919 * (phase + 1) + 104729 * station


## Loop length in bars (song.bars, default BARS).
static func bars_of(song: Dictionary) -> int:
	return int(song.get("bars", BARS))


static func is_minor(song: Dictionary) -> bool:
	return song.get("minor", false) or MINOR_SCALES.has(song.get("scale", ""))


## Render a whole song (blocking; call from a worker thread). Returns null if aborted.
static func render(song: Dictionary, seed: int) -> AudioStreamSynchronized:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var step := roundi(Synth.RATE * 60.0 / float(song.bpm) / 4.0)
	var n := step * STEPS * bars_of(song)
	var stems: Array[PackedFloat32Array] = []
	for i in STEMS:
		var b := PackedFloat32Array()
		b.resize(n)
		b.fill(0.0)
		stems.append(b)
	var gains: Array = STEM_GAIN
	match song.get("style", "lofi"):
		"rpg":
			gains = StyleRpg.render(stems, song, step, rng)
		"synthwave":
			gains = StyleSynthwave.render(stems, song, step, rng)
		"citypop":
			gains = StyleCityPop.render(stems, song, step, rng)
		"bossa":
			gains = StyleBossa.render(stems, song, step, rng)
		_:
			var chords := _chords(song)
			_pad(stems[PAD], song, chords, step, rng)
			if abort:
				return null
			_bass(stems[BASS], song, chords, step)
			if abort:
				return null
			_drums(stems[DRUMS], song, step, rng)
			if abort:
				return null
			_lead(stems[LEAD], song, chords, step, rng)
	if abort:
		return null
	# balance the stems, then scale them together so the full mix peaks just under 1
	var mix := PackedFloat32Array()
	mix.resize(n)
	mix.fill(0.0)
	for i in STEMS:
		Synth.norm(stems[i], gains[i])
		Synth.add(mix, stems[i])
	var k := 0.9 / maxf(Synth.peak(mix), 0.001)
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = STEMS
	for i in STEMS:
		sync.set_sync_stream(i, Synth.to_wav(Synth.scale(stems[i], k), 1.0, true, 0.0, false))
		sync.set_sync_stream_volume(i, -80.0)
	return sync


## Per bar: [root pitch class, chord tone pitch classes]. The 4-chord progression repeats to fill 8 bars.
static func _chords(song: Dictionary) -> Array:
	var out := []
	var prog: Array = song.prog
	for bar in BARS:
		var c: Array = prog[bar % prog.size()]
		var root: int = (int(song.key) + int(c[0])) % 12
		var tones := []
		for iv in CHORDS[c[1]]:
			tones.append(root + int(iv))
		out.append([root, tones])
	return out


static func _onset(s: int, step: int, swing: float) -> int:
	return s * step + (roundi(swing * step * 0.5) if s % 2 == 1 else 0)


# --- PAD ---

static func _pad(b: PackedFloat32Array, song: Dictionary, chords: Array, step: int, rng: RandomNumberGenerator) -> void:
	var bar_sec := float(step * STEPS) / Synth.RATE
	var cache := {}
	for bar in BARS:
		var tones: Array = chords[bar][1]
		var voiced := {}
		for t in tones:
			var m: int = 48 + t
			while m < 55:
				m += 12
			while m >= 71:
				m -= 12
			voiced[m] = true
		var g := 1.0 / sqrt(voiced.size())
		for m in voiced:
			if not cache.has(m):
				cache[m] = _pad_note(Synth.midi_hz(m), bar_sec)
				if abort:
					return
			Synth.add(b, cache[m], bar * STEPS * step, g, true)
	var c: float = song.get("crackle", 0.4)
	var sec := float(b.size()) / Synth.RATE
	var vinyl := Synth.lp(Synth.clicks(sec, rng, 7.0 * c), 3500.0)
	Synth.add(b, Synth.norm(vinyl), 0, 0.18 * c)
	Synth.add(b, Synth.lp(Synth.noise(sec, rng), 2500.0), 0, 0.012 * c)


static func _pad_note(f: float, held: float) -> PackedFloat32Array:
	var sec := held + 0.6
	var b := Synth.tone(Synth.SAW, f * 1.004, sec, -1.0, 0.5, 0.1, 0.4)
	Synth.add(b, Synth.tone(Synth.SAW, f * 0.996, sec, -1.0, 0.5, 0.1, 0.33))
	Synth.add(b, Synth.tone(Synth.TRI, f * 2.0, sec), 0, 0.25)
	Synth.lp(b, 700.0, 1300.0, 0.6)
	return Synth.adsr(b, 0.3, 0.6, 0.7, held)


# --- BASS ---

static func _bass(b: PackedFloat32Array, song: Dictionary, chords: Array, step: int) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var swing: float = song.get("swing", 0.2)
	var cache := {}
	for bar in BARS:
		var root: int = 36 + int(chords[bar][0])
		for nt in groove.bass:
			var m: int = root + int(nt[2])
			var held := float(int(nt[1]) * step) / Synth.RATE * 0.9
			var key := "%d:%d" % [m, int(nt[1])]
			if not cache.has(key):
				cache[key] = _bass_note(Synth.midi_hz(m), held)
			Synth.add(b, cache[key], bar * STEPS * step + _onset(int(nt[0]), step, swing), 1.0, true)


static func _bass_note(f: float, held: float) -> PackedFloat32Array:
	var b := Synth.tone(Synth.TRI, f, held + 0.08)
	Synth.add(b, Synth.tone(Synth.SINE, f, held + 0.08), 0, 0.6)
	Synth.drive(Synth.lp(b, 650.0), 1.3)
	return Synth.adsr(b, 0.005, 0.25, 0.55, held)


# --- DRUMS ---

static func _drums(b: PackedFloat32Array, song: Dictionary, step: int, rng: RandomNumberGenerator) -> void:
	var groove: Dictionary = GROOVES[song.groove]
	var swing: float = song.get("swing", 0.2)
	var kick := Synth.norm(Synth.perc(Synth.tone(Synth.SINE, 120.0, 0.28, 42.0), 0.002, 2.5))
	Synth.add(kick, Synth.perc(Synth.lp(Synth.noise(0.01, rng), 2000.0), 0.0005, 2.0), 0, 0.3)
	var snare := Synth.norm(Synth.perc(Synth.bp(Synth.noise(0.18, rng), 1800.0, -1.0, 0.8), 0.002, 2.2))
	Synth.add(snare, Synth.norm(Synth.perc(Synth.tone(Synth.TRI, 190.0, 0.08, 160.0), 0.002, 2.0)), 0, 0.5)
	Synth.lp(snare, 5000.0)
	var hat := Synth.norm(Synth.perc(Synth.hp(Synth.noise(0.035, rng), 6000.0), 0.001, 3.0))
	var parts := [["kick", kick, 1.0], ["snare", snare, 0.7], ["hat", hat, 0.28]]
	for bar in BARS:
		var fill := bar % 4 == 3                  # end of each 4-bar phrase: a pickup kick + ghost snare
		for part in parts:
			var pat: String = groove[part[0]]
			for s in STEPS:
				var ch := pat[s]
				if fill and s >= 14:
					ch = "o" if part[0] != "hat" else ch
				if ch == ".":
					continue
				var g: float = part[2] * (1.0 if ch == "x" else 0.45)
				if part[0] == "hat":
					g *= rng.randf_range(0.75, 1.0)
				Synth.add(b, part[1], bar * STEPS * step + _onset(s, step, swing), g, true)
	Synth.lp(b, 7000.0)


# --- LEAD ---

static func _lead(b: PackedFloat32Array, song: Dictionary, chords: Array, step: int, rng: RandomNumberGenerator) -> void:
	var penta: Array = MINOR_PENTA if song.get("minor", false) else MAJOR_PENTA
	var key: int = song.key
	var density: float = song.get("density", 0.5)
	var swing: float = song.get("swing", 0.2)
	var rA := [_rhythm(rng, density), _rhythm(rng, density)]
	var rB := [_rhythm(rng, density), _rhythm(rng, density)]
	var movesA := _moves(rng, 12)
	var movesB := _moves(rng, 12)
	var notes := []                               # [bar, step, length, midi]
	var cur := 72 + key % 12
	cur = _gen_bars(notes, [0, 1], rA, movesA, chords, penta, key, cur, false)
	cur = _gen_bars(notes, [2, 3], rA, movesA, chords, penta, key, cur, false)
	for nt in notes.duplicate():                  # bars 5-6 repeat the motif (same chords)
		if nt[0] <= 1:
			notes.append([nt[0] + 4, nt[1], nt[2], nt[3]])
	_gen_bars(notes, [6, 7], rB, movesB, chords, penta, key, cur, true)
	var cache := {}
	var echo_d := 3                               # dotted eighth
	for nt in notes:
		var held := float(int(nt[2]) * step) / Synth.RATE * 0.85
		var ck := "%d:%d" % [nt[3], nt[2]]
		if not cache.has(ck):
			cache[ck] = _lead_note(Synth.midi_hz(nt[3]), held)
			if abort:
				return
		var at: int = nt[0] * STEPS * step + _onset(int(nt[1]), step, swing)
		Synth.add(b, cache[ck], at, 1.0, true)
		Synth.add(b, cache[ck], at + echo_d * step, 0.32, true)
		Synth.add(b, cache[ck], at + echo_d * 2 * step, 0.12, true)


static func _rhythm(rng: RandomNumberGenerator, density: float) -> String:
	var pool: Array = RHYTHMS_BUSY if rng.randf() < density else RHYTHMS_SPARSE
	return pool[rng.randi() % pool.size()]


## Melodic contour: mostly steps of one scale degree, sometimes a leap of two.
static func _moves(rng: RandomNumberGenerator, count: int) -> Array:
	var out := []
	for i in count:
		var m := 1 if rng.randf() < 0.5 else -1
		if rng.randf() < 0.25:
			m *= 2
		if rng.randf() < 0.12:
			m = 0
		out.append(m)
	return out


## Notes for two bars from rhythm templates + contour. Strong beats snap to chord tones; the final note of an
## ending phrase lands on the chord root and rings to the bar end. Returns the last pitch.
static func _gen_bars(notes: Array, bars: Array, rhythms: Array, moves: Array, chords: Array, penta: Array,
		key: int, cur: int, ending: bool) -> int:
	var mi := 0
	for j in bars.size():
		var bar: int = bars[j]
		var pat: String = rhythms[j]
		var allowed := _allowed(chords[bar][1], penta, key)
		var tones: Array = chords[bar][1]
		var onsets := []
		for s in STEPS:
			if pat[s] == "x":
				onsets.append(s)
		for k in onsets.size():
			var s: int = onsets[k]
			var idx := _nearest(allowed, cur)
			idx = clampi(idx + int(moves[mi % moves.size()]), 0, allowed.size() - 1)
			mi += 1
			cur = allowed[idx]
			var last := ending and j == bars.size() - 1 and k == onsets.size() - 1
			if s % 8 == 0 or last:
				cur = _snap(cur, tones if not last else [tones[0]])
			var nxt: int = onsets[k + 1] if k + 1 < onsets.size() else STEPS
			var length := mini(nxt - s, 6) if not last else STEPS - s
			notes.append([bar, s, length, cur])
	return cur


## Lead pitches (MIDI, LEAD_LO..LEAD_HI) for a chord: chord tones plus pentatonic notes that aren't a
## semitone away from any chord tone.
static func _allowed(tones: Array, penta: Array, key: int) -> Array:
	var pcs := {}
	for t in tones:
		pcs[int(t) % 12] = true
	var ok := {}
	for p in pcs:
		ok[p] = true
	for iv in penta:
		var p: int = (key + int(iv)) % 12
		var clash := false
		for c in pcs:
			var d := absi(p - int(c)) % 12
			if (d == 1 or d == 11) and not pcs.has(p):
				clash = true
		if not clash:
			ok[p] = true
	var out := []
	for m in range(LEAD_LO, LEAD_HI + 1):
		if ok.has(m % 12):
			out.append(m)
	return out


static func _nearest(list: Array, m: int) -> int:
	var best := 0
	for i in list.size():
		if absi(int(list[i]) - m) < absi(int(list[best]) - m):
			best = i
	return best


## Nearest MIDI note (within the lead range) whose pitch class is one of `pcs`.
static func _snap(m: int, pcs: Array) -> int:
	var best := m
	var bd := 99
	for c in range(LEAD_LO, LEAD_HI + 1):
		for p in pcs:
			if c % 12 == int(p) % 12 and absi(c - m) < bd:
				bd = absi(c - m)
				best = c
	return best


static func _lead_note(f: float, held: float) -> PackedFloat32Array:
	var sec := held + 0.12
	var b := Synth.tone(Synth.SQUARE, f, sec, -1.0, 0.5, 0.12, 5.5)
	Synth.scale(b, 0.5)
	Synth.add(b, Synth.tone(Synth.TRI, f, sec, -1.0, 0.5, 0.12, 5.5), 0, 0.7)
	Synth.lp(b, 2400.0, -1.0, 0.8)
	return Synth.adsr(b, 0.008, 0.12, 0.55, held)


# --- shared by the station styles (StyleRpg, StyleSynthwave, StyleCityPop, StyleBossa) ---

## Chords per bar: an Array of segments [start step, root pitch class, chord tones (root + intervals)]. A prog
## entry is [interval above the key, chord name], or an Array of such entries to split the bar evenly
## (two chords = half a bar each). The prog repeats to fill the bars.
static func timeline(song: Dictionary, bars: int) -> Array:
	var prog: Array = song.prog
	var out := []
	for bar in bars:
		var e: Array = prog[bar % prog.size()]
		var segs := []
		if e[0] is Array:
			for j in e.size():
				segs.append(_seg(song, e[j], j * STEPS / e.size()))
		else:
			segs.append(_seg(song, e, 0))
		out.append(segs)
	return out


static func _seg(song: Dictionary, c: Array, start: int) -> Array:
	var root: int = (int(song.key) + int(c[0])) % 12
	var tones := []
	for iv in CHORDS[c[1]]:
		tones.append(root + int(iv))
	return [start, root, tones]


## The chord segment sounding at (bar, step).
static func chord_at(tl: Array, bar: int, s: int) -> Array:
	var segs: Array = tl[bar % tl.size()]
	var out: Array = segs[0]
	for sg in segs:
		if s >= int(sg[0]):
			out = sg
	return out


## Every chord segment as [bar, start step, length in steps, segment].
static func segments(tl: Array) -> Array:
	var out := []
	for bar in tl.size():
		var segs: Array = tl[bar]
		for j in segs.size():
			var st: int = segs[j][0]
			var en: int = segs[j + 1][0] if j + 1 < segs.size() else STEPS
			out.append([bar, st, en - st, segs[j]])
	return out


## Onset frame of 16th `s` in `bar`. swing pushes the off-16ths (s odd) late by swing/2 of a step; swing8 pushes
## the off-8ths (s % 4 == 2) by swing8 steps (0.67 = triplet swing, jazz).
static func at(bar: int, s: int, step: int, song: Dictionary) -> int:
	var o := (bar * STEPS + s) * step
	if s % 2 == 1:
		o += roundi(float(song.get("swing", 0.0)) * step * 0.5)
	elif s % 4 == 2:
		o += roundi(float(song.get("swing8", 0.0)) * step)
	return o


## Pitch classes the song's melodies use (song.scale, else the pentatonic of song.minor), in the song's key.
static func scale_pcs(song: Dictionary) -> Array:
	var name: String = song.get("scale", "minor_penta" if song.get("minor", false) else "penta")
	var out := []
	for iv in SCALES[name]:
		out.append((int(song.key) + int(iv)) % 12)
	return out


## Chord tones as MIDI notes folded into [lo, hi), sorted, no duplicates (a voicing).
static func voicing(tones: Array, lo: int, hi: int, drop_root := false) -> Array:
	var set := {}
	for i in tones.size():
		if drop_root and i == 0 and tones.size() >= 4:
			continue
		var m: int = lo + posmod(int(tones[i]) - lo, 12)
		if m >= hi:
			m -= 12
		set[m] = true
	var out := set.keys()
	out.sort()
	return out


## Bass interval for a groove entry: 0 root, 7 the chord's fifth (index 2), 12 octave, 19 fifth + octave,
## negative = chord tone index (-1 third, -3 seventh), other values = plain semitones.
static func bass_iv(seg: Array, iv: int) -> int:
	var tones: Array = seg[2]
	var root: int = seg[1]
	if iv == 7 or iv == 19:
		return int(tones[2]) - root + (12 if iv == 19 else 0)
	if iv < 0:
		return (int(tones[mini(-iv, tones.size() - 1)]) - root) % 12
	return iv


## Rhythm string -> [[step, length], ...]: x = note, - = hold the previous note, . = rest.
static func parse_rhythm(pat: String) -> Array:
	var out := []
	for s in pat.length():
		if pat[s] == "x":
			var l := 1
			while s + l < pat.length() and pat[s + l] == "-":
				l += 1
			out.append([s, l])
	return out


## Melody for the station styles: `form` letters are 2-bar units, and a repeated letter replays its rhythm and
## contour (re-fitted to the chords underneath), which is what makes a line sound like a tune. Downbeats snap to
## chord tones, every 4-bar phrase ends on a chord tone, the loop ends on the tonic (if the chord allows) and
## rings to the bar end. Returns [[bar, step, length, midi], ...]. rhythms = [sparse pool, busy pool].
static func melody(song: Dictionary, tl: Array, rng: RandomNumberGenerator, rhythms: Array, lo: int, hi: int) -> Array:
	var units := tl.size() / 2
	var form: String = song.get("form", "ABAC" if units <= 4 else "ABACABAD")
	var pcs := scale_pcs(song)
	var density: float = song.get("density", 0.5)
	var key: int = int(song.key) % 12
	var defs := {}
	var notes := []
	var cur := _snap_in(lo + (hi - lo) / 2, [key], lo, hi)
	for u in units:
		var letter := form[u % form.length()]
		if not defs.has(letter):
			var r0 := _pick_rhythm(rng, rhythms, density)
			defs[letter] = {"rh": [r0, _pick_rhythm(rng, rhythms, density * 0.8)], "moves": _contour(rng, 32),
				"start": cur}
		var d: Dictionary = defs[letter]
		cur = d.start
		var phrase_end := u % 2 == 1 or u == units - 1
		var ending := u == units - 1
		var mi := 0
		for j in 2:
			var bar := u * 2 + j
			var evs := parse_rhythm(d.rh[j])
			for k in evs.size():
				var s: int = evs[k][0]
				var length: int = evs[k][1]
				var seg := chord_at(tl, bar, s)
				var allowed := _allowed_pcs(seg[2], pcs, lo, hi)
				var idx := _nearest(allowed, cur)
				var mv: int = d.moves[mi % d.moves.size()]
				mi += 1
				var ni := idx + mv
				if ni < 0 or ni >= allowed.size():
					ni = idx - mv                     # bounce off the edge of the range
					mv = -mv
				var prev := cur
				cur = allowed[clampi(ni, 0, allowed.size() - 1)]
				if s % 4 == 0:                        # beats land on chord tones, still moving the way the line goes
					cur = _snap_toward(cur, prev, mv, seg[2], lo, hi)
				if j == 1 and k == evs.size() - 1 and phrase_end:
					var chord_pcs := []
					for t in seg[2]:
						chord_pcs.append(int(t) % 12)
					var home: Array = [key] if ending and chord_pcs.has(key) else [seg[1], seg[2][1]]
					cur = _snap_in(cur, home, lo, hi)
					length = STEPS - s
				notes.append([bar, s, length, cur])
	return notes


## Melodic contour for the station styles (in allowed-note steps): mostly steps, some skips (arpeggio-like
## thirds), the odd bigger leap, rarely a repeat; after a leap the line turns back with a step (singable).
## Runs of the same direction are capped at 4 so phrases arch instead of climbing off the range.
static func _contour(rng: RandomNumberGenerator, count: int) -> Array:
	var out := []
	var dir := 1 if rng.randf() < 0.5 else -1
	var run := 0
	var last := 0
	for i in count:
		var m: int
		if absi(last) >= 2:
			m = -signi(last)
		else:
			var r := rng.randf()
			var size := 1 if r < 0.55 else (2 if r < 0.85 else (3 if r < 0.92 else 0))
			if rng.randf() < 0.3 or run >= 4:
				dir = -dir
				run = 0
			m = size * dir
		run += 1
		out.append(m)
		last = m
	return out


## On a beat: the chord tone nearest `m`, but if that would just repeat `prev` while the line is moving, the
## next chord tone in the line's direction instead.
static func _snap_toward(m: int, prev: int, mv: int, tones: Array, lo: int, hi: int) -> int:
	var s := _snap_in(m, tones, lo, hi)
	if s != prev or mv == 0:
		return s
	var pcs := {}
	for t in tones:
		pcs[int(t) % 12] = true
	var c := prev + signi(mv)
	while c >= lo and c <= hi:
		if pcs.has(c % 12):
			return c
		c += signi(mv)
	return s


static func _pick_rhythm(rng: RandomNumberGenerator, rhythms: Array, density: float) -> String:
	var pool: Array = rhythms[1] if rng.randf() < density else rhythms[0]
	return pool[rng.randi() % pool.size()]


## MIDI notes in [lo, hi] for a chord: chord tones plus scale notes that aren't a semitone off a chord tone.
static func _allowed_pcs(tones: Array, pcs: Array, lo: int, hi: int) -> Array:
	var chord := {}
	for t in tones:
		chord[int(t) % 12] = true
	var ok := chord.duplicate()
	for p in pcs:
		var clash := false
		for c in chord:
			var d := absi(int(p) - int(c)) % 12
			if (d == 1 or d == 11) and not chord.has(p):
				clash = true
		if not clash:
			ok[p] = true
	var out := []
	for m in range(lo, hi + 1):
		if ok.has(m % 12):
			out.append(m)
	return out


## Nearest MIDI note in [lo, hi] whose pitch class is one of pcs.
static func _snap_in(m: int, pcs: Array, lo: int, hi: int) -> int:
	var best := m
	var bd := 99
	for c in range(lo, hi + 1):
		for p in pcs:
			if c % 12 == int(p) % 12 and absi(c - m) < bd:
				bd = absi(c - m)
				best = c
	return best


## Run a whole-buffer effect (filter sweep, echo) on a loop without a seam: two copies back to back go through
## it and the second is kept, so the effect's state (filter memory, echo tail) wraps around like the loop does.
## LFO effects need a whole number of cycles per loop.
static func seamless(b: PackedFloat32Array, fx: Callable) -> PackedFloat32Array:
	var n := b.size()
	var c := b.duplicate()
	c.append_array(b)
	fx.call(c)
	for i in n:
		b[i] = c[n + i]
	return b


## Gate envelope for drum hits shaped as perc() but cut hard at `gate` s (the 80s gated reverb).
static func gate(b: PackedFloat32Array, gate_sec: float, fall := 0.012) -> PackedFloat32Array:
	var g := Synth.frames(gate_sec)
	var f := Synth.frames(fall)
	for i in b.size():
		if i >= g + f:
			b[i] = 0.0
		elif i >= g:
			b[i] *= 1.0 - float(i - g) / f
	return b
