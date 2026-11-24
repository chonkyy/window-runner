extends Node2D
## Root of the prototype: owns scroll speed, camera, street, traffic, score, HUD, game over and restart.

@export var base_speed := 420.0
@export var speed_grace_m := 200.0        ## no speed-up for the first metres (let new players settle in)
@export var speed_per_meter := 0.45       ## px/s added per meter after the grace distance
@export var max_speed := 850.0
@export var hop_points := 100             ## per hop target, × combo × the target's bonus
@export var slice_points := 50            ## per bird sliced, × combo
@export var combo_window := 2.5           ## seconds each action (bounce, landing, bird kill) keeps the combo alive
@export var combo_mult_cap := 20          ## score multiplier cap (the counter keeps counting)
@export var shake_amount := 4.0           ## camera shake px per slice
@export var hitstop_time := 0.045         ## real seconds of slow-mo on slices and bonus bounces (0 = off)

const SLICE_COL := Color(0.55, 0.95, 1.0)
const SLICE_HOT := Color(1.0, 0.45, 0.95)
const HOP_COL := Color(1.0, 0.9, 0.35)
const HOP_HOT := Color(1.0, 0.6, 0.2)
const HOP_HOTTEST := Color(1.0, 0.35, 0.6)
@export var panel_min_wait := 1.5         ## game-over menu (zoom out to the kid) once the runner has left the screen, but not before this...
@export var panel_max_wait := 3.0         ## ...and at the latest after this

const PX_PER_METER := 50.0
const MENU_MARGIN := 64.0                 ## px of guaranteed lead-in before x 0 after the zoom-in

static var best_score := 0                ## loaded from / saved to user://save.cfg (Settings.best_score)
static var bench := false                 ## `-- --bench[=S]`: seeded global rng, no deaths, vsync off, stats, quit after S s
var _bench_len := 90.0
var _bench_t := 0.0
var _bench_acc := {}                      ## stat -> [sum this window, sum overall]
var _bench_n := [0, 0]                    ## frames [this window, overall]
var _bench_print := 0.0

var scroll_speed := 0.0
var cam_x := 0.0
var distance := 0.0
var hop_score := 0
var slice_score := 0
var combo := 0                            ## actions in a row, each within combo_window of the last
var best_combo := 0
var _combo_t := 0.0
var _shake := 0.0
var game_over := false

var gen: WireGenerator
var traffic: Traffic
var runner: Runner
var cam: Camera2D
var street: Street
var score_label: Label
var combo_meter: ComboMeter
var backdrop: Backdrop
var greenery: Greenery
var weather: Weather                      ## screen-space rain, null when dry
var cabin: Cabin                          ## intro, start menu and game-over menu (the kid's car)
var round_seed := 0                       ## level seed for this round (random unless `--seed=N`)
var round_mood := WireGenerator.Mood.NORMAL
var _reflection_mat: ShaderMaterial
var _restarting := false
var _hit_time := 0.0
var _over_shown := false
var _over_info := {}
var _hitstop_n := 0
var _hud_layer: CanvasLayer
var _toast: Control                       ## radio station toast (HUD), null when not showing
const TOAST_TIME := 1.6
var _pause_menu: PauseMenu                ## null unless paused
var _origin_x := 320.0                    ## runner x when play started (distance is measured from here)
var _view_x := 0.0                        ## monotonic scroll for the backdrop (cam_x wraps in the menu)


