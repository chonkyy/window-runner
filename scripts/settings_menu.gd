class_name SettingsMenu
extends Control
## Settings board (volumes, window, accessibility) with CONTROLS and CREDITS sub-pages, drawn like the game-over
## board. Used from the start menu (over the car window) and the pause menu. Every change is applied and saved
## right away. Emits `closed` on BACK / Esc / pad B from the top page.

signal closed

enum Page { SETTINGS, CONTROLS, CREDITS }

const W := 640.0
const H := 600.0
const CONTROLS := [
	["JUMP", "SPACE / W / UP"], ["DOUBLE JUMP", "JUMP IN THE AIR"], ["SLICE", "J / X"], ["DROP", "S / DOWN"],
	["RADIO", "R"], ["PAUSE", "ESC / P"], ["MUTE", "M"], ["FULLSCREEN", "F11"],
]
const PAD := [["JUMP", "A"], ["SLICE", "X"], ["DROP", "B"], ["RADIO", "Y"], ["PAUSE", "START"]]
const TOUCH := [["JUMP", "UP BUTTON (HOLD)"], ["DOUBLE JUMP", "UP AGAIN IN AIR"], ["DROP", "DOWN BUTTON"],
	["SLICE", "TAP RIGHT SIDE"], ["RADIO", "RADIO BUTTON"], ["PAUSE", "PAUSE / BACK"]]
## Phones: no window options (always fullscreen, the system owns vsync).
static var _window_opts := not OS.has_feature("mobile")

