class_name Cabin
extends CanvasLayer
## The kid's car (design §2): launch intro, start menu and game-over menu. The real game world is the
## background the whole time; Game keeps the camera scrolling while this layer draws over it. The
## interior is drawn around a transparent window hole, so the live world scrolls past in the glass.
##   launch:  SPLASH (studio card) -> EXTERIOR (car drives in, push into the rear window) -> MENU -> ZOOM_IN -> PLAY
##   death:   PLAY -> ZOOM_OUT (back out of the window) -> GAME_OVER -> restart_requested
##   restart from the game-over menu reloads with quick_start set: straight into ZOOM_IN; MAIN MENU (game over /
##   pause) reloads with to_menu set: straight into MENU. The menus are MenuLists (+ a SettingsMenu board).
## Game calls step(delta) every physics frame; pre_play() = the camera is in the safe negative-x
## lead-in and the runner is hidden.

signal play_started                       ## zoom-in done: gameplay begins at the current camera x
signal restart_requested                  ## RIDE AGAIN on the game-over menu
signal menu_requested                     ## MAIN MENU on the game-over menu

enum State { SPLASH, EXTERIOR, MENU, ZOOM_IN, PLAY, ZOOM_OUT, GAME_OVER }

static var launched := false              ## the car exterior plays only on the first launch
static var quick_start := false           ## set by Game before a game-over restart
static var to_menu := false               ## set by Game before a reload to the start menu

const STUDIO := "CHONKY GAMES"
const SPLASH_TIME := 2.7                  ## studio card: fade in, hold, fade out (black), then the exterior

const T_DRIVE := 1.4                      ## exterior: car drives in and settles...
const T_PUSH := 2.6                       ## ...push into the rear window...
const EXTERIOR_TIME := 2.95               ## ...fade-cut to the interior (menu)
const ZOOM_IN_TIME := 1.4
const ZOOM_OUT_TIME := 1.1
const INPUT_DELAY := 0.4                  ## menus ignore presses this long after they appear
const VIEW := Vector2(1280, 720)
const CAR_X := 330.0
const CAR_Y := 712.0                      ## car ground line (near lane, in front of the street)
const DRIVE_FROM := -520.0                ## car x when the exterior starts (drives in to CAR_X)
const S_MENU := 1.0                       ## interior scale while the menu shows (1:1 keeps the art pixels even)
const S_FINAL := 2.3                      ## interior scale when Interior.COVER covers the view
const TITLE := "WINDOW RUNNER"
const COUNT_TIME := 0.8                   ## game-over score counts up this long
const TEXT := Color(1.0, 0.98, 0.92)
const GOLD := Color(1.0, 0.82, 0.3)
const OUTLINE := Color(0.06, 0.04, 0.1)

const KID_PALETTE := {
	"K": Color(0.08, 0.06, 0.08), "H": Color(0.28, 0.17, 0.12), "h": Color(0.45, 0.3, 0.2),
	"S": Color(0.96, 0.78, 0.62), "p": Color(0.95, 0.6, 0.55), "E": Color(0.1, 0.08, 0.1),
	"m": Color(0.7, 0.35, 0.3), "Y": Color(0.98, 0.78, 0.2), "y": Color(0.82, 0.58, 0.12),
	"B": Color(0.25, 0.25, 0.3), "d": Color(0.19, 0.11, 0.08), "s": Color(0.82, 0.6, 0.48),
	"o": Color(0.66, 0.44, 0.1),
}
## Kid at the window, 3/4 back view, sitting upright (neck, sloped shoulders, straight back), reaching
## to the sill (hands at row 26).
## 42x50 art px; the torso runs off the bottom of the view.
const KID := [
	"..........K...KK..K.......................",
	".........KhK.KhhKKhK......................",
	"........KhHHKhHHHhHHK.....................",
	".......KHHHHHhHHHhHHHK....................",
	"......KHHHhHHHHHHHhHHHK...................",
	".....KHHHhHHHHHhHHHHHHHK..................",
	".....KHHhHHHHHhHHHHHHHHHK.................",
	"....KHHHHHHHHHHHHHHHHHHHK.................",
	"....KHHHHHHHHHHHHHHHHHHHHK................",
	"....KdHHHHHHHHHHHHHHHHHHHK................",
	"....KdHHHHHHHHHHHHHHHHHSSK................",
	"....KdHHHHHHHHHHHHHHHHSSSSK...............",
	"....KddHHHHHHHHHSSHHHSSESSK...............",
	"....KddHHHHHHHHSsSSHHSSSSSSK..............",
	".....KdHHHHHHHHSsSSHSSSSSSK...............",
	".....KddHHHHHHHHSSHSSSSpSSK...............",
	"......KddHHHHHHHHHSSSSSSSK................",
	".......KKdHHHHHHHSSSSSSKK.................",
	".......KKKddHHHHSSSSsKK...................",
	".........KKsssssssssK.....................",
	"...........KsssssssK......................",
	".......KKKKKyyyyyyyKKKKK..................",
	".....KKYYYYYyyyyyyyYYYYYKK................",
	"....KYYYYYYYYYYYYYYYYYYYYYK...............",
	"...KYYoYYYYYYYYYYYYYYYYYYYYK..............",
	"...KYoYYYYYYYYYYYYYYYYYYYYYYKK............",
	"...KYoYYYYYYYYYYYYYYYYYYYYYYYYKK....KKKK..",
	"...KYoYYYYYYYYYYYYYYYYyYYYYYYYYYKK.KSSSSK.",
	"...KYoYYYYYYYYYYYYYYYYYyyYYYYYYYYKKSSSsSK.",
	"...KYoYYYYYYYYYYYYYYYYYYyyyyYYYYKSSSSSSK..",
	"...KYoYYYYYYYYYYYYYYYYYYYYYyyyyKKSSsSSK...",
	"...KYoYYYYYYYYYYYYYYYYYYYYYKKKKK.KKKKK....",
	"...KYoYYYYYYYYYYYYYYYYYYYYK...............",
	"...KYoYYYYYYYYYYYYYYYYYYYyK...............",
	"...KYooYYYYYYYYYYYYYYYYYYyK...............",
	"...KYYoYYYYYYYYYYYYYYYYYYyK...............",
	"...KYYoYYYYYYYYYYYYYYYYYYyK...............",
	"...KYYoYYYYYYYYYYYYYYYYYyyK...............",
	"...KYYooYYYYYYYYYYYYYYYYyyK...............",
	"...KYYYoYYYYYYYYYYYYYYYYyyK...............",
	"...KYYYoYYYYYYYYYYYYYYYYyyK...............",
	"...KYYYoYYYYYYYYYYYYYYYYyyK...............",
	"...KYYYooYYYYYYYYYYYYYYYyyK...............",
	"...KYYYYoYYYYYYYYYYYYYYYyyK...............",
	"...KYYYYoYYYYYYYYYYYYYYYyyK...............",
	"...KYYYYoYYYYYYYYYYYYYYYyyK...............",
	"...KYYYYooYYYYYYYYYYYYYYyyK...............",
	"...KYYYYYoYYYYYYYYYYYYYYyyK...............",
	"...KYYYYYoYYYYYYYYYYYYYYyyK...............",
	"...KYYYYYoYYYYYYYYYYYYYYyyK...............",
]
## Small kid seen through the car's rear door window from outside. 10x11 art px.
const KID_SMALL := [
	"..KKKKK...",
	".KHHHHHK..",
	"KHHHHHHHK.",
	"KHHHHSSSK.",
	"KHHHSSESSK",
	"KHHHSSSSSK",
	".KHHSSSSK.",
	"..KKSSSK..",
	".KYYYYYYK.",
	"KYYYYYYYYK",
	"KYYYYYYYYK",
]

