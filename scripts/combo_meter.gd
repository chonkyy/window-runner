class_name ComboMeter
extends Control
## HUD combo counter under the score (Game owns the count and timer; this only shows them).
## Shows from x2: big tier-coloured count + "COMBO" tag, a draining pixel timer bar (`left`), punch + sparks on
## every bump, a milestone word + ring flash, shake/blink when the timer runs low, and a tip-over fall on drop.
## All motion runs in _process on its own timers (no tweens), drawn on `_root` so it fades as one.

const TIERS := [                               # [from combo, colour]
	[2, Color(0.55, 0.95, 1.0)],               # cyan (slice colour)
	[5, Color(1.0, 0.9, 0.35)],                # gold (hop colour)
	[10, Color(1.0, 0.6, 0.2)],                # orange
	[20, Color(1.0, 0.35, 0.6)],               # pink, shimmers
]
const MILESTONES := {5: "NICE!", 10: "GREAT!", 15: "WILD!", 20: "INSANE!"}   # then "NINJA!!" every 10 from 30
const GREY := Color(0.6, 0.6, 0.66)
const OUTLINE := Color(0.05, 0.05, 0.1)
const BAR_Y := 46.0
const BAR_W := 160.0
const BAR_H := 12.0
const CELL := 4.0
const WARN := 0.3                              ## timer fraction under which the bar blinks and the count shakes
const DROP_TIME := 0.55
const WORD_TIME := 0.95

var left := 1.0                                ## timer fraction 0..1, set by Game every frame

var _n := 0
var _root: Control
var _count: Label
var _tag: Label
var _word: Label
var _t := 0.0
var _punch := 0.0
var _flash := 0.0
var _ring := 0.0
var _word_t := -1.0
var _drop_t := -1.0
var _frozen := false
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_root = Control.new()
	_root.mouse_filter = MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	_root.draw.connect(_draw_root)
	add_child(_root)
	_count = _label(32)
	_tag = _label(16)
	_tag.text = "COMBO"
	_word = _label(16)
	_word.visible = false


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", maxi(size / 3, 8))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	_root.add_child(l)
	return l


## The combo went up to n (shown from 2).
func bump(n: int) -> void:
	if _frozen:
		return
	_n = n
	if n < 2:
		return
	_drop_t = -1.0
	_count.rotation = 0.0
	_count.text = "x%d" % n
	_count.add_theme_font_size_override("font_size", 40 if n >= 10 else 32)
	_count.reset_size()
	_tag.reset_size()
	_punch = 1.0
	_flash = 1.0
	var tier := _tier(n)
	for k in 3 + tier:
		_spark()
	var word := _milestone(n)
	if word != "":
		_word.text = word
		_word.reset_size()
		_word.visible = true
		_word_t = 0.0
		_ring = 1.0
		_punch = 1.4
		for k in 8:
			_spark()
		Sound.play("score_punch", Sound.note(2 + tier * 2), -6.0, 0.0, 0.0, "Ui")


## The timer ran out: the count goes grey and tips over.
func drop() -> void:
	if _n >= 2 and not _frozen:
		_drop_t = 0.0
		Sound.play("ui_back", 0.8, -10.0, 0.0, 0.0, "Ui")
	_n = 0


## Run over: hold still (Game fades it with the score).
func freeze() -> void:
	_frozen = true


func _tier(n: int) -> int:
	var t := 0
	for i in TIERS.size():
		if n >= int(TIERS[i][0]):
			t = i
	return t


func _milestone(n: int) -> String:
	if MILESTONES.has(n):
		return MILESTONES[n]
	return "NINJA!!" if n >= 30 and n % 10 == 0 else ""


func _colour() -> Color:
	var tier := _tier(maxi(_n, 2))
	var c: Color = TIERS[tier][1]
	if tier == TIERS.size() - 1:                 # top tier: hue shimmer
		c = c.lerp(Color.from_hsv(fposmod(_t * 0.7, 1.0), 0.5, 1.0), 0.45)
	return c


func _spark() -> void:
	var a := randf_range(-PI * 0.95, -PI * 0.05)  # upward fan
	_sparks.append({
		"p": _count.position + Vector2(randf_range(0.2, 1.0) * _count.size.x, _count.size.y * randf_range(0.2, 0.8)),
		"v": Vector2.from_angle(a) * randf_range(90.0, 230.0),
		"life": randf_range(0.35, 0.7), "t": 0.0,
		"c": _colour().lightened(randf_range(0.0, 0.5)),
	})


