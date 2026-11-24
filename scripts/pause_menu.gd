class_name PauseMenu
extends CanvasLayer
## Pause overlay (Game._pause): dims the frozen world, PAUSED + RESUME / RESTART / SETTINGS / MAIN MENU. Runs
## while the tree is paused. Esc / P / pad Start or B resumes.

signal resumed
signal restart
signal main_menu

var _list: MenuList
var _title: Label
var _hint: Label
var _board: SettingsMenu
var _t := 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.08, 0.62)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_title = _label("PAUSED", 40, MenuList.GOLD, 200)
	_list = MenuList.new()
	_list.position = Vector2(400, 300)
	_list.width = 480
	_list.add_item("RESUME", _resume)
	_list.add_item("RESTART", func() -> void: restart.emit())
	_list.add_item("SETTINGS", _open_settings)
	_list.add_item("MAIN MENU", func() -> void: main_menu.emit())
	_list.back.connect(_resume)
	add_child(_list)
	_hint = _label("%s  %s" % Radio.label(), 16, MenuList.DIM, 600)
	Sound.play("ui_back", 1.0, -6.0, 0.0, 0.0, "Ui")


func _label(text: String, size: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(1280, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", MenuList.OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(size / 3, 6))
	add_child(l)
	return l


func _process(delta: float) -> void:
	_t += delta
	_title.modulate.a = 0.75 + 0.25 * sin(_t * 4.0)
	if _board == null and _t > MenuList.INPUT_DELAY and Input.is_action_just_pressed("pause"):
		_resume()


func _resume() -> void:
	resumed.emit()


func _open_settings() -> void:
	_board = SettingsMenu.new()
	_board.centre_x = 640.0
	_board.closed.connect(_close_settings)
	add_child(_board)
	_list.visible = false
	_list.active = false
	_title.visible = false
	_hint.visible = false


func _close_settings() -> void:
	_board.queue_free()
	_board = null
	_list.visible = true
	_list.active = true
	_list.select(2)
	_title.visible = true
	_hint.visible = true
