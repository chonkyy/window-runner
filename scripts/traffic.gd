class_name Traffic
extends Node2D
## Spawns and moves cars and pedestrians on the street. Everything enters from the right edge and
## slides left relative to the camera. Spawns are checked against WireGenerator.street_hazard_ok at the
## predicted meeting point so wire ends/returns always have a clear window.

@export var spawn_ahead := 1500.0          ## px right of camera left where things spawn
@export var gap_min := 700.0               ## camera travel between spawn attempts
@export var gap_max := 1500.0
@export var density_per_meter := 0.0002    ## spawn gaps shrink by this fraction per meter
@export var min_density := 0.55            ## floor on the gap multiplier
@export var min_separation := 460.0        ## min distance between predicted meeting points
@export var chain_chance := 0.55           ## same-direction hoppable chain (else oncoming car)
@export var person_gap_min := 350.0       ## camera travel between person spawn attempts (own stream)
@export var person_gap_max := 800.0
@export var person_separation := 300.0    ## min spacing from other hazards' meeting points
@export_group("People weights")
@export var w_walker := 0.2
@export var w_group := 0.15                ## 2-3 walkers together
@export var w_child := 0.08
@export var w_jogger := 0.17
@export var w_cyclist := 0.22
@export var w_moto := 0.18                 ## fast, oncoming
@export var repeat_damp := 0.4             ## weight factor for repeating the previous person kind
@export_group("")
@export var car_vx_min := 120.0            ## same-direction cars (slower than the camera)
@export var car_vx_max := 300.0
@export var oncoming_vx_min := 250.0
@export var oncoming_vx_max := 450.0
@export var hop_flight := 0.45             ## seconds of free flight a chain gap is sized for
@export_group("Big vehicles")
@export var big_chance := 0.16             ## share of car spawn attempts that are a school bus / freight truck
@export var bus_share := 0.45              ## of big vehicles (school buses are rare at night)
@export var bus_vx_min := 90.0             ## same direction, slow: a long platform to run along
@export var bus_vx_max := 170.0
@export var truck_vx_min := 160.0          ## same direction
@export var truck_vx_max := 300.0
@export var truck_oncoming := 0.4          ## share of trucks coming the other way
@export var truck_oncoming_vx_min := 260.0
@export var truck_oncoming_vx_max := 400.0
@export_group("")

var gen: WireGenerator
var seed_value := 4242

var _rng := RandomNumberGenerator.new()
var _rain_rng := RandomNumberGenerator.new()   ## rain thinning only (never touches _rng)
var _next_x := 0.0
var _next_person_x := 0.0
var _meets: Array[float] = []
var _last_person := -1                     ## index into the person weights of the previous spawn

const LANE_GAP := 40.0                     ## min bumper gap between same-direction vehicles

const CAR_COLORS := [Color(0.82, 0.22, 0.2), Color(0.2, 0.45, 0.8), Color(0.9, 0.75, 0.2),
	Color(0.25, 0.65, 0.4), Color(0.85, 0.85, 0.88), Color(0.55, 0.3, 0.7)]


func _ready() -> void:
	_rng.seed = seed_value
	_rain_rng.seed = seed_value ^ 0x7f4a7c15
	_next_x = 1400.0
	_next_person_x = 1100.0


func update(delta: float, cam_x: float, scroll_speed: float, runner_x: float, distance_m: float) -> void:
	_keep_distance()
	for c in get_tree().get_nodes_in_group("cars"):
		var car := c as Car
		car.position.x += car.vx * delta
		if car.position.x + car.length < cam_x - 300.0:
			car.queue_free()
	for p in get_tree().get_nodes_in_group("peds"):
		var ped := p as Pedestrian
		ped.position.x += ped.vx * delta
		if ped.position.x < cam_x - 300.0:
			ped.queue_free()

	while cam_x >= _next_x:
		_spawn_attempt(cam_x, scroll_speed, runner_x, distance_m)
	while cam_x >= _next_person_x:
		_next_person_x += _rng.randf_range(person_gap_min, person_gap_max) / TimeOfDay.p().traffic
		_meets = _meets.filter(func(m: float) -> bool: return m > runner_x - 1500.0)
		_spawn_person(cam_x + _ahead(), scroll_speed, runner_x, _rained_off(cam_x + _ahead()))


