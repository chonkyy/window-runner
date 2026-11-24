class_name TouchControls
extends CanvasLayer
## Phone controls (mobile, or `-- --touch` on desktop with the mouse standing in for a finger). On-screen
## 8-bit buttons on the left: DROP (bottom-left corner) with JUMP above it (hold = higher, press again in the
## air = double jump), and small PAUSE + RADIO buttons in the top-right corner. The rest of the screen
## (the whole right side) is the slice pad: tap anywhere = slice. Within the left button column a touch goes
## to the nearer of JUMP / DROP, so a sloppy thumb still hits one. Everything is injected as the normal input
## actions (Input.action_press/release), so gameplay code never knows. Only live during play (and to skip the
## splash / exterior shot); the menus handle their own taps (Cabin icons, MenuList touch-as-mouse). Held
## actions are released on pause, focus loss and game over. Android back: pause in play, `menu_back`
## everywhere else (Game._notification). Button art: `draw_button` (also used by Cabin's menu icons).

const PX := 4.0                            ## button art pixel
const BTN := 128.0                         ## JUMP and DROP (same size)
const SMALL_BTN := 80.0
const MARGIN := 24.0                       ## PAUSE / RADIO from the top-right corner
const EDGE_X := 88.0                       ## JUMP / DROP from the left edge (clear of curved screen edges)
const EDGE_Y := 56.0                       ## DROP from the bottom edge
const ZONE_W := 360.0                      ## left button column: touches here go to JUMP / DROP
const HINT_TIME := 6.0                     ## first run: how long the slice hint shows (or until 3 slices)
const COL := Color(1.0, 0.97, 0.9)

## Square icons (11x11, the gear 13x13), drawn at PX * scale per art pixel by draw_button.
const ICONS := {
	"jump": [
		".....#.....",
		"....###....",
		"...#####...",
		"..#######..",
		".#########.",
		"###########",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
	],
	"drop": [
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"....###....",
		"###########",
		".#########.",
		"..#######..",
		"...#####...",
		"....###....",
		".....#.....",
	],
	"pause": [
		"...........",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"..###.###..",
		"...........",
	],
	"radio": [
		"........#..",
		".......#...",
		"......#....",
		".....#.....",
		"###########",
		"#.#.#######",
		"##.##.....#",
		"#.#.#.....#",
		"##.##.....#",
		"#.#.#######",
		"###########",
	],
	"home": [
		".....#.....",
		"....###....",
		"...#####...",
		"..#######..",
		".#########.",
		"###########",
		".#########.",
		".###...###.",
		".###...###.",
		".###...###.",
		".###...###.",
	],
	"settings": [                          # gear, 13x13 (8 teeth, round hole)
		".....###.....",
		".##..###..##.",
		".###########.",
		"..#########..",
		"..####.####..",
		"#####...#####",
		"####.....####",
		"#####...#####",
		"..####.####..",
		"..#########..",
		".###########.",
		".##..###..##.",
		".....###.....",
	],
}

static var enabled := false                ## set by setup(): phone, or `--touch`

var game: Node                             ## Game (cabin, game_over)
var _touches := {}                         ## touch index -> action held by that finger
var _releases := {}                        ## action -> physics frame it was pressed (released one frame later)
var _art: Control
var _hint: Label
var _hint_t := -1.0
var _hint_slices := 0


static func setup() -> void:
	enabled = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	if OS.get_cmdline_user_args().has("--touch"):
		Input.emulate_touch_from_mouse = true      # desktop test: the left mouse button is a finger