var state := State.PLAY
var road_speed := 420.0                   ## px/s the camera scrolls during the intro (Game sets base_speed)
var _t := 0.0                             ## time in the current state
var _clock := 0.0                         ## monotonic (kid blink/breath, glass streaks)
var _root: Node2D                         ## tinted like the world (CanvasModulate doesn't reach layers)
var _ext: Node2D                          ## exterior shot (car), scaled for the push-in
var _car: FamilyCar
var _interior: Interior
var _fade: ColorRect
var _fade_tw: Tween
var _ui: Control                          ## menu text: not tinted, fades with the zooms
var _menu: Control
var _over: Control
var _over_cause: Label
var _over_score: Label
var _over_stats: Label
var _over_best: Control                   ## "NEW BEST!" badge on the board's top edge
var _score_target := 0
var _score_punched := false
var _last_tick := 0.0                     ## game-over count-up: time of the last tick sound
var _pushed := false                      ## exterior: push-in whoosh played
var _menu_list: MenuList
var _over_list: MenuList
var _board: SettingsMenu                  ## settings / credits board over the menu, null when closed
var _splash: Control
var _chimed := false


static func kid_texture(blink: bool) -> ImageTexture:
	var pal := KID_PALETTE.duplicate()
	if blink:
		pal["E"] = Color(0.8, 0.6, 0.48)
	return PixelArt.texture("kid_blink" if blink else "kid", PackedStringArray(KID), pal)


func _ready() -> void:
	layer = 20
	_root = Node2D.new()
	_root.modulate = TimeOfDay.tint()
	add_child(_root)
	_ext = Node2D.new()
	_root.add_child(_ext)
	_car = FamilyCar.new()
	_car.lights = TimeOfDay.lights_on()
	_ext.add_child(_car)
	_interior = Interior.new()
	_root.add_child(_interior)
	_build_ui()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = VIEW
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_build_splash()

	if quick_start:
		quick_start = false
		_enter(State.ZOOM_IN)
		fade(1.0, 0.0, 0.3)
	elif to_menu:
		to_menu = false
		_enter(State.MENU)
		fade(1.0, 0.0, 0.4)
	elif not launched and not OS.get_cmdline_user_args().has("--no-intro"):
		_enter(State.SPLASH)
	else:
		_enter(State.PLAY)
	launched = true
	_layout()


func pre_play() -> bool:
	return state == State.SPLASH or state == State.EXTERIOR or state == State.MENU or state == State.ZOOM_IN


## Game over: back out of the window onto the kid, then the stats panel. info: see Game._on_hit.
func show_game_over(info: Dictionary) -> void:
	_over_cause.text = str(info.cause).to_upper()
	_over_stats.text = "%-10s%8s\n%-10s%8s\n%-10s%8s\n%-10s%8s\n%-10s%8d" % [
		"DISTANCE", "%d M" % info.distance, "HOPS", "+%d" % info.hops,
		"SLICES", "+%d" % info.slices, "MAX COMBO", "x%d" % info.get("combo", 0), "BEST", info.best]
	_over_best.visible = info.new_best
	_score_target = info.score
	_score_punched = false
	_over_score.text = "0"
	_last_tick = 0.0
	_enter(State.ZOOM_OUT)


## Fade the black overlay from a to b over dur seconds, then call done (if valid).
func fade(a: float, b: float, dur: float, done := Callable()) -> void:
	if _fade_tw:
		_fade_tw.kill()
	_fade.color.a = a
	_fade_tw = create_tween()
	_fade_tw.tween_property(_fade, "color:a", b, dur)
	if done.is_valid():
		_fade_tw.tween_callback(done)