func _spawn_attempt(cam_x: float, s: float, runner_x: float, distance_m: float) -> void:
	var dens: float = maxf(1.0 - density_per_meter * distance_m, min_density) / TimeOfDay.p().traffic
	_next_x += _rng.randf_range(gap_min, gap_max) * dens
	var sx := cam_x + _ahead()
	_meets = _meets.filter(func(m: float) -> bool: return m > runner_x - 1500.0)

	if _rng.randf() < big_chance:
		_spawn_big(sx, s, runner_x)
	elif _rng.randf() < chain_chance:
		var vx := _lane_vx(sx, 165.0, _rng.randf_range(car_vx_min, car_vx_max), cam_x, s)
		var count := _rng.randi_range(2, 3)
		var closing := s - vx
		var gap := clampf(closing * hop_flight, 90.0, 380.0)
		var ok := not is_nan(vx) and _meet_ok(_meet_x(sx, vx, runner_x, s))
		var x := sx
		for k in count:
			var car_len := _rng.randf_range(135.0, 165.0)
			if not (ok and gen.street_hazard_ok(_meet_x(x, vx, runner_x, s))):
				break
			if _lane_vx(x, car_len, vx, cam_x, s) != vx:       # would overlap / need another speed
				break
			_spawn_car(x, vx, car_len)
			x += car_len + gap
	else:
		var vx := -_rng.randf_range(oncoming_vx_min, oncoming_vx_max)
		if _meet_ok(_meet_x(sx, vx, runner_x, s)):
			_spawn_car(sx, vx, _rng.randf_range(135.0, 165.0))


## Predicted world x where an object spawned at sx with velocity vx meets the runner.
func _meet_x(sx: float, vx: float, runner_x: float, s: float) -> float:
	var closing := s - vx
	if closing < 1.0:
		return sx
	return runner_x + s * (sx - runner_x) / closing


func _meet_ok(m: float, sep: float = -1.0) -> bool:
	if sep < 0.0:
		sep = min_separation
	if not gen.street_hazard_ok(m):
		return false
	for o in _meets:
		if absf(o - m) < sep:
			return false
	_meets.append(m)
	return true


## School bus (same direction, slow) or freight truck (either direction). Long, so the whole stretch the
## runner spends alongside it must clear the wire windows and other hazards, not just its rear edge.
func _spawn_big(sx: float, s: float, runner_x: float) -> void:
	var night := TimeOfDay.phase() == TimeOfDay.Phase.NIGHT
	var bus := _rng.randf() < (bus_share * 0.2 if night else bus_share)
	var vx: float
	var blen: float
	if bus:
		vx = _rng.randf_range(bus_vx_min, bus_vx_max)
		blen = PixelArt.snap(_rng.randf_range(290.0, 320.0))
	else:
		blen = PixelArt.snap(_rng.randf_range(350.0, 400.0))
		if _rng.randf() < truck_oncoming:
			vx = -_rng.randf_range(truck_oncoming_vx_min, truck_oncoming_vx_max)
		else:
			vx = _rng.randf_range(truck_vx_min, truck_vx_max)
	if vx > 0.0:
		vx = _lane_vx(sx, blen, vx, sx - _ahead(), s)
		if is_nan(vx):
			return
	if not _range_ok(_meet_x(sx, vx, runner_x, s), _meet_x(sx + blen, vx, runner_x, s), min_separation):
		return
	_spawn_car(sx, vx, blen, Car.Model.BUS if bus else Car.Model.TRUCK)


## Like _meet_ok for a stretch [m0, m1] of meeting points: every point clears street_hazard_ok and no
## other meeting point lies within sep of it.
func _range_ok(m0: float, m1: float, sep: float) -> bool:
	var a := minf(m0, m1)
	var b := maxf(m0, m1)
	var x := a
	while true:
		if not gen.street_hazard_ok(x):
			return false
		if x >= b:
			break
		x = minf(x + 150.0, b)
	for o in _meets:
		if o > a - sep and o < b + sep:
			return false
	_meets.append(a)
	_meets.append(b)
	return true