var centre_x := 640.0                     ## board centre (screen px)
var start_page := Page.SETTINGS
var _list: MenuList
var _title: Label
var _page := Page.SETTINGS
var _from := -1                           ## SETTINGS row that opened the current sub-page (BACK reselects it)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var at := Vector2(roundf(centre_x - W / 2.0), (View.BASE.y - H) / 2.0)
	var border := ColorRect.new()
	border.position = at - Vector2(4, 4)
	border.size = Vector2(W, H) + Vector2(8, 8)
	border.color = Color(0.95, 0.9, 0.8, 0.9)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	var bg := ColorRect.new()
	bg.position = at
	bg.size = Vector2(W, H)
	bg.color = Color(0.07, 0.05, 0.12, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_title = Label.new()
	_title.position = at + Vector2(0, 28)
	_title.size = Vector2(W, 32)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", MenuList.GOLD)
	_title.add_theme_color_override("font_outline_color", MenuList.OUTLINE)
	_title.add_theme_constant_override("outline_size", 8)
	add_child(_title)
	_list = MenuList.new()
	_list.position = at + Vector2(64, 84)
	_list.width = W - 128.0
	_list.row_h = 38.0
	_list.font_size = 16
	_list.centred = false
	_list.back.connect(_on_back)
	add_child(_list)
	_show(start_page)


func _on_back() -> void:
	if _page == Page.SETTINGS or start_page != Page.SETTINGS:
		closed.emit()
	else:
		_show(Page.SETTINGS, _from)


func _show(p: Page, select := -1) -> void:
	_page = p
	_list.clear()
	match p:
		Page.SETTINGS:
			_title.text = "SETTINGS"
			_list.add_slider("MASTER", _vol_get.bind("Master"), _vol_set.bind("Master"))
			_list.add_slider("MUSIC", _vol_get.bind("Music"), _vol_set.bind("Music"))
			_list.add_slider("SOUND FX", _vol_get.bind("Sfx"), _vol_set.bind("Sfx"))
			_list.add_slider("STREET", _vol_get.bind("World"), _vol_set.bind("World"))
			_list.add_toggle("MUTE", func() -> bool: return Settings.muted, func(v: bool) -> void: Sound.set_muted(v))
			if _window_opts:
				_list.add_toggle("FULLSCREEN", func() -> bool: return Settings.fullscreen, _flag.bind("fullscreen"))
				_list.add_toggle("VSYNC", func() -> bool: return Settings.vsync, _flag.bind("vsync"))
			_list.add_toggle("SCREEN SHAKE", func() -> bool: return Settings.shake, _flag.bind("shake"))
			_list.add_toggle("FLASHES", func() -> bool: return Settings.flashes, _flag.bind("flashes"))
			_list.add_item("CONTROLS", _sub.bind(Page.CONTROLS))
			if TouchControls.enabled:             # phones: no CREDITS on the start menu, it lives here
				_list.add_item("CREDITS", _sub.bind(Page.CREDITS))
			_list.add_item("RESET DEFAULTS", _reset)
			_list.add_item("BACK", func() -> void: closed.emit())
		Page.CONTROLS:
			_title.text = "CONTROLS"
			if TouchControls.enabled:
				_list.add_text("TOUCH", 16, MenuList.GOLD, 30.0)
				for c in TOUCH:
					_list.add_text(_pair(c[0], c[1]), 16, MenuList.TEXT, 30.0)
				_list.add_gap(10.0)
				_list.add_text("GAMEPAD", 16, MenuList.GOLD, 30.0)
				for c in PAD:
					_list.add_text(_pair(c[0], c[1]), 16, MenuList.TEXT, 28.0)
				_list.add_gap(8.0)
				_list.add_item("BACK", _on_back)
				_finish(select)
				return
			for c in CONTROLS:
				_list.add_text(_pair(c[0], c[1]), 16, MenuList.TEXT, 30.0)
			_list.add_gap(10.0)
			_list.add_text("GAMEPAD", 16, MenuList.GOLD, 30.0)
			for c in PAD:
				_list.add_text(_pair(c[0], c[1]), 16, MenuList.TEXT, 28.0)
			_list.add_gap(8.0)
			_list.add_item("BACK", _on_back)
		Page.CREDITS:
			_title.text = "CREDITS"
			for line in [["WINDOW RUNNER", MenuList.GOLD], ["A CHONKY GAMES GAME", MenuList.TEXT], ["", null],
					["ART, MUSIC + SOUND", MenuList.GOLD], ["MADE IN CODE", MenuList.TEXT], ["", null],
					["FONT", MenuList.GOLD], ["PRESS START 2P BY CODEMAN38", MenuList.TEXT], ["(SIL OPEN FONT LICENSE)", MenuList.DIM],
					["", null], ["HORNS + VOICES", MenuList.GOLD], ["CC0 RECORDINGS FROM FREESOUND", MenuList.TEXT],
					["(SEE AUDIO/CREDITS.MD)", MenuList.DIM], ["", null],
					["MADE WITH GODOT ENGINE", MenuList.DIM]]:
				if line[1] == null:
					_list.add_gap(12.0)
				else:
					_list.add_text(line[0], 16, line[1], 28.0)
			_list.add_gap(8.0)
			_list.add_item("BACK", _on_back)
	_finish(select)


func _sub(p: Page) -> void:
	_from = _list._sel
	_show(p)


func _finish(select: int) -> void:
	if select >= 0:
		_list.select(select)
	_list.active = true


## "JUMP ........ SPACE" padded to the column (the pixel font is monospaced: 16 px per glyph at size 16).
func _pair(a: String, b: String) -> String:
	var cols := int(_list.width / 16.0)
	return a + " ".repeat(maxi(cols - a.length() - b.length(), 1)) + b


func _vol_get(slider: String) -> int:
	return Settings.vol[slider]


func _vol_set(v: int, slider: String) -> void:
	Settings.vol[slider] = v
	Sound.apply_volumes()
	Settings.save()


func _flag(v: bool, key: String) -> void:
	match key:
		"fullscreen": Settings.fullscreen = v
		"vsync": Settings.vsync = v
		"shake": Settings.shake = v
		"flashes": Settings.flashes = v
	Settings.apply()
	Settings.save()


func _reset() -> void:
	Settings.reset()
	Settings.apply()
	Settings.save()
	_show(Page.SETTINGS, _list._sel)