func step(delta: float) -> void:
	_t += delta
	_clock += delta
	var go := Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("slice") \
		or Input.is_action_just_pressed("start")
	match state:
		State.SPLASH:
			if not _chimed and _t >= 0.35:
				_chimed = true
				Sound.play("splash_chime", Sound.note(0), -4.0, 0.0, 0.0, "Ui")
			if _t >= SPLASH_TIME or (go and _t > 0.3):
				_enter(State.EXTERIOR)
		State.EXTERIOR:
			if not _pushed and _t >= T_PUSH - 0.25:
				_pushed = true
				Sound.play("push_whoosh", 1.0, -4.0, 0.0, 0.0, "Ui")
			if _t >= EXTERIOR_TIME or (go and _t > 0.3):
				_enter(State.MENU)
				fade(1.0, 0.0, 0.4)
		State.ZOOM_IN:
			if _t >= ZOOM_IN_TIME:
				_enter(State.PLAY)
				play_started.emit()
		State.ZOOM_OUT:
			if _t >= ZOOM_OUT_TIME:
				_enter(State.GAME_OVER)
	_layout()
	_sound()


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	_menu_list.active = s == State.MENU
	_over_list.active = s == State.GAME_OVER
	if s == State.MENU:
		_menu_list.select(0)
	if s == State.GAME_OVER:
		_over_list.select(0)
	match s:
		State.SPLASH, State.EXTERIOR, State.MENU:
			Sound.music(Sound.M.MENU)
		State.ZOOM_IN:
			Sound.music(Sound.M.ZOOM)
			Sound.play("zoom_whoosh", 1.0, -6.0, 0.0, 0.0, "Ui")
		State.PLAY:
			Sound.music(Sound.M.PLAY)
		State.ZOOM_OUT:
			Sound.music(Sound.M.OVER)
			Sound.play("zoom_out", 1.0, -7.0, 0.0, 0.0, "Ui")


## Inside the car the world is heard through the glass (and the car drones); zooming into the window opens it
## up. Outside (exterior shot) the family car's engine passes by and the radio is muffled by the car body.
func _sound() -> void:
	var world := 0.0
	var radio := 0.0
	var engine := 0.0
	match state:
		State.SPLASH:
			world = 1.0
			radio = 1.0
		State.EXTERIOR:
			var k := clampf((_t - T_PUSH) / (EXTERIOR_TIME - T_PUSH), 0.0, 1.0)
			world = k
			radio = lerpf(1.4, 1.0, k)
			engine = 1.0 - k
		State.MENU, State.GAME_OVER:
			world = 1.0
			radio = 1.0
		State.ZOOM_IN:
			world = 1.0 - _smooth(_t / ZOOM_IN_TIME)
			radio = world
		State.ZOOM_OUT:
			world = _smooth(_t / ZOOM_OUT_TIME)
			radio = world
	Sound.set_glass(world, radio)
	Sound.loop("car_drone", world * 0.4, 1.0, "Sfx", 4.0)
	var drive := 1.0 - pow(1.0 - clampf(_t / T_DRIVE, 0.0, 1.0), 3.0)
	Sound.loop("car_engine_ext", engine * 0.75, 1.15 - 0.2 * drive, "Sfx", 6.0)


func _layout() -> void:
	_root.visible = state != State.PLAY
	_ext.visible = state == State.EXTERIOR
	_interior.visible = state != State.SPLASH and state != State.EXTERIOR and state != State.PLAY
	_menu.visible = (state == State.MENU or state == State.ZOOM_IN) and _board == null
	_over.visible = state == State.ZOOM_OUT or state == State.GAME_OVER
	_splash.visible = state == State.SPLASH
	match state:
		State.SPLASH:
			_fade.color.a = 1.0
			_ui.modulate.a = 0.0
			var a := clampf((_t - 0.3) / 0.5, 0.0, 1.0) * clampf((SPLASH_TIME - 0.25 - _t) / 0.5, 0.0, 1.0)
			_splash.modulate.a = a
			_splash.position.y = roundf(8.0 * (1.0 - _smooth(_t / 0.8)) / 2.0) * 2.0   # settles up into place
		State.EXTERIOR:
			_layout_exterior()
			_ui.modulate.a = 0.0
		State.MENU, State.GAME_OVER:
			_place_interior(0.0)
			_ui.modulate.a = clampf(_t / 0.3, 0.0, 1.0)
		State.ZOOM_IN:
			_place_interior(_smooth(_t / ZOOM_IN_TIME))
			_ui.modulate.a = 1.0 - clampf(_t / 0.2, 0.0, 1.0)
		State.ZOOM_OUT:
			_place_interior(1.0 - _smooth(_t / ZOOM_OUT_TIME))
			_ui.modulate.a = 0.0
	if state == State.GAME_OVER:
		_layout_score()