func _process(delta: float) -> void:
	_t += delta
	_punch = maxf(_punch - delta * 4.0, 0.0)
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_ring = maxf(_ring - delta * 2.2, 0.0)
	for i in range(_sparks.size() - 1, -1, -1):
		var s := _sparks[i]
		s.t += delta
		var v: Vector2 = s.v
		v.y += 420.0 * delta
		s.v = v
		s.p += v * delta
		if s.t >= s.life:
			_sparks.remove_at(i)

	var col := _colour()
	var base := Vector2(0, BAR_Y - 6.0 - _count.size.y)
	_tag.position = Vector2(_count.size.x * maxf(_count.scale.x, 1.0) + 10.0, BAR_Y - 8.0 - _tag.size.y)
	if _drop_t >= 0.0:                             # tipping over and falling
		_drop_t += delta
		var k := minf(_drop_t / DROP_TIME, 1.0)
		_count.pivot_offset = Vector2(_count.size.x, _count.size.y)
		_count.rotation = 0.7 * k * k
		_count.position = base + Vector2(0, 48.0 * k * k)
		_count.scale = Vector2.ONE
		_count.add_theme_color_override("font_color", GREY)
		_tag.add_theme_color_override("font_color", GREY)
		_root.modulate.a = 1.0 - k
		if k >= 1.0:
			_drop_t = -1.0
			_count.rotation = 0.0
	elif _n >= 2:
		var s := 1.0 + 0.3 * _punch * _punch
		_count.pivot_offset = Vector2(0, _count.size.y / 2.0)
		_count.scale = Vector2(s, s)
		var shake := Vector2.ZERO
		if not _frozen and left < WARN:
			var amp := 1.0 + 3.0 * (1.0 - left / WARN)
			shake = Vector2(randf_range(-amp, amp), randf_range(-amp, amp)).snapped(Vector2(2, 2))
		_count.position = base + Vector2(0, -12.0 * _punch) + shake
		var c := GREY.lerp(col, 0.5) if _frozen else col
		_count.add_theme_color_override("font_color", c.lerp(Color.WHITE, _flash * 0.8))
		_tag.add_theme_color_override("font_color", Color.WHITE.lerp(c, 0.45))
		_root.modulate.a = minf(_root.modulate.a + delta * 10.0, 1.0)
	else:
		_root.modulate.a = 0.0

	if _word_t >= 0.0:                             # milestone word: punches in, then floats up and fades
		_word_t += delta
		var w := _word_t / WORD_TIME
		var ws := 1.0 + 1.0 * maxf(1.0 - _word_t / 0.12, 0.0)
		_word.pivot_offset = Vector2(0, _word.size.y / 2.0)
		_word.scale = Vector2(ws, ws)
		_word.position = Vector2(maxf(BAR_W, _tag.position.x + _tag.size.x) + 20.0, BAR_Y - 8.0 - _word.size.y - 24.0 * maxf(w - 0.5, 0.0))
		_word.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.5 * (1.0 - w)))
		_word.modulate.a = 1.0 if w < 0.55 else maxf(1.0 - (w - 0.55) / 0.45, 0.0)
		if w >= 1.0:
			_word_t = -1.0
			_word.visible = false
	_root.queue_redraw()


func _draw_root() -> void:
	var col := _colour()
	if _drop_t >= 0.0 or _frozen:
		col = GREY.lerp(col, 0.0 if _drop_t >= 0.0 else 0.5)
	# milestone ring behind the count
	if _ring > 0.0:
		var c := _count.position + _count.size * 0.5
		var e := 1.0 - pow(_ring, 3.0)
		_root.draw_circle(c, 24.0 + 20.0 * e, Color(col.r, col.g, col.b, 0.15 * _ring))
		_root.draw_arc(c, 20.0 + 36.0 * e, 0.0, TAU, 32, Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.8 * _ring), 4.0 * _ring + 2.0)
	# timer bar: dark frame, track, stepped fill with a lit top row and a shaded bottom row
	_root.draw_rect(Rect2(-4.0, BAR_Y - 4.0, BAR_W + 8.0, BAR_H + 8.0), Color(OUTLINE, 0.85))
	_root.draw_rect(Rect2(0.0, BAR_Y, BAR_W, BAR_H), Color(0.16, 0.14, 0.24, 0.9))
	var cells := ceili(clampf(left, 0.0, 1.0) * BAR_W / CELL) if _drop_t < 0.0 else 0
	if cells > 0:
		var fill := col.lerp(Color.WHITE, _flash * 0.7)
		if not _frozen and left < WARN and fposmod(_t * (6.0 + 14.0 * (1.0 - left / WARN)), 1.0) < 0.5:
			fill = fill.lerp(Color(1.0, 0.25, 0.25), 0.6)   # warning blink: flashes red
		var w := cells * CELL
		_root.draw_rect(Rect2(0.0, BAR_Y, w, BAR_H), fill)
		_root.draw_rect(Rect2(0.0, BAR_Y, w, CELL), fill.lightened(0.45))
		_root.draw_rect(Rect2(0.0, BAR_Y + BAR_H - CELL, w, CELL), fill.darkened(0.3))
		_root.draw_rect(Rect2(w - CELL, BAR_Y, CELL, BAR_H), Color(1, 1, 1, 0.7))   # bright leading edge
	# sparks (4 px squares)
	for s in _sparks:
		var a: float = 1.0 - s.t / s.life
		var p: Vector2 = (s.p as Vector2).snapped(Vector2(2, 2))
		_root.draw_rect(Rect2(p, Vector2(4, 4)), Color(s.c.r, s.c.g, s.c.b, a))
