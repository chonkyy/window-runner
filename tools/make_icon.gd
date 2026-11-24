extends SceneTree
## App icons, all drawn on an art grid and scaled up NEAREST. The hero: the ninja leaping mid-slice (dash
## "drive" frame with the sword arm out), katana up-forward, red scarf streaming behind, a cyan slash crescent
## around him and a full moon behind as a halo, over a dusk sky, a sagging power line and the skyline.
## Everything that matters sits within ~20 art px of the centre, so launcher masks (circle / squircle) never
## cut the ninja.
##   res://icon.png                           480x480 (48 grid x 10): desktop / web / Android legacy icon
##   res://android/icon_foreground.png        432x432 (72 grid x 6): adaptive foreground (ninja only)
##   res://android/icon_background.png        432x432: adaptive background (sky, moon, wire, skyline)
##   res://android/icon_monochrome.png        432x432: Android 13 themed icon (white silhouette)
## Android shows the centre 72/108 of an adaptive layer and guarantees the centre 66/108 (radius 22 of 72).
## godot --headless --path . --script tools/make_icon.gd [-- --preview=<dir>]  (preview: masked mock-ups)

const SKY_TOP := Color(0.09, 0.06, 0.2)
const SKY_MID := Color(0.34, 0.15, 0.42)
const SKY_BOT := Color(0.98, 0.5, 0.4)
const MOON := Color(1.0, 0.9, 0.68)
const MOON_SHADE := Color(0.93, 0.78, 0.58)
const HALO := Color(1.0, 0.75, 0.6)
const CITY := Color(0.17, 0.09, 0.24)
const CITY_FAR := Color(0.33, 0.16, 0.36)
const LIT := Color(1.0, 0.8, 0.42)
const WIRE := Color(0.07, 0.05, 0.1)
const SLASH := Color(0.6, 0.97, 1.0)
const BLADE := Color(0.82, 0.88, 0.96)
const BLADE_HI := Color(1.0, 1.0, 1.0)
const OUT := Color(0.06, 0.06, 0.09)

const CHEST := Vector2i(13, 11)          ## chest pivot in the 22x26 dash frame (arc + moon centre)
const HAND := Vector2i(21, 10)           ## sword hand's outline column in the slice arm row


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://android"))
	var main := _compose(48, true, true)
	_save(main, 10, "res://icon.png")
	_save(_compose(72, true, false), 6, "res://android/icon_background.png")
	var fg := _compose(72, false, true)
	_save(fg, 6, "res://android/icon_foreground.png")
	_save(_mono(fg), 6, "res://android/icon_monochrome.png")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview="):
			_previews(a.trim_prefix("--preview="), main, _compose(72, true, true))
	quit()


## One icon layer on an n x n art grid: background and/or the hero, centred on the grid.
func _compose(n: int, bg: bool, hero: bool) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2i(n / 2, n / 2)
	var origin := c - CHEST + Vector2i(1, 1)     # frame top-left; the scarf trails left, so nudge right
	var chest := origin + CHEST
	if bg:
		_background(img, n, chest)
	if hero:
		_hero(img, origin)
	return img


func _background(img: Image, n: int, chest: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in n:
		var k := float(y) / (n - 1)
		for x in n:
			# stepped bands with a checker dither between steps, so the gradient reads as 8-bit
			var q := snappedf(k * 10.0 + (0.25 if (x + y) % 2 == 0 else -0.25), 1.0) / 10.0
			var col := SKY_TOP.lerp(SKY_MID, q / 0.55) if q < 0.55 else SKY_MID.lerp(SKY_BOT, (q - 0.55) / 0.45)
			img.set_pixel(x, y, col)
	for i in n / 3:                                    # stars, upper sky
		var p := Vector2i(rng.randi_range(1, n - 2), rng.randi_range(1, int(n * 0.4)))
		img.set_pixel(p.x, p.y, img.get_pixel(p.x, p.y).lerp(Color(1, 0.95, 0.85), rng.randf_range(0.5, 1.0)))
	# moon halo (dithered ring) + moon behind the ninja's chest
	var mc := Vector2(chest) + Vector2(0.5, -0.5)
	var r := 13.0
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(mc)
			if d < r:
				var col := MOON
				if Vector2(x + 0.5, y + 0.5).distance_to(mc + Vector2(-3.5, -2.5)) < 2.6 \
						or Vector2(x + 0.5, y + 0.5).distance_to(mc + Vector2(4.5, 4.5)) < 2.0 \
						or Vector2(x + 0.5, y + 0.5).distance_to(mc + Vector2(5.0, -5.0)) < 1.5:
					col = MOON_SHADE
				img.set_pixel(x, y, col)
			elif d < r + 2.0 or (d < r + 4.0 and (x + y) % 2 == 0):
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(HALO, 0.35 if d < r + 2.0 else 0.2))
	# far skyline, then near skyline with lit windows
	var wy0 := chest.y + 17
	var base := wy0 + 1
	var x := 0
	while x < n:
		var w := rng.randi_range(3, 6)
		var h := rng.randi_range(4, 9)
		img.fill_rect(Rect2i(x, base - h - 3, w, n), CITY_FAR)
		x += w
	x = -1
	while x < n:
		var w := rng.randi_range(4, 7)
		var h := rng.randi_range(2, 7)
		img.fill_rect(Rect2i(x, base - h + 2, w, n), CITY)
		for wy in range(base - h + 4, n - 1, 2):
			for wx in range(x + 1, x + w - 1, 2):
				if rng.randf() < 0.22 and wx >= 0 and wx < n:
					img.set_pixel(wx, wy, LIT)
		x += w + rng.randi_range(0, 1)
	# power line: sags across under the ninja's feet, poles past the safe zone
	for px in n:
		var t := float(px) / (n - 1)
		var y := wy0 - 2 + int(round(3.0 * sin(PI * t)))
		img.set_pixel(px, y, WIRE)
	for pole in [2, n - 3]:
		img.fill_rect(Rect2i(pole, wy0 - 4, 2, n), WIRE)
		img.fill_rect(Rect2i(pole - 2, wy0 - 3, 6, 1), WIRE)