func _ready() -> void:
	Engine.time_scale = 1.0                     # in case a restart landed mid-hitstop
	for a in OS.get_cmdline_user_args():
		if a == "--bench" or a.begins_with("--bench="):
			bench = true
			if a.begins_with("--bench="):
				_bench_len = float(a.trim_prefix("--bench="))
	Runner.immortal = bench
	if bench:
		seed(_round_seed() ^ 0x5bd1e995)        # global rng too (car models, colours, jitter) -> repeatable frames
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT   # render 1280x720 whatever the WM does
	_setup_input()
	PixelArt.warm_wheels()                      # once per launch (cached): no hitch when the first car shows up
	if OS.has_feature("mobile"):
		Engine.max_fps = 60                     # phones: no point drawing faster than the game moves (battery, heat)
	Settings.load_all()
	if not Cabin.launched:
		Settings.apply()                        # window mode / vsync once per launch (volumes: Sound)
	best_score = maxi(best_score, Settings.best_score())
	Sound.attach(get_tree())                    # persistent: survives this scene's reloads
	Sound.new_round()                           # ambience + song for this round's time of day
	var tod := TimeOfDay.p()
	round_seed = _round_seed()
	Biome.setup(round_seed)                     # scenery zones along the run (visual + ambience only)
	Weather.roll(round_seed)                    # dry / light / heavy rain; read by everything visual below
	RenderingServer.set_default_clear_color(Backdrop.wet(tod.sky_bottom, Weather.rain))

	backdrop = Backdrop.new()
	backdrop.seed_value = round_seed
	add_child(backdrop)
	var tint := CanvasModulate.new()            # world only; backdrop/HUD are separate canvas layers
	tint.color = TimeOfDay.tint()
	add_child(tint)

	gen = WireGenerator.new()
	gen.seed_value = round_seed
	add_child(gen)

	street = Street.new()
	street.floor_y = gen.floor_y
	street.z_index = -1
	street.lamp_fixed.connect(_on_lamp_fixed)
	add_child(street)

	greenery = Greenery.new()                   # bushes/trees behind the sidewalk (decoration only)
	greenery.floor_y = gen.floor_y
	greenery.seed_value = round_seed
	greenery.span = gen.span
	greenery.z_index = -2
	add_child(greenery)

	traffic = Traffic.new()
	traffic.gen = gen
	traffic.seed_value = (round_seed ^ 0x2545F491) & 0x3fffffff
	var mood_rng := RandomNumberGenerator.new()
	mood_rng.seed = round_seed ^ 0x1b873593
	round_mood = WireGenerator.pick_mood(mood_rng)
	gen.apply_mood(round_mood, traffic)                 # silent: only shifts the mix
	print("seed %d mood %s rain %s | %s" % [round_seed, WireGenerator.Mood.keys()[round_mood],
		Weather.Level.keys()[Weather.level], Biome.describe()])
	add_child(traffic)

	runner = Runner.new()
	runner.gen = gen
	runner.position = Vector2(320, gen.wire_y_at(0, 320))
	runner.lane = 0
	runner.z_index = 5
	runner.hit.connect(_on_hit)
	runner.hopped.connect(_on_hopped)
	runner.bird_sliced.connect(_on_bird_sliced)
	add_child(runner)

	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(cam)

	_build_reflection(gen.floor_y, tod)
	if Weather.active():
		weather = Weather.new()
		weather.floor_y = gen.floor_y
		add_child(weather)
	Sound.loop("amb_rain_light", 0.6 if Weather.level == Weather.Level.LIGHT else 0.0, 1.0, "World", 0.5)
	Sound.loop("amb_rain_heavy", 0.75 if Weather.heavy() else 0.0, 1.0, "World", 0.5)

	var layer := CanvasLayer.new()
	layer.layer = 10
	_hud_layer = layer
	score_label = _make_label(layer, Vector2(16, 16), 24)
	combo_meter = ComboMeter.new()
	combo_meter.position = Vector2(20, 52)
	layer.add_child(combo_meter)
	add_child(layer)

	cabin = Cabin.new()
	cabin.road_speed = base_speed               # intro car's wheels roll at the lead-in scroll speed
	cabin.play_started.connect(_on_play_started)
	cabin.restart_requested.connect(_restart)
	cabin.menu_requested.connect(_to_menu)
	add_child(cabin)
	if cabin.pre_play():                        # camera starts in the wire-only lead-in at negative x
		runner.visible = false
		score_label.modulate.a = 0.0
		combo_meter.modulate.a = 0.0
		cam_x = _menu_top() - gen.span * 0.5
		if cabin.state == Cabin.State.EXTERIOR or cabin.state == Cabin.State.SPLASH:
			cam_x = _menu_top() - gen.span - base_speed * Cabin.EXTERIOR_TIME
	_view_x = cam_x

	gen.update_spans(cam_x, cam_x + 1280.0)
	if bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		set_process(true)
	else:
		set_process(false)


