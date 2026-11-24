class_name View
extends RefCounted
## Screen size in canvas px. The game is laid out for 1280x720 (BASE). Phones (and `-- --wide` on desktop)
## use stretch aspect KEEP_HEIGHT: the height stays 720 and a wider screen shows more world on the right,
## so `w()` can be > 1280. Desktop keeps KEEP (letterbox), so a tiling WM resizing the window never
## changes the layout mid-round. Nodes size themselves from `w()` when built (once per round).

const BASE := Vector2(1280, 720)


## Called first thing in Game._ready (before anything reads w()).
## `-- --wide=W` renders a fixed W x 720 screen whatever the window does (screenshots / movie captures of a phone
## aspect, e.g. 1600 = 20:9; a tiling WM resizing the window can't change it).
static func setup(win: Window) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wide="):
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
			win.content_scale_size = Vector2i(maxi(int(a.trim_prefix("--wide=")) / 2 * 2, int(BASE.x)), int(BASE.y))
			return
	if OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--wide"):
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT


static func size() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return BASE
	var s := tree.root.get_visible_rect().size
	return Vector2(maxf(floorf(s.x / 2.0) * 2.0, BASE.x), BASE.y)   # even width (pixel grid), never narrower


static func w() -> float:
	return size().x


## Extra width over the 1280 layout (0 on desktop).
static func extra() -> float:
	return w() - BASE.x
