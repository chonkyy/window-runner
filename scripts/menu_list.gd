class_name MenuList
extends Control
## One column of menu rows in the pixel font: items (call back), sliders (0..Settings.STEPS, Left/Right) and
## toggles (ON/OFF), plus plain text rows. Keyboard, pad and mouse. Reads Input in _process, so it also works while
## the tree is paused (the owner gives it process_mode ALWAYS). Emits `back` on Esc / Backspace / pad B.
## Actions (menu_up/down/left/right/ok/back) are registered in Game._setup_input.

signal back

const INPUT_DELAY := 0.2                  ## ignore presses this long after (re)activation
const REPEAT_DELAY := 0.35                ## held direction: first repeat after this...
const REPEAT_RATE := 0.07                 ## ...then this often
const TEXT := Color(1.0, 0.98, 0.92)
const GOLD := Color(1.0, 0.82, 0.3)
const DIM := Color(0.62, 0.6, 0.74)
const OUTLINE := Color(0.06, 0.04, 0.1)
const PIP := Vector2(12, 20)              ## slider pip (even sizes: pixel grid)
const PIP_GAP := 4

var width := 560.0
var row_h := 44.0
var font_size := 24
var delay := INPUT_DELAY                  ## this list's guard after (re)activation
var centred := true                       ## item text centred in the column (value rows are always left/right)
var active := true:
	set(v):
		active = v
		_t = 0.0
		_refresh()

var _rows: Array = []                     ## {kind, text, cb, getter, setter, lbl: Label, val: Label, y}
var _sel := -1
var _t := 0.0
var _clock := 0.0
var _hold := {}
var _cursor: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor = _make_label(">", font_size, GOLD)
	add_child(_cursor)
	_refresh()


func clear() -> void:
	for r in _rows:
		r.lbl.queue_free()
		if r.val:
			r.val.queue_free()
	_rows.clear()
	_sel = -1
	_t = 0.0
	queue_redraw()


func add_item(text: String, cb: Callable) -> void:
	_add({"kind": "item", "text": text, "cb": cb})


## get() -> int in 0..Settings.STEPS, set(int)
func add_slider(text: String, getter: Callable, setter: Callable) -> void:
	_add({"kind": "slider", "text": text, "getter": getter, "setter": setter})


## get() -> bool, set(bool)
func add_toggle(text: String, getter: Callable, setter: Callable) -> void:
	_add({"kind": "toggle", "text": text, "getter": getter, "setter": setter})


## Non-selectable line (headings, credits, control lists). h = row height (0 = row_h).
func add_text(text: String, size := 16, col := DIM, h := 0.0) -> void:
	_add({"kind": "text", "text": text, "sz": size, "col": col, "h": h if h > 0.0 else row_h})


func add_gap(h: float) -> void:
	_add({"kind": "gap", "text": "", "h": h})


func height() -> float:
	if _rows.is_empty():
		return 0.0
	var last: Dictionary = _rows[-1]
	return last.y + last.get("h", row_h)


func _add(r: Dictionary) -> void:
	r.y = height()
	var size: int = r.get("sz", font_size)
	r.lbl = _make_label(r.text, size, r.get("col", TEXT))
	r.lbl.position = Vector2(0, r.y)
	r.lbl.size = Vector2(width, r.get("h", row_h))
	var valued: bool = r.kind == "slider" or r.kind == "toggle"
	if (centred and not valued) or r.kind == "text":
		r.lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.val = null
	if r.kind == "toggle":
		r.val = _make_label("", font_size, TEXT)
		r.val.position = Vector2(0, r.y)
		r.val.size = Vector2(width, row_h)
		r.val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(r.val)
	add_child(r.lbl)
	_rows.append(r)
	if _sel < 0 and _selectable(_rows.size() - 1):
		_sel = _rows.size() - 1
	_refresh()