## Speed for a same-direction vehicle spanning [x, x + len] so it never runs into (or is run into by) another
## same-direction vehicle while they're on screen: a car it would catch caps its speed, a faster car behind
## that would catch it raises it. NAN if it would start overlapping one, or no speed fits.
func _lane_vx(x: float, len: float, vx: float, cam_x: float, s: float) -> float:
	var lo := -INF
	var hi := INF
	var exit_x := cam_x - 300.0
	for c in get_tree().get_nodes_in_group("cars"):
		var car := c as Car
		if car.vx <= 0.0 or car.is_queued_for_deletion():
			continue
		var ahead := car.position.x >= x
		var gap := car.position.x - (x + len) if ahead else x - (car.position.x + car.length)
		if gap < LANE_GAP:
			return NAN
		var back_vx := vx if ahead else car.vx         # the one behind catches up if it's faster
		var front_vx := car.vx if ahead else vx
		if back_vx <= front_vx:
			continue
		# both scroll off the left edge at roughly the camera speed; only a catch-up before that matters
		var front_x := car.position.x + car.length if ahead else x + len
		var t_exit := (front_x - exit_x) / maxf(s - front_vx, 1.0)
		var t_catch := (gap - LANE_GAP) / (back_vx - front_vx)
		if t_catch > t_exit:
			continue
		if ahead:
			hi = minf(hi, car.vx)
		else:
			lo = maxf(lo, car.vx)
	if lo > hi:
		return NAN
	return clampf(vx, lo, hi)


## Runtime safety net: a same-direction vehicle that gets too close to the one ahead slows to its speed.
func _keep_distance() -> void:
	var lane: Array = []
	for c in get_tree().get_nodes_in_group("cars"):
		if (c as Car).vx > 0.0:
			lane.append(c)
	lane.sort_custom(func(a: Car, b: Car) -> bool: return a.position.x < b.position.x)
	for i in range(lane.size() - 1):
		var back := lane[i] as Car
		var front := lane[i + 1] as Car
		if back.vx > front.vx and front.position.x - (back.position.x + back.length) < LANE_GAP:
			back.vx = front.vx


func _spawn_car(x: float, vx: float, car_len: float, model := -1) -> void:
	var car := Car.new()
	car.position = Vector2(x, gen.floor_y)
	car.vx = vx
	car.length = car_len
	car.color = CAR_COLORS[_rng.randi() % CAR_COLORS.size()]
	if model >= 0:
		car.model = model as Car.Model
		car.preset = true
	car.z_index = 1
	add_child(car)


## Rain keeps people indoors. A rained-off spawn still runs
## the whole spawn (same _rng draws, same meeting-point reservation) and just isn't added, so the cars and
## the rest of the street are identical to a dry round with the same seed. Own rng for the roll.
func _rained_off(sx: float) -> bool:
	if not Weather.active():
		return false
	var keep := 1.0 / (2.4 if Weather.heavy() else 1.6)
	return _rain_rng.randf() > keep


func _spawn_person(sx: float, s: float, runner_x: float, rained_off := false) -> void:
	# 0 walker, 1 group, 2 child, 3 jogger, 4 cyclist, 5 moto; the last pick is damped so it rarely repeats
	var weights := [w_walker, w_group, w_child, w_jogger, w_cyclist, w_moto]
	if _last_person >= 0:
		weights[_last_person] *= repeat_damp
	var total := 0.0
	for w in weights:
		total += w
	var pick := _rng.randf() * total
	var choice := weights.size() - 1
	for k in weights.size():
		pick -= weights[k]
		if pick < 0.0:
			choice = k
			break
	_last_person = choice
	var kind := Pedestrian.Kind.WALKER
	var count := 1
	var vx := 0.0
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	match choice:
		0:
			vx = _rng.randf_range(25.0, 60.0) * dir
		1:
			vx = _rng.randf_range(25.0, 55.0) * dir
			count = _rng.randi_range(2, 3)
		2:
			kind = Pedestrian.Kind.CHILD
			vx = _rng.randf_range(35.0, 70.0) * dir
		3:
			kind = Pedestrian.Kind.JOGGER
			vx = _rng.randf_range(110.0, 180.0) * dir
		4:
			kind = Pedestrian.Kind.CYCLIST
			vx = _rng.randf_range(150.0, 280.0) * dir
		_:
			kind = Pedestrian.Kind.MOTO
			vx = -_rng.randf_range(480.0, 700.0)                  # oncoming, fast
	if not _meet_ok(_meet_x(sx, vx, runner_x, s), person_separation):
		return
	for k in count:
		var ped := Pedestrian.new()
		ped.setup(kind, _rng)
		ped.vx = vx
		var lift := Street.PED_LIFT if ped.on_sidewalk() else 0.0
		ped.position = Vector2(sx + k * _rng.randf_range(38.0, 54.0), gen.floor_y - lift)
		ped.z_index = 0 if ped.on_sidewalk() else 1               # vehicles pass in front of people on foot
		if rained_off:
			ped.free()
			continue
		add_child(ped)


## Spawn x right of the camera's left edge: further out on wide screens so nothing pops in on screen.
func _ahead() -> float:
	return spawn_ahead + View.extra()