## Bench stats: per-frame averages every 5 s and for the whole run, then quit.
const BENCH_STATS := {
	"frame_ms": -1, "process_ms": Performance.TIME_PROCESS, "physics_ms": Performance.TIME_PHYSICS_PROCESS,
	"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	"primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
	"nodes": Performance.OBJECT_NODE_COUNT, "static_mb": Performance.MEMORY_STATIC,
}

func _process(delta: float) -> void:
	_bench_t += delta
	if OS.get_cmdline_user_args().has("--bench-trace") and Engine.get_process_frames() % 60 == 0:
		print("trace %d cam %.3f runner %.3f,%.3f score %d" % [Engine.get_physics_frames(), cam_x,
			runner.position.x, runner.position.y, _score()])
	if _bench_t < 1.0:                          # skip the first second (warm-up, first spans)
		return
	for k in BENCH_STATS:
		var v: float = delta * 1000.0 if BENCH_STATS[k] < 0 else Performance.get_monitor(BENCH_STATS[k])
		if k == "process_ms" or k == "physics_ms":
			v *= 1000.0
		elif k == "static_mb":
			v /= 1048576.0
		if not _bench_acc.has(k):
			_bench_acc[k] = [0.0, 0.0]
		_bench_acc[k][0] += v
		_bench_acc[k][1] += v
	_bench_n[0] += 1
	_bench_n[1] += 1
	_bench_print += delta
	if _bench_print >= 5.0:
		_bench_print = 0.0
		print("bench %5.1fs %s" % [_bench_t, _bench_line(0)])
		for k in _bench_acc:
			_bench_acc[k][0] = 0.0
		_bench_n[0] = 0
	if _bench_t >= _bench_len:
		print("BENCH TOTAL %s" % _bench_line(1))
		get_tree().quit()


func _bench_line(i: int) -> String:
	var s := ""
	for k in _bench_acc:
		s += "%s %.2f  " % [k, _bench_acc[k][i] / maxf(_bench_n[i], 1)]
	return s + "fps %.0f" % (1000.0 / maxf(_bench_acc.frame_ms[i] / maxf(_bench_n[i], 1), 0.001))


## Fresh level every round; `-- --seed=N` replays a layout (the seed is printed on start).
func _round_seed() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			return int(a.trim_prefix("--seed=")) & 0x3fffffff
	return randi() & 0x3fffffff


## While the menu waits, cam_x stays below this so the zoom-in still ends before x 0.
func _menu_top() -> float:
	return -(base_speed * Cabin.ZOOM_IN_TIME + MENU_MARGIN)


func _physics_process(delta: float) -> void:
	cabin.step(delta)                           # may emit play_started / restart_requested
	if cabin.pre_play():
		# intro/menu: the car drives on, the runner isn't in play yet. In the menu the camera wraps back by
		# whole spans (poles, wire and lamps repeat every span; no birds/traffic at negative x).
		scroll_speed = 0.0 if cabin.state == Cabin.State.SPLASH else base_speed   # held still under the studio card
		cam_x += scroll_speed * delta
		if cabin.state == Cabin.State.MENU:
			while cam_x > _menu_top():
				cam_x -= gen.span
		_scroll_world(delta)
		return
	_update_cursor()
	if Input.is_action_just_pressed("pause") and _can_pause():
		_pause()
		return
	if Input.is_action_just_pressed("radio") and cabin.state == Cabin.State.PLAY and not game_over:
		Sound.next_station()
		_station_toast()
	if game_over:
		_update_game_over(delta)
	else:
		distance = (runner.position.x - _origin_x) / PX_PER_METER
		scroll_speed = minf(base_speed + speed_per_meter * maxf(distance - speed_grace_m, 0.0), max_speed)
		Sound.intensity(scroll_speed, combo)
	# the car keeps driving after a loss: camera, spans and traffic keep going, the runner is left behind
	cam_x += scroll_speed * delta
	_scroll_world(delta)
	runner.step(delta, scroll_speed, cam_x)

	_shake = maxf(_shake - delta * 60.0, 0.0)
	cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * (_shake if Settings.shake else 0.0)
	if game_over:
		return
	_combo_t = maxf(_combo_t - delta, 0.0)
	if _combo_t <= 0.0 and combo > 0:
		combo = 0
		combo_meter.drop()
	combo_meter.left = _combo_t / combo_window
	score_label.text = "%d" % _score()