func _make_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(size / 3, 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", maxi(size / 8, 2))
	l.add_theme_constant_override("shadow_offset_y", maxi(size / 8, 2))
	return l


func _selectable(i: int) -> bool:
	return i >= 0 and i < _rows.size() and _rows[i].kind != "text" and _rows[i].kind != "gap"


func select(i: int) -> void:
	if _selectable(i):
		_sel = i
		_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if _cursor and _sel >= 0:                      # cursor nudges toward the item
		_cursor.position.x = _cursor_x() + (4.0 if fmod(_clock, 0.6) < 0.3 else 0.0)
	if not is_visible_in_tree() or not active:
		return
	_t += delta
	if _t < delay:
		return
	if _repeat("menu_up", delta):
		_move(-1)
	elif _repeat("menu_down", delta):
		_move(1)
	elif _repeat("menu_left", delta):
		_change(-1)
	elif _repeat("menu_right", delta):
		_change(1)
	elif Input.is_action_just_pressed("menu_ok"):
		_activate()
	elif Input.is_action_just_pressed("menu_back"):
		Sound.play("ui_back", 1.0, -6.0, 0.0, 0.0, "Ui")
		back.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not active or _t < delay:
		return
	if not (event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed)):
		return
	var p := get_global_mouse_position() - global_position
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if not _selectable(i) or p.y < r.y or p.y >= r.y + row_h or p.x < -48.0 or p.x > width + 48.0:
			continue
		if i != _sel:
			_sel = i
			_tick(0)
			_refresh()
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if r.kind == "slider":
					var x0 := width - _pips_w()
					if p.x >= x0 - PIP_GAP:
						_set_slider(r, clampi(int((p.x - x0) / (PIP.x + PIP_GAP)) + 1, 0, Settings.STEPS))
				else:
					_activate()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change(1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change(-1)
			get_viewport().set_input_as_handled()
		return


func _repeat(action: String, delta: float) -> bool:
	if Input.is_action_just_pressed(action):
		_hold[action] = 0.0
		return true
	if not Input.is_action_pressed(action):
		_hold.erase(action)
		return false
	var h: float = _hold.get(action, 0.0) + delta
	_hold[action] = h
	if h >= REPEAT_DELAY:
		_hold[action] = REPEAT_DELAY - REPEAT_RATE
		return true
	return false


func _move(d: int) -> void:
	if _sel < 0:
		return
	var i := _sel
	for k in _rows.size():
		i = posmod(i + d, _rows.size())
		if _selectable(i):
			break
	if i != _sel:
		_sel = i
		_tick(0)
		_refresh()


func _change(d: int) -> void:
	if _sel < 0:
		return
	var r: Dictionary = _rows[_sel]
	if r.kind == "slider":
		_set_slider(r, clampi(int(r.getter.call()) + d, 0, Settings.STEPS))
	elif r.kind == "toggle":
		_activate()


func _set_slider(r: Dictionary, v: int) -> void:
	if v == int(r.getter.call()):
		return
	r.setter.call(v)
	_tick(v)
	_refresh()


func _activate() -> void:
	if _sel < 0:
		return
	var r: Dictionary = _rows[_sel]
	match r.kind:
		"item":
			Sound.play("confirm", Sound.note(0), -4.0, 0.0, 0.0, "Ui")
			r.cb.call()
		"toggle":
			r.setter.call(not bool(r.getter.call()))
			Sound.play("confirm", Sound.note(2 if r.getter.call() else 0), -6.0, 0.0, 0.0, "Ui")
	_refresh()


func _tick(step: int) -> void:
	Sound.play("ui_tick", Sound.note(step), -9.0, 0.0, 0.0, "Ui")


func _pips_w() -> float:
	return Settings.STEPS * (PIP.x + PIP_GAP) - PIP_GAP


func _cursor_x() -> float:
	if _sel < 0:
		return 0.0
	var r: Dictionary = _rows[_sel]
	var x := -40.0
	if r.lbl.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		var font: Font = r.lbl.get_theme_font("font")
		x = (width - font.get_string_size(r.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) / 2.0 - 40.0
	return x


func _refresh() -> void:
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if not _selectable(i):
			continue
		var on := i == _sel and active
		r.lbl.add_theme_color_override("font_color", GOLD if on else TEXT)
		if r.kind == "toggle":
			r.val.text = "ON" if r.getter.call() else "OFF"
			r.val.add_theme_color_override("font_color", GOLD if on else (TEXT if r.getter.call() else DIM))
	if _cursor:
		_cursor.visible = _sel >= 0 and active
		if _sel >= 0:
			_cursor.position = Vector2(_cursor_x(), _rows[_sel].y)
			_cursor.size = Vector2(32, row_h)
	queue_redraw()


func _draw() -> void:
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if r.kind != "slider":
			continue
		var on := i == _sel and active
		var v := int(r.getter.call())
		var x0 := width - _pips_w()
		var y: float = r.y + (row_h - PIP.y) / 2.0
		for k in Settings.STEPS:
			var rect := Rect2(x0 + k * (PIP.x + PIP_GAP), y, PIP.x, PIP.y)
			draw_rect(rect.grow(2.0), OUTLINE)
			var col := (GOLD if on else TEXT) if k < v else Color(0.3, 0.28, 0.4)
			draw_rect(rect, col)