## 8-bit button: chamfered grey square on the PX grid (low opacity, brighter while held) with an ICONS glyph.
## `solid`: the menu style (Cabin.MenuIcons) — opaque dark plate, cream edge, gold icon.
static func draw_button(ci: CanvasItem, b: Rect2, icon: String, held := false, solid := false) -> void:
	var a := 1.6 if held else 1.0
	var fill := Color(0.5, 0.5, 0.55, 0.22 * a)
	var edge := Color(0.82, 0.82, 0.86, 0.38 * a)
	var ink := Color(0.95, 0.95, 0.98, 0.5 * a)
	var shadow := Color(0.05, 0.05, 0.08, 0.3 * a)
	if solid:
		fill = Color(0.07, 0.05, 0.12, 0.92)
		edge = Color(0.95, 0.9, 0.8)
		ink = MenuList.GOLD
		shadow = Color(0.0, 0.0, 0.0, 0.6)
	var p := b.position
	var s := b.size
	var c := PX * 2.0                              # cut corners: two art pixels
	ci.draw_rect(Rect2(p + Vector2(c, PX), Vector2(s.x - c * 2.0, s.y - PX * 2.0)), fill)
	ci.draw_rect(Rect2(p + Vector2(PX, c), Vector2(PX, s.y - c * 2.0)), fill)
	ci.draw_rect(Rect2(p + Vector2(s.x - PX * 2.0, c), Vector2(PX, s.y - c * 2.0)), fill)
	ci.draw_rect(Rect2(p + Vector2(c, 0), Vector2(s.x - c * 2.0, PX)), edge)                  # top
	ci.draw_rect(Rect2(p + Vector2(c, s.y - PX), Vector2(s.x - c * 2.0, PX)), edge)           # bottom
	ci.draw_rect(Rect2(p + Vector2(0, c), Vector2(PX, s.y - c * 2.0)), edge)                  # left
	ci.draw_rect(Rect2(p + Vector2(s.x - PX, c), Vector2(PX, s.y - c * 2.0)), edge)           # right
	for corner in [Vector2(PX, PX), Vector2(s.x - PX * 2.0, PX), Vector2(PX, s.y - PX * 2.0),
			Vector2(s.x - PX * 2.0, s.y - PX * 2.0)]:
		ci.draw_rect(Rect2(p + corner, Vector2(PX, PX)), edge)                                # diagonal step
	var rows: Array = ICONS[icon]
	var g := maxf(floorf(s.x * 0.5 / rows.size() / PX), 1.0) * PX                             # icon ~half the button
	var o := (p + (s - Vector2(rows.size(), rows.size()) * g) / 2.0).snapped(Vector2(PX, PX))
	for y in rows.size():
		var row: String = rows[y]
		var x := 0
		while x < row.length():                    # one rect per horizontal run
			if row[x] != "#":
				x += 1
				continue
			var x0 := x
			while x < row.length() and row[x] == "#":
				x += 1
			var r := Rect2(o + Vector2(x0, y) * g, Vector2(x - x0, 1) * g)
			ci.draw_rect(Rect2(r.position + Vector2(PX, PX), r.size), shadow)
			ci.draw_rect(r, ink)


func _ready() -> void:
	layer = 11                                     # just above the HUD (10), under the cabin (20)
	process_mode = Node.PROCESS_MODE_ALWAYS        # sees the pause so it can let go of held actions
	_art = Buttons.new()
	_art.owner_tc = self
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.size = View.size()
	add_child(_art)
	if not Settings.touch_hint_seen:
		var half := View.w() / 2.0
		_hint = Label.new()
		_hint.text = "TAP RIGHT SIDE\nTO SLICE!"
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.add_theme_font_size_override("font_size", 24)
		_hint.add_theme_color_override("font_color", COL)
		_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
		_hint.add_theme_constant_override("outline_size", 8)
		_hint.add_theme_constant_override("line_spacing", 16)
		_hint.position = Vector2(half, 160)
		_hint.size = Vector2(half, 64)
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint.modulate.a = 0.0
		add_child(_hint)


## Live play (or a skippable intro shot): touches drive the game. Otherwise they're just mouse clicks.
func _live() -> bool:
	if game == null or game.cabin == null or get_tree().paused:
		return false
	var s: int = game.cabin.state
	if s == Cabin.State.SPLASH or s == Cabin.State.EXTERIOR:
		return true
	return s == Cabin.State.PLAY and not game.game_over and not game._restarting


func _playing() -> bool:
	return _live() and game.cabin.state == Cabin.State.PLAY