func _scroll_world(delta: float) -> void:
	_view_x += scroll_speed * delta
	cam.position = Vector2(cam_x, 0)
	street.cam_x = cam_x
	backdrop.scroll(_view_x, cam_x + 640.0)
	greenery.scroll(cam_x)
	if weather:
		weather.cam_x = cam_x
		weather.scroll_speed = scroll_speed
	_biome_ambience()
	_reflection_mat.set_shader_parameter("world_x", cam_x)
	gen.update_spans(cam_x - 100.0, cam_x + 1380.0)
	traffic.update(delta, cam_x, scroll_speed, cam_x + runner.screen_target, distance)
	var gust := clampf((scroll_speed - 380.0) / 470.0, 0.0, 1.0)  # wind past the window grows with speed
	Sound.loop("amb_wind", 0.25 + 0.5 * gust, 0.85 + 0.35 * gust, "World", 1.5)


## Ambience follows the scenery (cross-faded with it): less traffic rumble out in the country, more crickets
## and songbirds in the suburbs; birds go quiet in the rain. Indexed by Biome.Kind.
func _biome_ambience() -> void:
	var p := TimeOfDay.p()
	var x := cam_x + 640.0
	Sound.loop("amb_city", p.city * Biome.mix(x, [1.0, 0.6]), 1.0, "World", 0.4)
	Sound.loop("amb_crickets", p.crickets * Biome.mix(x, [1.0, 1.4]), 1.0, "World", 0.4)
	Sound.set_chirps(p.chirps * Biome.mix(x, [1.0, 1.4]) * (1.0 - 0.75 * Weather.rain))


## Zoomed into the window: the runner appears on the wire wherever the camera is (still in the
## lead-in before x 0); distance counts from here.
func _on_play_started() -> void:
	_origin_x = cam_x + runner.screen_target
	runner.position = Vector2(_origin_x, gen.wire_y_at(0, _origin_x))
	runner.visible = true
	_burst(runner.position + Vector2(0, -26), SLICE_COL, 64.0, 14)   # the ninja appears (kid's imagination)
	Sound.play("ninja_pop", Sound.note(0), -2.0, 0.0, 0.0)
	score_label.create_tween().tween_property(score_label, "modulate:a", 1.0, 0.4)
	combo_meter.create_tween().tween_property(combo_meter, "modulate:a", 1.0, 0.4)


## After a hit: once the runner has scrolled off the left edge (min/max wait), zoom back out of the
## window to the kid and the game-over menu (Cabin handles the restart press).
func _update_game_over(delta: float) -> void:
	_hit_time += delta
	if _over_shown:
		return
	var gone := runner.position.x < cam_x - 70.0
	if (gone and _hit_time >= panel_min_wait) or _hit_time >= panel_max_wait:
		_over_shown = true
		cabin.show_game_over(_over_info)
		score_label.create_tween().tween_property(score_label, "modulate:a", 0.0, 0.3)
		combo_meter.create_tween().tween_property(combo_meter, "modulate:a", 0.0, 0.3)


func _score() -> int:
	return int(distance) + hop_score + slice_score


## Every action (bounce, landing on a target, bird kill) extends the one combo and refills its timer.
## Returns the score multiplier.
func _add_combo() -> int:
	combo += 1
	_combo_t = combo_window
	best_combo = maxi(best_combo, combo)
	combo_meter.bump(combo)
	return mini(combo, combo_mult_cap)


func _on_bird_sliced(pos: Vector2) -> void:
	if game_over:
		return
	var m := _add_combo()
	var pts := slice_points * m
	slice_score += pts
	var c := mini(combo, 10)
	_shake = shake_amount + c * 0.6
	var col := SLICE_COL.lerp(SLICE_HOT, clampf((combo - 1) / 6.0, 0.0, 1.0))
	var at := pos + Vector2(0, -16)
	_burst(at, col, 34.0 + c * 6.0, 8 + c)
	var text := "+%d" % pts if combo < 2 else "+%d  x%d" % [pts, m]
	_popup(text, at + Vector2(-20, -44), 14 + mini(combo, 6) * 3, col)
	_punch(score_label, col)
	_hitstop(hitstop_time)
	Sound.play("slice_hit", Sound.note(mini(combo - 1, 9)), -2.0, 0.0, 0.0)   # climbs the song's scale


