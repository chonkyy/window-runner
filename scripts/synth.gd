class_name Synth
extends RefCounted
## Tiny offline synthesizer (Phase 4 audio): every sound is built as a mono float buffer at RATE Hz and baked
## into a 16-bit AudioStreamWAV by to_wav(). Static and stateless (noise takes an rng), so SoundBank and Music
## can render on worker threads. Buffers are PackedFloat32Array (passed by reference): the helpers change the
## buffer in place AND return it, so calls chain: `Synth.perc(Synth.lp(Synth.noise(0.2, r), 900.0))`.

const RATE := 22050
enum { SINE, SQUARE, SAW, TRI, NOISE }
enum { LP, BP, HP }
const LN2_12 := 0.0577623                 ## ln(2) / 12: vibrato depth in semitones -> frequency ratio (small-angle)


static func frames(sec: float) -> int:
	return maxi(roundi(sec * RATE), 1)


static func empty(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(frames(sec))
	b.fill(0.0)
	return b


static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## Oscillator. Exponential slide f0 -> f1 over the buffer, vibrato `vib` semitones at vib_hz (vib_in > 0: the
## vibrato waits that many seconds, then fades in over 0.15 s, like a singer or a chip lead). SAW/SQUARE are
## band-limited (polyBLEP). NOISE is sample-and-hold noise clocked at f0 (>= RATE: white).
static func tone(wave: int, f0: float, sec: float, f1 := -1.0, duty := 0.5, vib := 0.0, vib_hz := 5.0,
		rng: RandomNumberGenerator = null, vib_in := 0.0) -> PackedFloat32Array:
	var n := frames(sec)
	var b := PackedFloat32Array()
	b.resize(n)
	if f1 <= 0.0:
		f1 = f0
	var step := pow(f1 / f0, 1.0 / n)
	var f := f0
	var ph := 0.0
	var hold := 0.0
	var vk := TAU * vib_hz / RATE
	var vd := vib * LN2_12
	var v_in := float(frames(vib_in)) if vib_in > 0.0 else -1.0
	var v_ramp := 1.0 / (0.15 * RATE)
	for i in n:
		var fi := f
		if vd != 0.0:
			var depth := vd if v_in < 0.0 else vd * clampf((i - v_in) * v_ramp, 0.0, 1.0)
			fi *= 1.0 + depth * sin(vk * i)
		var dt := fi / RATE
		ph += dt
		if ph >= 1.0:
			ph -= floorf(ph)
			if wave == NOISE:
				hold = rng.randf_range(-1.0, 1.0)
		var v := 0.0
		if wave == SINE:
			v = sin(TAU * ph)
		elif wave == TRI:
			v = 4.0 * absf(ph - 0.5) - 1.0
		elif wave == SAW:
			v = 2.0 * ph - 1.0 - _blep(ph, dt)
		elif wave == SQUARE:
			v = (1.0 if ph < duty else -1.0) + _blep(ph, dt) - _blep(fposmod(ph + 1.0 - duty, 1.0), dt)
		else:
			v = rng.randf_range(-1.0, 1.0) if f0 >= RATE else hold
		b[i] = v
		f *= step
	return b


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


## White noise (hz = 0) or sample-and-hold noise at hz.
static func noise(sec: float, rng: RandomNumberGenerator, hz := 0.0) -> PackedFloat32Array:
	return tone(NOISE, hz if hz > 0.0 else float(RATE), sec, -1.0, 0.5, 0.0, 5.0, rng)


## Brown(ish) noise: leaky-integrated white noise, normalised. Rumbles, distant traffic.
static func brown(sec: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := noise(sec, rng)
	var y := 0.0
	for i in b.size():
		y = y * 0.985 + b[i] * 0.12
		b[i] = y
	return norm(b)


## Sparse clicks (vinyl crackle, electric sparks): `rate` per second, fading by (1-u)^fall over the buffer.
static func clicks(sec: float, rng: RandomNumberGenerator, rate: float, fall := 0.0) -> PackedFloat32Array:
	var b := empty(sec)
	var n := b.size()
	var p := rate / RATE
	var i := 0
	while i < n - 4:
		var u := float(i) / n
		if rng.randf() < p * pow(1.0 - u, fall):
			var a := rng.randf_range(0.3, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			b[i] = a
			b[i + 1] = -a * 0.6
			b[i + 2] = a * 0.3
			i += 3
		i += 1
	return b


## Percussive envelope: linear attack, then (1-u)^curve decay to silence at the end of the buffer.
static func perc(b: PackedFloat32Array, attack := 0.004, curve := 2.0) -> PackedFloat32Array:
	var n := b.size()
	var na := maxi(frames(attack), 1)
	for i in n:
		var a := minf(float(i) / na, 1.0)
		var u := float(maxi(i - na, 0)) / maxi(n - na, 1)
		b[i] *= a * pow(1.0 - u, curve)
	return b


## Natural ring: attack, then exponential decay with time constant tau (seconds).
static func decay(b: PackedFloat32Array, attack: float, tau: float) -> PackedFloat32Array:
	var na := maxi(frames(attack), 1)
	var k := exp(-1.0 / (tau * RATE))
	var g := 1.0
	for i in b.size():
		if i < na:
			b[i] *= float(i) / na
		else:
			g *= k
			b[i] *= g
	return b


## Note envelope: attack a, decay d to sustain level s while held, then release over the rest of the buffer.
static func adsr(b: PackedFloat32Array, a: float, d: float, s: float, held: float) -> PackedFloat32Array:
	var n := b.size()
	var na := maxi(frames(a), 1)
	var nd := maxi(frames(d), 1)
	var nh := mini(frames(held), n)
	var level := 0.0
	var rel_from := 0.0
	for i in n:
		if i < nh:
			if i < na:
				level = float(i) / na
			elif i < na + nd:
				level = lerpf(1.0, s, float(i - na) / nd)
			else:
				level = s
			rel_from = level
		else:
			var u := float(i - nh) / maxi(n - nh, 1)
			level = rel_from * (1.0 - u) * (1.0 - u)
		b[i] *= level
	return b


## Rise to a peak at fraction `peak` of the buffer, then fall (whooshes, swells).
static func swell(b: PackedFloat32Array, peak := 0.7, cin := 2.0, cout := 2.0) -> PackedFloat32Array:
	var n := b.size()
	for i in n:
		var u := float(i) / n
		b[i] *= pow(u / peak, cin) if u < peak else pow((1.0 - u) / (1.0 - peak), cout)
	return b


## Amplitude modulation: sine (duty < 0) or pulse gate at hz; depth 1 = full chop.
static func am(b: PackedFloat32Array, hz: float, depth: float, duty := -1.0) -> PackedFloat32Array:
	for i in b.size():
		var ph := fmod(hz * i / RATE, 1.0)
		var m := (0.5 - 0.5 * cos(TAU * ph)) if duty < 0.0 else (1.0 if ph < duty else 0.0)
		b[i] *= 1.0 - depth + depth * m
	return b


## Short linear fades at both ends (de-click).
static func fades(b: PackedFloat32Array, fin := 0.003, fout := 0.01) -> PackedFloat32Array:
	var n := b.size()
	var a := mini(frames(fin), n)
	var z := mini(frames(fout), n)
	for i in a:
		b[i] *= float(i) / a
	for i in z:
		b[n - 1 - i] *= float(i) / z
	return b


## TPT state-variable filter (stable at any cutoff). Cutoff slides exponentially fc0 -> fc1. BP has unity peak.
static func filt(b: PackedFloat32Array, mode: int, fc0: float, fc1 := -1.0, q := 0.707) -> PackedFloat32Array:
	if fc1 <= 0.0:
		fc1 = fc0
	var n := b.size()
	var k := 1.0 / q
	var ratio := fc1 / fc0
	var ic1 := 0.0
	var ic2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	for i in n:
		if i % 16 == 0:
			var fc := minf(fc0 * pow(ratio, float(i) / n), RATE * 0.45)
			var g := tan(PI * fc / RATE)
			a1 = 1.0 / (1.0 + g * (g + k))
			a2 = g * a1
			a3 = g * a2
		var x := b[i]
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		if mode == LP:
			b[i] = v2
		elif mode == BP:
			b[i] = v1 * k
		else:
			b[i] = x - k * v1 - v2
	return b


static func lp(b: PackedFloat32Array, fc0: float, fc1 := -1.0, q := 0.707) -> PackedFloat32Array:
	return filt(b, LP, fc0, fc1, q)


static func bp(b: PackedFloat32Array, fc0: float, fc1 := -1.0, q := 1.0) -> PackedFloat32Array:
	return filt(b, BP, fc0, fc1, q)


static func hp(b: PackedFloat32Array, fc0: float, fc1 := -1.0, q := 0.707) -> PackedFloat32Array:
	return filt(b, HP, fc0, fc1, q)


## Band-pass with a periodic (sine LFO) cutoff between lo and hi; lfo_hz * buffer length should be whole cycles
## for loops.
static func bp_lfo(b: PackedFloat32Array, lo: float, hi: float, lfo_hz: float, q := 0.8) -> PackedFloat32Array:
	return filt_lfo(b, BP, lo, hi, lfo_hz, q)


## Low-pass with a sine-LFO cutoff between lo and hi (filter sweeps on pads). Same rule as bp_lfo for loops.
static func lp_lfo(b: PackedFloat32Array, lo: float, hi: float, lfo_hz: float, q := 0.707) -> PackedFloat32Array:
	return filt_lfo(b, LP, lo, hi, lfo_hz, q)


## Two-operator FM: a sine carrier at f phase-modulated by a sine at f * ratio, the index falling from index0
## towards index1 with time constant tau (s). ratio 1 = electric piano body, ratio ~14 = its bell-like tine.
static func fm(f: float, sec: float, ratio: float, index0: float, index1 := 0.0, tau := 0.3) -> PackedFloat32Array:
	var n := frames(sec)
	var b := PackedFloat32Array()
	b.resize(n)
	var wc := TAU * f / RATE
	var wm := wc * ratio
	var k := exp(-1.0 / (maxf(tau, 0.001) * RATE))
	var idx := index0 - index1
	for i in n:
		b[i] = sin(wc * i + (index1 + idx) * sin(wm * i))
		idx *= k
	return b


static func filt_lfo(b: PackedFloat32Array, mode: int, lo: float, hi: float, lfo_hz: float, q := 0.8) -> PackedFloat32Array:
	var n := b.size()
	var k := 1.0 / q
	var ic1 := 0.0
	var ic2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var a3 := 0.0
	for i in n:
		if i % 16 == 0:
			var m := 0.5 - 0.5 * cos(TAU * lfo_hz * i / RATE)
			var g := tan(PI * lo * pow(hi / lo, m) / RATE)
			a1 = 1.0 / (1.0 + g * (g + k))
			a2 = g * a1
			a3 = g * a2
		var x := b[i]
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		if mode == BP:
			b[i] = v1 * k
		elif mode == LP:
			b[i] = v2
		else:
			b[i] = x - k * v1 - v2
	return b


## Karplus-Strong plucked string (the power line twang, soft bass plucks). bright 0..1 colours the excitation.
static func pluck(f: float, sec: float, rng: RandomNumberGenerator, damp := 0.996, bright := 0.5) -> PackedFloat32Array:
	var n := frames(sec)
	var p := maxi(roundi(RATE / f), 2)
	var ring := PackedFloat32Array()
	ring.resize(p)
	var y := 0.0
	for i in p:
		y += bright * (rng.randf_range(-1.0, 1.0) - y)
		ring[i] = y
	var b := PackedFloat32Array()
	b.resize(n)
	var idx := 0
	for i in n:
		var nxt := idx + 1
		if nxt >= p:
			nxt = 0
		var v := ring[idx]
		b[i] = v
		ring[idx] = damp * 0.5 * (v + ring[nxt])
		idx = nxt
	return norm(b)


## Add src into dst from frame `at` with gain. Grows dst to fit, or (wrap) folds the overflow back to the start
## so a fixed-length loop stays seamless.
static func add(dst: PackedFloat32Array, src: PackedFloat32Array, at := 0, gain := 1.0, wrap := false) -> PackedFloat32Array:
	var n := dst.size()
	var m := src.size()
	if wrap:
		at = posmod(at, n)
		for i in m:
			var j := at + i
			while j >= n:
				j -= n
			dst[j] += src[i] * gain
		return dst
	if at + m > n:
		dst.resize(at + m)
		for i in range(n, at + m):
			dst[i] = 0.0
	for i in m:
		dst[at + i] += src[i] * gain
	return dst


## Add src at a time offset in seconds (grows dst).
static func add_at(dst: PackedFloat32Array, src: PackedFloat32Array, sec: float, gain := 1.0) -> PackedFloat32Array:
	return add(dst, src, frames(sec) if sec > 0.0 else 0, gain)


static func scale(b: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] *= g
	return b


## Soft saturation (tanh), output peak kept near the input's.
static func drive(b: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var t := tanh(amount)
	for i in b.size():
		b[i] = tanh(b[i] * amount) / t
	return b


## Lo-fi: hold every `hold` samples and quantise to `bits`.
static func crush(b: PackedFloat32Array, hold := 2, bits := 8) -> PackedFloat32Array:
	var q := pow(2.0, bits - 1)
	var v := 0.0
	for i in b.size():
		if i % hold == 0:
			v = roundf(b[i] * q) / q
		b[i] = v
	return b


## Feedback echo; grows the buffer by `tail` seconds.
static func echo(b: PackedFloat32Array, delay: float, fb := 0.35, wet := 0.4, tail := 0.4) -> PackedFloat32Array:
	var n := b.size()
	var total := n + frames(tail)
	b.resize(total)
	for i in range(n, total):
		b[i] = 0.0
	var d := frames(delay)
	var line := PackedFloat32Array()
	line.resize(d)
	line.fill(0.0)
	var idx := 0
	for i in total:
		var dl := line[idx]
		line[idx] = b[i] + dl * fb
		b[i] += dl * wet
		idx = (idx + 1) % d
	return b


static func peak(b: PackedFloat32Array) -> float:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	return m


static func norm(b: PackedFloat32Array, to := 1.0) -> PackedFloat32Array:
	var m := peak(b)
	if m > 0.000001:
		scale(b, to / m)
	return b


## Bake to a 16-bit mono AudioStreamWAV. normalize: peak -> level. loop: LOOP_FORWARD over the whole stream;
## xfade > 0 cross-fades the last xfade seconds into the start (the result is that much shorter) so noisy
## loops have no seam. Render tonal loops as whole cycles of (length - xfade).
static func to_wav(b: PackedFloat32Array, level := 0.8, loop := false, xfade := 0.0, normalize := true) -> AudioStreamWAV:
	if loop and xfade > 0.0:
		var x := mini(frames(xfade), b.size() >> 1)
		var n0 := b.size() - x
		for i in x:
			var u := float(i) / x
			b[i] = b[i] * u + b[n0 + i] * (1.0 - u)
		b.resize(n0)
	if normalize:
		norm(b, level)
	var n := b.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, clampi(roundi(b[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