func _input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch:
		return
	var e := event as InputEventScreenTouch
	if e.pressed:
		if _live():
			_touch_down(e.index, e.position)
	else:
		_touch_up(e.index)


func _touch_down(i: int, p: Vector2) -> void:
	get_viewport().set_input_as_handled()
	if not _playing():
		_tap("jump")                               # intro: any touch skips
		return
	var act := action_at(p)
	if act == "pause" or act == "radio":
		_tap(act)
	elif act == "slice":
		_tap("slice")
		_hint_slices += 1
	else:                                          # jump / drop: held while the finger stays down
		_touches[i] = act
		_press(act)                                # another finger already holding it: re-press (double jump)


func _touch_up(i: int) -> void:
	if not _touches.has(i):
		return
	var act: String = _touches[i]
	_touches.erase(i)
	if not act in _touches.values():
		Input.action_release(act)


## What a touch at p does: a button name, or "slice" (everything off the buttons).
func action_at(p: Vector2) -> String:
	var r := button_rects()
	for k in ["pause", "radio"]:
		if (r[k] as Rect2).grow(12.0).has_point(p):
			return k
	var jump: Rect2 = r.jump
	if p.x < ZONE_W and p.y >= jump.position.y - 48.0:
		var drop: Rect2 = r.drop
		return "jump" if p.distance_to(jump.get_center()) <= p.distance_to(drop.get_center()) else "drop"
	return "slice"


## Press now, released one physics frame later (a press and release in the same frame wouldn't register).
func _tap(action: String) -> void:
	_press(action)
	_releases[action] = Engine.get_physics_frames()


func _press(action: String) -> void:
	if Input.is_action_pressed(action):
		Input.action_release(action)
	Input.action_press(action)
	_releases.erase(action)


func _physics_process(_delta: float) -> void:
	var f := Engine.get_physics_frames()
	for a in _releases.keys():
		if f > _releases[a] + 1:
			Input.action_release(a)
			_releases.erase(a)
	if not _live() and not _touches.is_empty():
		release_all()


func _process(delta: float) -> void:
	_art.visible = _playing()
	if _art.visible:
		_art.queue_redraw()                        # held states
	if _hint:
		_update_hint(delta)


func _update_hint(delta: float) -> void:
	if _hint_t < 0.0:
		if not _playing():
			return
		_hint_t = 0.0
		_hint_slices = 0
	if not _playing():                             # died / paused early: hide, show again next round
		_hint.modulate.a = 0.0
		_hint_t = -1.0
		return
	_hint_t += delta
	var out := _hint_t >= HINT_TIME or _hint_slices >= 3
	var target := 0.0 if out else (1.0 if fmod(_hint_t, 1.0) < 0.75 else 0.35)   # slow blink
	_hint.modulate.a = move_toward(_hint.modulate.a, target, delta * 4.0)
	if out and _hint.modulate.a <= 0.0:
		_hint.queue_free()
		_hint = null
		Settings.touch_hint_seen = true
		Settings.save()


func release_all() -> void:
	for a in ["jump", "slice", "drop", "pause", "radio"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	_touches.clear()
	_releases.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		release_all()


## Button rects in canvas px: DROP in the bottom-left corner, JUMP above it, PAUSE in the top-right corner
## with RADIO to its left (the radio toast drops below them, Game._station_toast).
func button_rects() -> Dictionary:
	var h := View.BASE.y
	var drop := Rect2(EDGE_X, h - EDGE_Y - BTN, BTN, BTN)
	var jump := Rect2(EDGE_X, drop.position.y - 24.0 - BTN, BTN, BTN)
	var px := View.w() - MARGIN - SMALL_BTN
	return {
		"jump": jump, "drop": drop,
		"pause": Rect2(px, MARGIN, SMALL_BTN, SMALL_BTN),
		"radio": Rect2(px - 16.0 - SMALL_BTN, MARGIN, SMALL_BTN, SMALL_BTN),
	}


class Buttons extends Control:
	var owner_tc: TouchControls

	func _draw() -> void:
		var r := owner_tc.button_rects()
		for k in r:
			TouchControls.draw_button(self, r[k], k, Input.is_action_pressed(k))