## Game-over score: counts up (ease-out), then punches in; gently pulses gold <-> white after.
func _layout_score() -> void:
	var u := clampf((_t - 0.15) / COUNT_TIME, 0.0, 1.0)
	_over_score.text = str(roundi(_score_target * (1.0 - pow(1.0 - u, 3.0))))
	_over_score.pivot_offset = _over_score.size / 2.0             # fixed panel width: stays centred
	if u > 0.0 and u < 1.0 and _score_target > 0 and _t - _last_tick >= 0.06:
		_last_tick = _t                                           # count-up ticks climb the scale
		Sound.play("ui_tick", Sound.note(int(u * 8.0)), -9.0, 0.0, 0.0, "Ui")
	if u >= 1.0 and not _score_punched:
		_score_punched = true
		Sound.play("score_punch", Sound.note(0), -3.0, 0.0, 0.0, "Ui")
		if _over_best.visible:
			Sound.play("fanfare", Sound.note(0), -2.0, 0.15, 0.0, "Ui")
		_over_score.scale = Vector2(1.5, 1.5)
		_over_score.create_tween().tween_property(_over_score, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var glow := 0.5 + 0.5 * sin(_clock * 4.0) if _score_punched else 0.0
	_over_score.add_theme_color_override("font_color", GOLD.lerp(Color(1.0, 0.97, 0.75), glow * 0.6))
	_over_best.scale = Vector2.ONE * (1.0 + 0.06 * sin(_clock * 6.0))


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _layout_exterior() -> void:
	var t := _t
	var drive := 1.0 - pow(1.0 - clampf(t / T_DRIVE, 0.0, 1.0), 3.0)
	_car.position = Vector2(lerpf(DRIVE_FROM, CAR_X, drive), CAR_Y)
	_car.t = t
	_car.spin = (road_speed * t + _car.position.x - DRIVE_FROM) / (FamilyCar.WHEEL_R * FamilyCar.U)  # rolls
	_car.queue_redraw()
	var pivot := _car.position + FamilyCar.REAR_WINDOW
	var s := lerpf(1.0, 1.12, smoothstep(T_DRIVE, T_PUSH, t))
	var k := clampf((t - T_PUSH) / (EXTERIOR_TIME - T_PUSH), 0.0, 1.0)
	s *= lerpf(1.0, 4.0, k * k)
	_ext.scale = Vector2(s, s)
	_ext.position = pivot * (1.0 - s)
	_fade.color.a = maxf(1.0 - clampf(t / 0.5, 0.0, 1.0), k)    # fade in at the start, out at the cut


## k = 0: menu framing (kid + window); k = 1: window centred and covering the whole view.
func _place_interior(k: float) -> void:
	var s := lerpf(S_MENU, S_FINAL, k)
	var wc := Interior.COVER.get_center()
	var c := wc.lerp(VIEW / 2.0, k) + Vector2(0, sin(_clock * 7.0) * 2.0 * (1.0 - k))   # car sway
	_interior.scale = Vector2(s, s)
	_interior.position = (c - wc * s).round()
	_interior.t = _clock
	_interior.glass = 1.0 - k
	_interior.queue_redraw()


func _build_ui() -> void:
	_ui = Control.new()
	_ui.size = VIEW
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var win := Rect2(420, 0, 700, 0)                  # text column over the window glass

	_menu = Control.new()
	_ui.add_child(_menu)
	_label(_menu, TITLE, 40, GOLD, Vector2(win.position.x, 150), win.size.x)
	_menu_list = MenuList.new()
	_menu_list.position = Vector2(win.position.x + 150, 300)
	_menu_list.width = win.size.x - 300
	_menu_list.add_item("PLAY", _on_play)
	_menu_list.add_item("SETTINGS", _open_board.bind(SettingsMenu.Page.SETTINGS))
	_menu_list.add_item("CREDITS", _open_board.bind(SettingsMenu.Page.CREDITS))
	if not OS.has_feature("web"):
		_menu_list.add_item("QUIT", func() -> void: get_tree().quit())
	_menu.add_child(_menu_list)
	var controls := _label(_menu, "SPACE  JUMP (x2)   J  SLICE\nS      DROP       R  RADIO\nESC    PAUSE      M  MUTE",
		16, TEXT, Vector2(win.position.x + win.size.x / 2.0 - 27 * 8, 574), 0.0)   # 27 monospaced 16 px glyphs, centred
	controls.add_theme_constant_override("line_spacing", 8)

	_over = Control.new()
	_ui.add_child(_over)
	var panel := Rect2(460, 100, 640, 420)
	var border := ColorRect.new()
	border.position = panel.position - Vector2(4, 4)
	border.size = panel.size + Vector2(8, 8)
	border.color = Color(0.95, 0.9, 0.8, 0.9)
	_over.add_child(border)
	var bg := ColorRect.new()
	bg.position = panel.position
	bg.size = panel.size
	bg.color = Color(0.07, 0.05, 0.12, 0.9)
	_over.add_child(bg)
	var x := panel.position.x
	var w := panel.size.x
	_over_cause = _label(_over, "", 24, Color(1.0, 0.5, 0.35), Vector2(x, 144), w)
	_label(_over, "SCORE", 16, Color(0.75, 0.72, 0.85), Vector2(x, 196), w)
	_over_score = _label(_over, "0", 64, GOLD, Vector2(x, 220), w)
	_over_score.add_theme_constant_override("outline_size", 16)
	_over_score.add_theme_color_override("font_shadow_color", Color(0.85, 0.3, 0.1))
	_over_score.add_theme_constant_override("shadow_offset_x", 6)
	_over_score.add_theme_constant_override("shadow_offset_y", 6)
	_over_stats = _label(_over, "", 16, TEXT, Vector2(x, 316), w)
	_over_stats.add_theme_constant_override("line_spacing", 4)
	_over_list = MenuList.new()
	_over_list.position = Vector2(x + 120, 440)
	_over_list.width = w - 240
	_over_list.row_h = 32.0
	_over_list.font_size = 16
	_over_list.delay = INPUT_DELAY
	_over_list.add_item("RIDE AGAIN", func() -> void: restart_requested.emit())
	_over_list.add_item("MAIN MENU", func() -> void: menu_requested.emit())
	_over.add_child(_over_list)

	# NEW BEST! badge straddling the board's top edge
	_over_best = Control.new()
	_over_best.position = Vector2(x + w / 2.0 - 136, panel.position.y - 26)
	_over_best.size = Vector2(272, 48)
	_over_best.pivot_offset = _over_best.size / 2.0
	_over.add_child(_over_best)
	var b_edge := ColorRect.new()
	b_edge.size = _over_best.size
	b_edge.color = OUTLINE
	_over_best.add_child(b_edge)
	var b_fill := ColorRect.new()
	b_fill.position = Vector2(4, 4)
	b_fill.size = _over_best.size - Vector2(8, 8)
	b_fill.color = Color(0.95, 0.3, 0.35)
	_over_best.add_child(b_fill)
	_label(_over_best, "NEW BEST!", 24, GOLD, Vector2(0, 12), _over_best.size.x)


## Studio card on black (above the fade overlay): CHONKY GAMES / PRESENTS.
func _build_splash() -> void:
	_splash = Control.new()
	_splash.size = VIEW
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_splash)
	_label(_splash, STUDIO, 40, GOLD, Vector2(0, 312), VIEW.x)
	_label(_splash, "PRESENTS", 16, TEXT, Vector2(0, 380), VIEW.x)