func _on_hopped(_runner_combo: int, mult: float, target: Node2D) -> void:
	if game_over:
		return
	var m := _add_combo()
	var pts := int(hop_points * m * mult)
	hop_score += pts
	var col := HOP_COL
	if mult >= 6.0:
		col = HOP_HOTTEST
	elif mult >= 3.0:
		col = HOP_HOT
	var feet := runner.position
	_burst(feet, col, 30.0 + 10.0 * mult + 4.0 * mini(combo, 6), 8 + int(mult) * 2)
	var text := "+%d" % pts if combo == 1 else "+%d  x%d" % [pts, m]
	_popup(text, feet + Vector2(-24, -96), 16 + mini(combo, 6) * 3, col)
	if mult > 1.0:
		if not target is Pedestrian:              # people say their own line instead (Pedestrian.Shout bubble)
			var bonus := "x%s BONUS!" % String.num(mult, 1).trim_suffix(".0")
			get_tree().create_timer(0.08).timeout.connect(_popup.bind(bonus, feet + Vector2(-30, -64), 12 + int(mult) * 2, col.lightened(0.3)))
		Sound.play("bonus", Sound.note(0 if mult < 3.0 else (2 if mult < 6.0 else 5)), -3.0, 0.06, 0.0)
		_hitstop(hitstop_time)
		_shake = maxf(_shake, 2.0 + mult)
	_punch(score_label, col)
	Sound.play("hop", Sound.note(mini(combo - 1, 9)), -3.0, 0.0, 0.0)


func _on_hit(reason: String) -> void:
	game_over = true                            # score freezes; the world keeps moving (see _physics_process)
	Sound.music(Sound.M.DEAD)                   # tape stop
	_hit_time = 0.0
	_shake = {"car": 14.0, "electrocuted": 10.0}.get(reason, 7.0)
	if reason == "electrocuted":
		_flash_screen()
	combo_meter.freeze()
	var final := _score()
	var new_best := final > best_score
	best_score = maxi(best_score, final)
	Settings.set_best(best_score)
	var lines: Array = DEATH_QUIPS.get(reason, ["NICE ONE, GENIUS."])
	_over_info = {"cause": lines.pick_random(), "score": final, "new_best": new_best, "distance": int(distance),
		"hops": hop_score, "slices": slice_score, "combo": best_combo, "best": best_score}


## A dead/flickering street lamp was bounced back on.
func _on_lamp_fixed(at: Vector2) -> void:
	_burst(at, Color(1.0, 0.85, 0.4), 46.0, 12)
	_popup("FIXED!", at + Vector2(-40, -60), 24, Color(1.0, 0.9, 0.45))
	Sound.play_at("lamp_fixed", at, Sound.note(0), -2.0, 0.0, 0.0)
	_shake = maxf(_shake, 4.0)


## Game-over headline per hit reason (Runner.hit), picked at random. Max 26 chars (one line at 24 px).
const DEATH_QUIPS := {
	"electrocuted": ["HOW SHOCKING!!!", "WATT WAS THAT?!", "YOU'RE GROUNDED!!!", "CURRENTLY: DEAD."],
	"pedestrian": ["HEY, I'M WALKIN' HERE!!!", "WATCH IT, BUDDY!!!", "EYES UP, GENIUS!", "EXCUSE YOU!!!"],
	"cyclist": ["BIKE LANE, PAL!!!", "*DING DING* TOO LATE.", "SHARE THE ROAD, NINJA!"],
	"motorcyclist": ["VROOM VROOM, LOSER!", "NICE HELMET. OH WAIT.", "ROAD RASH, BABY!!!"],
	"car": ["BEEP BEEP, LOSER!", "LEARN TO JUMP MUCH?", "YOU DENTED MY CAR!!!", "THAT'LL BUFF OUT."],
	"bird": ["OUTSMARTED BY A PIGEON.", "COO COO, CLOWN.", "THE PIGEON WON. AGAIN.", "BIRDBRAIN MOVE."],
}


