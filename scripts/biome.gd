class_name Biome
extends RefCounted
## Scenery zones along the run (purely visual + ambience, never gameplay): CITY skyline and SUBURB houses.
## Each round rolls its own schedule from the round seed (Game._ready -> setup): zone 0 (random biome) covers
## the lead-in/menu and the first FIRST_M metres, then the other biome every ZONE_M metres (never the same
## twice in a row, so with two biomes they alternate). Around each boundary the two biomes cross-fade over BLEND_M
## metres (Backdrop fades whole layer sets, Greenery dithers per prop). `-- --biome=N` forces one biome.

enum Kind { CITY, SUBURB }
const NAMES := ["CITY", "SUBURB"]
const WEIGHTS := [1.0, 1.0]               ## indexed by Kind
const FIRST_M := Vector2(450.0, 800.0)
const ZONE_M := Vector2(600.0, 1100.0)
const BLEND_M := 60.0                     ## cross-fade length around a boundary
const PX_PER_M := 50.0                    ## = Game.PX_PER_METER
const ZONES := 240                        ## ~200 km of schedule, far more than any run

static var force := -1                    ## `-- --biome=N`
static var _args_read := false
static var _starts := PackedFloat64Array()   ## world x where zone i begins (zone 0: -INF)
static var _kinds := PackedInt32Array()


static func setup(seed_value: int) -> void:
	_read_args()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x68e31da4
	_starts.clear()
	_kinds.clear()
	var x := -INF
	var last := -1
	for i in ZONES:
		var k := force if force >= 0 else _pick(rng, last)
		_starts.append(x)
		_kinds.append(k)
		last = k
		var len_m := rng.randf_range(FIRST_M.x, FIRST_M.y) if i == 0 else rng.randf_range(ZONE_M.x, ZONE_M.y)
		x = (0.0 if i == 0 else x) + len_m * PX_PER_M


static func _pick(rng: RandomNumberGenerator, last: int) -> int:
	var total := 0.0
	for k in WEIGHTS.size():
		total += 0.0 if k == last else WEIGHTS[k]
	var r := rng.randf() * total
	for k in WEIGHTS.size():
		if k == last:
			continue
		r -= WEIGHTS[k]
		if r < 0.0:
			return k
	return 0 if last != 0 else 1


static func _zone(x: float) -> int:
	if _starts.is_empty():
		return -1
	var lo := 0
	var hi := _starts.size() - 1
	while lo < hi:                               # last zone whose start <= x
		var mid := (lo + hi + 1) >> 1
		if _starts[mid] <= x:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Biome at world x (CITY before setup).
static func kind_at(x: float) -> int:
	var i := _zone(x)
	return Kind.CITY if i < 0 else _kinds[i]


## Cross-fade at world x: Vector3(from kind, to kind, t 0..1). Away from a boundary from == to and t = 0.
static func blend_at(x: float) -> Vector3:
	var i := _zone(x)
	if i < 0:
		return Vector3(Kind.CITY, Kind.CITY, 0.0)
	var half := BLEND_M * PX_PER_M * 0.5
	if i + 1 < _starts.size() and x > _starts[i + 1] - half:
		return Vector3(_kinds[i], _kinds[i + 1], (x - (_starts[i + 1] - half)) / (2.0 * half))
	if i > 0 and x < _starts[i] + half:
		return Vector3(_kinds[i - 1], _kinds[i], (x - (_starts[i] - half)) / (2.0 * half))
	return Vector3(_kinds[i], _kinds[i], 0.0)


## Weighted value per biome at x (cross-faded), e.g. ambience levels: vals indexed by Kind.
static func mix(x: float, vals: Array) -> float:
	var b := blend_at(x)
	return lerpf(float(vals[int(b.x)]), float(vals[int(b.y)]), b.z)


## Deterministic per-prop pick inside a cross-fade: the biome a thing at x (with its own hash h) belongs to.
static func dither_at(x: float, h: int) -> int:
	var b := blend_at(x)
	return int(b.y) if float(absi(h) % 1000) / 1000.0 < b.z else int(b.x)


## "CITY 0m, SUBURB 612m, ..." for the first few zones (printed with the seed).
static func describe(n := 5) -> String:
	var parts := []
	for i in mini(n, _kinds.size()):
		var at := 0.0 if i == 0 else _starts[i] / PX_PER_M
		parts.append("%s %dm" % [NAMES[_kinds[i]], int(at)])
	return ", ".join(parts)


static func _read_args() -> void:
	if _args_read:
		return
	_args_read = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--biome="):
			force = clampi(int(a.trim_prefix("--biome=")), 0, NAMES.size() - 1)