func _on_play() -> void:
	Sound.play("ui_start", Sound.note(0), -2.0, 0.0, 0.0, "Ui")
	_enter(State.ZOOM_IN)


## Settings / credits board over the window glass; the menu list hides until it closes.
func _open_board(page: SettingsMenu.Page) -> void:
	_board = SettingsMenu.new()
	_board.centre_x = 770.0
	_board.start_page = page
	_board.closed.connect(_close_board)
	_ui.add_child(_board)
	_menu_list.active = false


func _close_board() -> void:
	if _board:
		_board.queue_free()
		_board = null
	_menu_list.active = state == State.MENU


## Pixel-font label; width > 0 centres it in [x, x + width].
func _label(parent: Control, text: String, size: int, col: Color, pos: Vector2, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(size / 3, 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", maxi(size / 8, 2))
	l.add_theme_constant_override("shadow_offset_y", maxi(size / 8, 2))
	if width > 0.0:
		l.size.x = width
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


## The kid's family car, side view, front at +x. Origin = ground under the rear bumper. Drawn in
## 4 px art pixels.
class FamilyCar extends Node2D:
	const U := 4.0
	const REAR_WINDOW := Vector2(44 * U, -40 * U)   ## local centre of the rear door window (kid)
	const WHEEL_X := [22.0, 88.0]                   ## wheel centres, art px (rear, front)
	const WHEEL_Y := -8.0
	const WHEEL_R := 8.0                            ## art px
	const WELL := Color(0.09, 0.09, 0.11)           ## wheel colours: PixelArt.alloy_wheel
	var t := 0.0
	var spin := 0.0                                 ## wheel roll angle (Cabin derives it from road distance)
	var lights := false

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
		draw_rect(Rect2(x * U, y * U, w * U, h * U), c)

	func _poly(pts: Array, c: Color) -> void:
		var p := PackedVector2Array()
		for v in pts:
			p.append(v * U)
		PixelArt.poly(self, p, c, U)                     # stepped in whole art pixels, like the rects

	## Wheel-arch layer: half disc of radius r over wheel wx, closed flat at y = bottom (art px).
	func _arch(wx: float, r: float, c: Color, bottom := -7.0) -> void:
		var pts := [Vector2(wx - r, bottom)]
		for k in 13:
			pts.append(Vector2(wx, WHEEL_Y) + Vector2.from_angle(PI + k * PI / 12.0) * r)
		pts.append(Vector2(wx + r, bottom))
		_poly(pts, c)

	## Tyre + 5-spoke alloy rim, one art pixel at a time. Tread notches and spokes turn with `roll`; the
	## shading (light from the upper left) and the brake caliper stay put.
	func _wheel(wx: float, roll: float) -> void:
		PixelArt.alloy_wheel(self, Vector2(wx, WHEEL_Y) * U, WHEEL_R, roll, U)

	func _draw() -> void:
		var K := Color(0.06, 0.06, 0.08)
		var body := Color(0.22, 0.52, 0.6)
		var dark := body.darkened(0.3)
		var light := body.lightened(0.3)
		var inside := Color(0.16, 0.17, 0.24)
		var glass := Color(0.62, 0.78, 0.92, 0.35)
		_r(2, -1, 106, 2, Color(0, 0, 0, 0.35))                                   # ground shadow
		if lights:                                                                # headlight beam
			draw_polygon(PackedVector2Array([Vector2(110, -27) * U, Vector2(170, -32) * U,
				Vector2(170, -10) * U, Vector2(110, -24) * U]), PackedColorArray([Color(1.6, 1.5, 1.1, 0.35),
				Color(1.6, 1.5, 1.1, 0.0), Color(1.6, 1.5, 1.1, 0.0), Color(1.6, 1.5, 1.1, 0.35)]))
		var bob := -2.0 if fmod(t, 0.3) < 0.15 else 0.0                           # engine shake
		draw_set_transform(Vector2(0, bob))
		# roof rack
		_r(14, -53, 52, 2, K)
		_r(18, -51, 2, 2, K)
		_r(60, -51, 2, 2, K)
		# cabin
		var shell := PackedVector2Array()
		for v in [Vector2(3, -31), Vector2(7, -51), Vector2(71, -51), Vector2(90, -31)]:
			shell.append(v * U)
		PixelArt.poly_outlined(self, shell, body, K, U)
		_r(9, -50, 61, 1, light)                                                  # roof highlight
		# windows: dark interior, people, glass
		var rq := [Vector2(7, -33), Vector2(10, -47), Vector2(30, -47), Vector2(30, -33)]
		var fw := [Vector2(58, -47), Vector2(68, -47), Vector2(82, -33), Vector2(58, -33)]
		_poly(rq, inside)
		_r(33, -47, 22, 14, inside)
		_poly(fw, inside)
		draw_texture_rect(PixelArt.texture("kid_small", PackedStringArray(Cabin.KID_SMALL), Cabin.KID_PALETTE),
			Rect2(39 * U, -45 * U, 10 * U, 11 * U), false)
		_r(63, -45, 6, 9, Color(0.1, 0.1, 0.14))                                  # driver silhouette
		_r(64, -46, 4, 1, Color(0.1, 0.1, 0.14))
		_poly(rq, glass)
		_r(33, -47, 22, 14, glass)
		_poly(fw, glass)
		for gx in [14.0, 40.0, 64.0]:                                             # glare
			_poly([Vector2(gx, -34), Vector2(gx + 2, -34), Vector2(gx + 7, -46), Vector2(gx + 5, -46)],
				Color(1, 1, 1, 0.3))
		# lower body with stepped corners
		_r(2, -33, 106, 26, K)
		_r(1, -31, 108, 22, K)
		_r(3, -32, 104, 24, body)
		_r(2, -30, 106, 20, body)
		_r(3, -32, 104, 1, light)                                                 # shoulder line
		_r(2, -14, 106, 3, dark)                                                  # sill
		for sx in [31.0, 56.0]:                                                   # door seams + handles
			_r(sx, -31, 1, 18, dark)
			_r(sx + 3, -28, 4, 1, dark)
		for wx in WHEEL_X:                                                        # wheel arches
			_arch(wx, 12, light, -9)                                              # fender lip
			_arch(wx, 11, K)
			_arch(wx, 10, Color(0.18, 0.18, 0.21))                                # liner
			_arch(wx, 9, WELL)                                                    # well shadow
		_r(0, -16, 5, 4, Color(0.55, 0.56, 0.6))                                  # bumpers
		_r(105, -16, 5, 4, Color(0.55, 0.56, 0.6))
		var head := Color(2.2, 2.1, 1.6) if lights else Color(1.0, 0.95, 0.7)
		_r(106, -28, 3, 3, head)
		_r(1, -29, 2, 6, Color(2.0, 0.3, 0.2) if lights else Color(0.85, 0.15, 0.12))
		draw_set_transform(Vector2.ZERO)
		for wx in WHEEL_X:                                                        # wheels (don't bob)
			_wheel(wx, spin)


## Back-seat interior (after inspiration.jpg): dark cabin around a transparent, tilted door window (the
## live game world shows through it), kid leaning on the sill, seatbelt from the pillar, front-seat
## headrest on the right. COVER is a rect inside the window and clear of the kid/headrest: the zoom
## scales it up to cover the view.
class Interior extends Node2D:
	## Door-glass outline (clockwise) and per-corner rounding radius.
	const WINDOW_PTS := [Vector2(330, 104), Vector2(1150, 50), Vector2(1178, 526), Vector2(150, 532), Vector2(168, 300)]
	const WINDOW_RADII := [70.0, 24.0, 14.0, 14.0, 120.0]
	const COVER := Rect2(420, 140, 700, 340)
	const KID_POS := Vector2(180, 320)
	const KID_SCALE := 8.0
	const CELL := 4.0                         ## fabric dither pixel
	const K := Color(0.05, 0.05, 0.07)
	const FABRIC := Color(0.15, 0.15, 0.18)
	const FLECK := Color(0.21, 0.21, 0.25)
	const FABRIC_LIT := Color(0.31, 0.31, 0.36)   ## seat edges facing the window
	const SEAM := Color(0.08, 0.08, 0.1)
	const STITCH := Color(0.3, 0.3, 0.35)
	const PIPING := Color(0.25, 0.25, 0.3)
	const POCKET := Color(0.11, 0.11, 0.14)
	const POCKET_FLECK := Color(0.14, 0.14, 0.17)
	const CHROME := Color(0.5, 0.51, 0.57)
	const CHROME_HI := Color(0.86, 0.87, 0.92)
	const PLASTIC := Color(0.13, 0.13, 0.16)
	var t := 0.0
	var glass := 1.0                          ## reflections/tint on the glass, fades during the zoom
	static var _hole := PackedVector2Array()

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	static func hole() -> PackedVector2Array:
		if _hole.is_empty():
			_hole = rounded(WINDOW_PTS, WINDOW_RADII)
		return _hole

	## Outline pts with corner i rounded by radii[i] (quadratic bezier, whole px; 0 = sharp).
	static func rounded(pts: Array, radii: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		var n := pts.size()
		for i in n:
			var p: Vector2 = pts[i]
			var r: float = radii[i]
			if r <= 0.0:
				out.append(p)
				continue
			var a: Vector2 = pts[(i - 1 + n) % n]
			var b: Vector2 = pts[(i + 1) % n]
			var p0 := p + (a - p).normalized() * minf(r, p.distance_to(a) * 0.5)
			var p1 := p + (b - p).normalized() * minf(r, p.distance_to(b) * 0.5)
			for k in 9:
				var u := k / 8.0
				out.append(p0.lerp(p, u).lerp(p.lerp(p1, u), u).round())
		return out

	## Upholstered pad: convex outline pts on the CELL grid with a K edge, checker-dithered fabric, a lit
	## top row and lit edge on the window side, a shadowed edge on the other side, darker below shade_from.
	func _pad(pts: PackedVector2Array, base: Color, fleck: Color, lit_left: bool, shade_from := INF,
			lit := FABRIC_LIT) -> void:
		var rs := PixelArt.rows(pts, CELL)
		for i in rs.size():
			var r: Array = rs[i]
			var y: float = r[0]
			draw_rect(Rect2(r[1], y, r[2] - r[1], CELL), K)
			var s := PixelArt.inner_span(rs, i, CELL)
			if s.y <= s.x:
				continue
			var w := s.y - s.x
			var shade := 0.3 if y >= shade_from else (0.15 if y >= shade_from - CELL * 3.0 else 0.0)
			var b := base.darkened(shade)
			draw_rect(Rect2(s.x, y, w, CELL), b)
			var f := fleck.darkened(shade)
			var x := s.x + (CELL if int((s.x + y) / CELL) % 2 else 0.0)      # checker on the global grid
			while x < s.y:
				draw_rect(Rect2(x, y, CELL, CELL), f)
				x += CELL * 2.0
			if i == 1:                                                          # lit top roll
				draw_rect(Rect2(s.x, y, w, CELL), lit)
			elif i == 2:
				draw_rect(Rect2(s.x, y, w, CELL), lit.lerp(b, 0.55))
			var e := minf(CELL, w)
			var lit_x := s.x if lit_left else s.y - e
			var dim_x := s.y - e if lit_left else s.x
			draw_rect(Rect2(dim_x, y, e, CELL), b.darkened(0.35))
			draw_rect(Rect2(lit_x, y, e, CELL), lit)
			if w > CELL * 3.0:
				draw_rect(Rect2(lit_x + (CELL if lit_left else -CELL), y, e, CELL), lit.lerp(b, 0.5))

	## Straight seam a -> b (screen px): dark groove with a stitch line one cell beside it (below a
	## horizontal seam, right of a vertical one; side = -1 flips it). dashed = false: solid piping.
	func _seam(a: Vector2, b: Vector2, dashed := true, side := 1.0) -> void:
		PixelArt.line(self, a, b, SEAM, CELL, CELL)
		var off := (Vector2(0, CELL) if absf(b.x - a.x) > absf(b.y - a.y) else Vector2(CELL, 0)) * side
		var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)) / CELL)
		for k in range(0, steps + 1, 2 if dashed else 1):
			var p := (a.lerp(b, float(k) / maxi(steps, 1)) + off).snapped(Vector2(CELL, CELL))
			draw_rect(Rect2(p, Vector2(CELL, CELL)), STITCH if dashed else PIPING)

	## Chrome headrest post (2 cells wide) from y0 down into a seat top at y1, with its plastic collar.
	func _post(x: float, y0: float, y1: float) -> void:
		draw_rect(Rect2(x - CELL, y0, CELL * 4.0, y1 - y0), K)
		draw_rect(Rect2(x, y0, CELL * 2.0, y1 - y0), CHROME)
		draw_rect(Rect2(x, y0, CELL, y1 - y0), CHROME_HI)
		draw_rect(Rect2(x - CELL * 2.0, y1 - CELL * 2.0, CELL * 6.0, CELL * 4.0), K)
		draw_rect(Rect2(x - CELL, y1 - CELL, CELL * 4.0, CELL * 2.0), PLASTIC)
		draw_rect(Rect2(x - CELL, y1 - CELL, CELL * 4.0, CELL), PLASTIC.lightened(0.25))

	## Raindrops on the door glass (drawn before the door body, which covers anything outside the hole):
	## beads that sit and swell, then let go and run down, leaving a faint trail; heavy rain adds a mist of
	## tiny specks. Stateless (a function of t), on the 4 px CELL grid.
	func _rain_on_glass() -> void:
		var heavy := Weather.heavy()
		var n := 64 if heavy else 26
		var bead := Color(0.84, 0.92, 1.0, 0.3 * glass)
		var rim := Color(0.04, 0.06, 0.1, 0.32 * glass)
		var hi := Color(1, 1, 1, 0.65 * glass)
		var trail := Color(0.82, 0.9, 1.0, 0.1 * glass)
		var c4 := Vector2(CELL, CELL)
		if heavy:
			for i in 90:
				var p := Vector2(150.0 + _hr(i, 1) * 1030.0, 50.0 + _hr(i, 2) * 480.0).snapped(c4)
				draw_rect(Rect2(p, c4), Color(0.85, 0.92, 1.0, 0.16 * glass))
		for i in n:
			var period := 3.0 + _hr(i, 3) * 5.0
			var cyc := t / period + _hr(i, 4)
			var round_i := int(floorf(cyc))
			var u := cyc - round_i
			var x0 := 150.0 + _hr(i * 97 + round_i, 5) * 1030.0
			var y0 := 50.0 + _hr(i * 97 + round_i, 6) * 400.0
			var big := _hr(i, 7) < 0.4
			var y := y0
			var run_at := 0.6 + 0.25 * _hr(i, 8)
			if u > run_at:                                                 # let go: runs down, speeding up
				var k := (u - run_at) / (1.0 - run_at)
				y = y0 + k * k * (80.0 + _hr(i, 9) * 200.0)
				var wob := snappedf(sin(k * 9.0 + i) * CELL * 0.6, CELL)
				draw_rect(Rect2(Vector2(x0 + wob, y0).snapped(c4), Vector2(CELL, maxf(y - y0, CELL)).snapped(c4)), trail)
				x0 += wob
			var p := Vector2(x0, y).snapped(c4)
			var sz := CELL * (2.0 if big or u > run_at else 1.0)
			if u < 0.08:                                                    # just landed: a single speck
				sz = CELL
			draw_rect(Rect2(p, Vector2(sz, sz)), bead)
			draw_rect(Rect2(p + Vector2(0, sz), Vector2(sz, CELL)), rim)
			if sz > CELL:
				draw_rect(Rect2(p, c4), hi)

	func _hr(a: int, b: int) -> float:
		return float(absi(hash(Vector2i(a, b * 7919))) % 10000) / 10000.0

	func _draw() -> void:
		var frame := Color(0.21, 0.2, 0.24)
		var frame_lit := Color(0.29, 0.28, 0.33)
		var headliner := Color(0.31, 0.3, 0.34)
		var door := Color(0.17, 0.16, 0.2)
		var sill := Color(0.27, 0.26, 0.3)
		var h := hole()
		# glass: faint tint + sliding reflection streaks (clipped to the window)
		if glass > 0.0:
			draw_colored_polygon(h, Color(0.7, 0.85, 1.0, 0.07 * glass))
			for k in 2:
				var x := fposmod(k * 520.0 - t * 90.0, 1500.0) - 100.0
				var w := 60.0 if k == 0 else 26.0
				var streak := PackedVector2Array([Vector2(x + 140, 0), Vector2(x + 140 + w, 0),
					Vector2(x + w, 560), Vector2(x, 560)])
				for poly in Geometry2D.intersect_polygons(streak, h):
					draw_colored_polygon(poly, Color(1, 1, 1, 0.1 * glass))
			if Weather.active():
				_rain_on_glass()
		# body around the hole, in two halves (each half minus the window is a simple polygon);
		# extends well past the view so sway/zoom never shows an edge
		for half in [Rect2(-400, -400, 1060, 1520), Rect2(660, -400, 1100, 1520)]:
			var q := PackedVector2Array([half.position, Vector2(half.end.x, half.position.y), half.end,
				Vector2(half.position.x, half.end.y)])
			for poly in Geometry2D.clip_polygons(q, h):
				draw_colored_polygon(poly, frame)
		# headliner (roof lining) above the door frame, grab handle
		var lining := PackedVector2Array([Vector2(-400, -400), Vector2(1760, -400), Vector2(1760, -6),
			Vector2(1150, 10), Vector2(330, 64), Vector2(-400, 120)])
		draw_colored_polygon(lining, headliner)
		draw_polyline(PackedVector2Array([Vector2(-400, 120), Vector2(330, 64), Vector2(1150, 10), Vector2(1760, -6)]), K, 6.0)
		draw_rect(Rect2(600, 26, 140, 16), K)
		draw_rect(Rect2(604, 30, 132, 8), frame_lit)
		# door frame inner lip (lighter edge just outside the seal)
		var lip := h.duplicate()
		lip.append(h[0])
		draw_polyline(lip, frame_lit, 22.0)
		# door panel below the sill: armrest, handle recess, lock pin
		draw_rect(Rect2(-400, 566, 2160, 560), door)
		draw_rect(Rect2(-400, 528, 2160, 40), sill)
		draw_rect(Rect2(-400, 528, 2160, 4), frame_lit.lightened(0.15))
		draw_rect(Rect2(-400, 566, 2160, 4), K)
		draw_rect(Rect2(560, 652, 640, 34), sill)                     # armrest
		draw_rect(Rect2(560, 652, 640, 4), frame_lit.lightened(0.1))
		draw_rect(Rect2(560, 686, 640, 4), K)
		draw_rect(Rect2(940, 596, 130, 40), K)                        # handle recess
		draw_rect(Rect2(946, 602, 118, 28), Color(0.1, 0.1, 0.13))
		draw_rect(Rect2(958, 612, 70, 8), frame_lit)                  # lever
		draw_rect(Rect2(1110, 508, 12, 22), K)                        # lock pin
		draw_rect(Rect2(1112, 510, 8, 18), Color(0.5, 0.5, 0.55))
		# window seal
		draw_polyline(lip, K, 8.0)
		# rear seat behind the kid: pleated seat back lit from the window, low headrest on chrome posts
		_pad(rounded([Vector2(-80, 468), Vector2(236, 468), Vector2(240, 800), Vector2(-80, 800)],
			[0, 48, 0, 0]), FABRIC, FLECK, false, 640.0)
		_seam(Vector2(-80, 512), Vector2(196, 512))                                   # top roll
		for px in [28.0, 84.0, 140.0]:                                                # pleat channels
			_seam(Vector2(px, 520), Vector2(px, 800))
		_seam(Vector2(196, 488), Vector2(196, 800), false, -1.0)                      # side bolster
		_post(16, 444, 472)
		_post(96, 444, 472)
		_pad(rounded([Vector2(-40, 392), Vector2(136, 396), Vector2(132, 456), Vector2(-36, 456)],
			[32, 32, 20, 20]), FABRIC, FLECK, false, 440.0)
		# kid (breathing, blinking), then the seatbelt over the near shoulder
		var blink := fmod(t, 2.2) > 2.06
		var tex := Cabin.kid_texture(blink)
		var breathe := -4.0 if fmod(t, 1.4) > 0.7 else 0.0
		var kp := KID_POS + Vector2(0, breathe)
		draw_texture_rect(tex, Rect2(kp, tex.get_size() * KID_SCALE), false)
		var anchor := Vector2(80, 372)                                # on the pillar, above the headrest
		var shoulder := kp + Vector2(8, 21.5) * KID_SCALE
		draw_line(anchor, shoulder, K, 22.0)
		draw_line(anchor, shoulder, Color(0.3, 0.3, 0.36), 14.0)
		draw_line(anchor + Vector2(-2, 2), shoulder + Vector2(-2, 2), Color(0.4, 0.4, 0.47), 4.0)
		draw_rect(Rect2(anchor - Vector2(16, 20), Vector2(32, 40)), K)  # belt anchor
		draw_rect(Rect2(anchor - Vector2(12, 16), Vector2(24, 32)), Color(0.45, 0.45, 0.5))
		# front seat seen from behind, on the right in front of the window corner: seat back with side
		# bolster and map pocket, headrest on its post
		_pad(rounded([Vector2(1132, 536), Vector2(1400, 536), Vector2(1400, 800), Vector2(1132, 800)],
			[56, 0, 0, 0]), FABRIC, FLECK, true, 700.0)
		_seam(Vector2(1176, 584), Vector2(1176, 800), false, -1.0)                    # side bolster
		_seam(Vector2(1180, 584), Vector2(1400, 584))                                 # top panel
		_pad(rounded([Vector2(1196, 640), Vector2(1400, 640), Vector2(1400, 800), Vector2(1196, 800)],
			[12, 0, 0, 0]), POCKET, POCKET_FLECK, true, INF, FLECK)                   # map pocket
		_seam(Vector2(1200, 652), Vector2(1400, 652))                                 # elastic band
		_post(1204, 492, 540)
		_pad(rounded([Vector2(1164, 340), Vector2(1352, 340), Vector2(1344, 500), Vector2(1172, 500)],
			[40, 40, 24, 24]), FABRIC, FLECK, true, 468.0)
		_seam(Vector2(1176, 432), Vector2(1352, 432))