## World-space score text: punches in (scale overshoot), then rises and fades. Undoes the world tint.
func _popup(text: String, pos: Vector2, font_size: int = 24, col := Color(1.0, 0.95, 0.4)) -> void:
	if _restarting:
		return
	var l := Label.new()
	l.text = text
	l.position = pos
	l.z_index = 20
	l.add_theme_font_size_override("font_size", maxi(8, roundi(font_size / 8.0) * 8))   # pixel font: multiples of 8
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", 8)
	var t: Color = TimeOfDay.tint()
	l.self_modulate = Color(1.0 / t.r, 1.0 / t.g, 1.0 / t.b)
	add_child(l)
	l.reset_size()
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(0.3, 0.3)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.35, 1.35), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.25)
	tw.set_parallel()
	tw.tween_property(l, "position:y", pos.y - 50.0, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)


## Expanding ring + spark burst at a scoring hit (world space).
func _burst(at: Vector2, col: Color, radius: float, sparks: int) -> void:
	var b := Burst.new()
	b.position = at
	b.color = col
	b.radius = radius
	b.sparks = sparks
	b.z_index = 19
	add_child(b)


## HUD label pop: quick scale overshoot and colour flash back to its normal colour.
func _punch(l: Label, col: Color) -> void:
	l.pivot_offset = Vector2(0, l.size.y / 2.0)
	if l.has_meta("punch"):
		(l.get_meta("punch") as Tween).kill()
	l.scale = Vector2(1.45, 1.45)
	l.modulate = Color(col.r * 1.3, col.g * 1.3, col.b * 1.3)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate", Color.WHITE, 0.35)
	l.set_meta("punch", tw)


## Brief slow-motion for impact. Real-time timer, so it always ends; reset in _ready on restart.
func _hitstop(dur: float) -> void:
	if dur <= 0.0 or game_over or bench:      # bench: real-time timers would make runs unrepeatable
		return
	Engine.time_scale = 0.12
	_hitstop_n += 1
	get_tree().create_timer(dur, true, false, true).timeout.connect(func() -> void:
		_hitstop_n -= 1
		if _hitstop_n <= 0:
			Engine.time_scale = 1.0)


class Burst extends Node2D:
	const LIFE := 0.32
	var color := Color.WHITE
	var radius := 40.0
	var sparks := 8
	var _t := 0.0
	var _dirs: Array[Vector2] = []

	func _ready() -> void:
		var a0 := randf() * TAU
		for k in sparks:
			_dirs.append(Vector2.from_angle(a0 + TAU * k / sparks + randf_range(-0.2, 0.2)) * randf_range(0.8, 1.2))

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _t / LIFE
		var e := 1.0 - pow(1.0 - k, 3.0)                       # ease-out
		var hot := Color(color.r * 1.8, color.g * 1.8, color.b * 1.8, 1.0 - k)   # >1: survives night tint
		draw_circle(Vector2.ZERO, radius * 0.45 * (1.0 - k), Color(2.0, 2.0, 1.9, 0.7 * (1.0 - k)))   # core flash
		draw_arc(Vector2.ZERO, radius * e, 0.0, TAU, 24, hot, maxf(6.0 * (1.0 - k), 1.0))
		for d in _dirs:
			var p0 := d * radius * (0.3 + 0.9 * e)
			draw_line(p0, p0 + d * 12.0 * (1.0 - k), hot, 3.0)