func _hero(img: Image, o: Vector2i) -> void:
	_slash(img, o + CHEST)
	var fx := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	fx.fill(Color(0, 0, 0, 0))
	_scarf(fx, o)
	_katana(fx, o)
	_outline(fx)
	img.blend_rect(fx, Rect2i(Vector2i.ZERO, fx.get_size()), Vector2i.ZERO)
	var ninja := NinjaArt.dash_frame("drive", true).get_image()
	ninja.convert(Image.FORMAT_RGBA8)
	img.blend_rect(ninja, Rect2i(Vector2i.ZERO, ninja.get_size()), o)


## Cyan crescent sweeping over the head and round the front: thick in the middle, tapering to points.
func _slash(img: Image, c: Vector2i) -> void:
	var a0 := deg_to_rad(-150.0)
	var a1 := deg_to_rad(35.0)
	var cc := Vector2(c) + Vector2(0.5, 0.5)
	for y in img.get_height():
		for x in img.get_width():
			var v := Vector2(x + 0.5, y + 0.5) - cc
			var a := v.angle()
			if a < a0 or a > a1:
				continue
			var u := (a - a0) / (a1 - a0)
			var th := 3.2 * sin(PI * pow(u, 0.8))
			var d := v.length()
			if d > 16.0 - th and d < 16.0:
				var core := d > 16.0 - th * 0.45
				var col := BLADE_HI if core and u > 0.35 else SLASH
				col.a = 1.0 if u > 0.25 else 0.55
				img.set_pixel(x, y, img.get_pixel(x, y).blend(col))


## Two red tails from the back of the neck band, waving off to the left: a long one lifting, a short one
## drooping, with a gap between them so each reads on its own.
func _scarf(img: Image, o: Vector2i) -> void:
	var start := o + Vector2i(11, 7)
	for tail in [[16, -0.28, 0.0], [11, 0.32, 2.0]]:          # length, drift per px, wave phase
		for t in int(tail[0]):
			var x := start.x - t
			var y := start.y + int(round(t * float(tail[1]) + 1.3 * sin(t * 0.55 + float(tail[2])) * minf(t / 4.0, 1.0)))
			_put(img, x, y, Color(0.93, 0.27, 0.15))
			if t < int(tail[0]) - 3:
				_put(img, x, y + 1, Color(0.62, 0.13, 0.1))


## Katana from the forward hand, angled up-forward: steel blade with a white edge.
func _katana(img: Image, o: Vector2i) -> void:
	var h := o + HAND
	for i in 11:
		var x := h.x + 1 + i
		var y := h.y - int(floor(i * 0.6))
		_put(img, x, y, BLADE)
		_put(img, x, y - 1, BLADE_HI if i < 10 else BLADE)


func _put(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


## 1-art-px dark outline round every opaque pixel (4-neighbour).
func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = Vector2i(x, y) + d
				if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height() and src.get_pixel(p.x, p.y).a > 0.0:
					img.set_pixel(x, y, OUT)
					break


func _mono(fg: Image) -> Image:
	var m := Image.create(fg.get_width(), fg.get_height(), false, Image.FORMAT_RGBA8)
	m.fill(Color(0, 0, 0, 0))
	for y in fg.get_height():
		for x in fg.get_width():
			if fg.get_pixel(x, y).a > 0.5:
				m.set_pixel(x, y, Color(1, 1, 1))
	return m


func _save(img: Image, scale: int, path: String) -> void:
	var big := img.duplicate() as Image
	big.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	big.save_png(path)
	print("wrote ", path, " ", big.get_size())


## Mock-ups: the main icon in a rounded square, and the adaptive layers through a circle mask (the visible
## 72/108 of the layer).
func _previews(dir: String, main: Image, full: Image) -> void:
	var sq := main.duplicate() as Image
	sq.resize(512, 512, Image.INTERPOLATE_NEAREST)
	_mask(sq, func(p: Vector2) -> bool: return _rounded(p, 512.0, 110.0))
	sq.save_png(dir + "/squircle.png")
	var ad := full.duplicate() as Image
	ad.resize(432, 432, Image.INTERPOLATE_NEAREST)
	var vis := 432.0 * 72.0 / 108.0
	var crop := ad.get_region(Rect2i(Vector2i(int((432 - vis) / 2), int((432 - vis) / 2)), Vector2i(int(vis), int(vis))))
	crop.resize(288, 288, Image.INTERPOLATE_NEAREST)
	_mask(crop, func(p: Vector2) -> bool: return p.distance_to(Vector2(144, 144)) < 144.0)
	crop.save_png(dir + "/circle.png")


func _mask(img: Image, inside: Callable) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if not inside.call(Vector2(x + 0.5, y + 0.5)):
				img.set_pixel(x, y, Color(1, 1, 1))


func _rounded(p: Vector2, s: float, r: float) -> bool:
	var q := Vector2(clampf(p.x, r, s - r), clampf(p.y, r, s - r))
	return p.distance_to(q) < r