func _make_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)          # readable on every sky
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
	l.add_theme_constant_override("outline_size", maxi(size / 3, 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	parent.add_child(l)
	return l


## Road-strip ColorRect running the wet-road reflection shader (screen space, under the HUD).
func _build_reflection(floor_y: float, tod: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	var rect := ColorRect.new()
	rect.position = Vector2(0, floor_y)
	rect.size = Vector2(1280, 720 - floor_y)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reflection_mat = ShaderMaterial.new()
	_reflection_mat.shader = load("res://shaders/reflection.gdshader")
	_reflection_mat.set_shader_parameter("axis_px", floor_y)
	_reflection_mat.set_shader_parameter("strength", minf(tod.reflection + 0.3 * Weather.rain, 0.95))   # rain: wetter
	_reflection_mat.set_shader_parameter("tint", tod.refl_tint)
	rect.material = _reflection_mat
	layer.add_child(rect)
	add_child(layer)


## From the game-over / pause menu: fade to black and open the next round on the zoom into the window.
func _restart() -> void:
	_reload(false)


## MAIN MENU (game over / pause): the next round opens on the kid at the window with the start menu.
func _to_menu() -> void:
	_reload(true)


func _reload(menu: bool) -> void:
	if _restarting:
		return
	_restarting = true
	_unpause()
	TimeOfDay.round_count += 1                  # time of day advances every TimeOfDay.ROUNDS_PER_PHASE rounds
	Cabin.quick_start = not menu
	Cabin.to_menu = menu
	cabin.fade(0.0, 1.0, 0.25, func() -> void: get_tree().reload_current_scene.call_deferred())


func _can_pause() -> bool:
	return cabin.state == Cabin.State.PLAY and not game_over and not _restarting and _pause_menu == null


## Freeze the world (everything but Sound and the menu), muffle it through the car glass, show the menu.
func _pause() -> void:
	Engine.time_scale = 1.0                     # a hitstop's timer still runs (process-always) and resets it too
	get_tree().paused = true
	Sound.set_glass(1.0, 1.0)                   # Cabin._sound() opens it again on the next unpaused step
	_pause_menu = PauseMenu.new()
	_pause_menu.resumed.connect(_unpause)
	_pause_menu.restart.connect(_restart)
	_pause_menu.main_menu.connect(_to_menu)
	add_child(_pause_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unpause() -> void:
	if _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null
	get_tree().paused = false


## Window lost focus mid-run: pause so the player doesn't come back to a crash.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and cabin and _can_pause() and not bench:
		_pause()


## Mouse pointer only where there's something to click (menus), hidden during a run.
func _update_cursor() -> void:
	var want := Input.MOUSE_MODE_HIDDEN if cabin.state == Cabin.State.PLAY and not game_over \
		else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want and DisplayServer.get_name() != "headless":
		Input.mouse_mode = want


## Car radio toast (HUD, top right): "FM 92.7" over the station name, slides in, holds, fades. A new press
## replaces it. Colours > 1 aren't needed: the HUD layer isn't tinted.
func _station_toast() -> void:
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
	var lines := Radio.label()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for i in 2:
		var l := Label.new()
		l.text = lines[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_font_size_override("font_size", 16 if i == 0 else 24)
		l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75) if i == 0 else Color(1.0, 0.95, 0.8))
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.08))
		l.add_theme_constant_override("outline_size", 8)
		box.add_child(l)
	_hud_layer.add_child(box)
	box.reset_size()
	var x := 1280.0 - 24.0 - box.size.x
	box.position = Vector2(x + 40.0, 20.0)
	box.modulate.a = 0.0
	_toast = box
	var tw := box.create_tween()
	tw.set_parallel()
	tw.tween_property(box, "position:x", x, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, 0.12)
	tw.chain().tween_interval(TOAST_TIME)
	tw.chain().tween_property(box, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(box.queue_free)


func _setup_input() -> void:
	_bind("jump", [KEY_SPACE, KEY_W, KEY_UP], [JOY_BUTTON_A])
	_bind("slice", [KEY_J, KEY_X], [JOY_BUTTON_X])
	_bind("drop", [KEY_S, KEY_DOWN], [JOY_BUTTON_B, JOY_BUTTON_DPAD_DOWN])
	_bind("start", [KEY_ENTER], [JOY_BUTTON_START])          # menus only (Cabin); restart is from the game-over menu
	_bind("radio", [KEY_R], [JOY_BUTTON_Y])
	_bind("mute", [KEY_M], [])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])  # pad Start is also "start": menus only, no clash
	_bind("fullscreen", [KEY_F11], [])
	# menus (MenuList): arrows / WASD / d-pad / left stick, Space/Enter/J = OK, Esc/Backspace/pad B = back
	_bind("menu_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("menu_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("menu_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("menu_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("menu_ok", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_J], [JOY_BUTTON_A, JOY_BUTTON_START])
	_bind("menu_back", [KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_B])


func _bind(action: String, keys: Array, buttons: Array, axes: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.5)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)


## White-blue flash over everything (electrocution).
func _flash_screen() -> void:
	if not Settings.flashes:
		return
	var r := ColorRect.new()
	r.color = Color(0.85, 0.92, 1.0, 0.75)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(r)
	_hud_layer.move_child(r, 0)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.4)
	tw.tween_callback(r.queue_free)
