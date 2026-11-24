class_name Greenery
extends Node2D
## Grass verge and the odd low bush behind the far sidewalk, SUBURB only (CITY has none). Pure decoration:
## nothing here is a hop target or a hazard. World space (Game puts it at z -2, behind the street and the
## poles), so the world tint and the wet-road reflection apply. One chunk per pole span, drawn once and recycled
## like Backdrop.Skyline. Kept sparse on purpose (it competes with the gameplay). Biome is dithered per prop
## inside a cross-fade. 2 px art pixels, 1-art-pixel outlines.

const G := PixelArt.PX
const OUTLINE := PixelArt.OUTLINE

const LEAF := Color(0.27, 0.52, 0.25)
const LEAF_DARK := Color(0.17, 0.37, 0.18)
const LEAF_LIT := Color(0.43, 0.67, 0.32)
const GRASS := Color(0.36, 0.6, 0.29)
const GRASS_DARK := Color(0.25, 0.47, 0.22)
## Leaf palettes [dark, mid, lit]: summer green, yellow-green.
const CANOPIES := [[LEAF_DARK, LEAF, LEAF_LIT], [Color(0.3, 0.42, 0.15), Color(0.45, 0.58, 0.2), Color(0.6, 0.72, 0.3)]]

var floor_y := 620.0
var span := 640.0
var seed_value := 0
var force_kind := -1                      ## >= 0: every prop uses this Biome.Kind (sprite dashboard)
var _chunks := {}


func base_y() -> float:
	return floor_y - 8.0 - Street.SIDEWALK_H


func scroll(cam_x: float) -> void:
	var first := int(floorf((cam_x - 120.0) / span))
	var last := int(floorf((cam_x + 1400.0) / span))
	for i in range(first, last + 1):
		if not _chunks.has(i):
			var c := Chunk.new()
			c.idx = i
			c.g = self
			c.position.x = i * span
			add_child(c)
			_chunks[i] = c
	for i in _chunks.keys():
		if i < first:
			(_chunks[i] as Node2D).queue_free()
			_chunks.erase(i)


class Chunk extends Node2D:
	var idx := 0
	var g: Greenery
	var _key := 0                           ## content seed: every span before the run starts looks the same

	func _h(a: int, b: int) -> float:
		return float(absi(hash(Vector4i(g.seed_value, _key, a, b))) % 100000) / 100000.0

	func _kind(x: float, salt: int) -> int:
		if g.force_kind >= 0:
			return g.force_kind
		return Biome.dither_at(position.x + x, hash(Vector3i(g.seed_value, _key * 131 + salt, 77)))

	func _draw() -> void:
		# the menu lead-in wraps the camera back by whole spans: keep those spans identical so nothing pops
		_key = idx if idx >= 2 else -1
		var base := g.base_y()
		_verge(base)
		# slots across the span; each picks its biome at its own x and grows something (or nothing)
		var slots := 7
		var step := g.span / slots
		for s in slots:
			var x := PixelArt.snap(s * step + step * 0.5 + (_h(s, 1) - 0.5) * step * 0.5)
			var kind := _kind(x, s)
			var roll := _h(s, 2)
			if kind == Biome.Kind.SUBURB and roll < 0.3:   # CITY: nothing
				_bush(x, base, s, 0.9)

	## Grass verge strip along the back of the sidewalk (SUBURB), ragged top edge.
	func _verge(base: float) -> void:
		var x := 0.0
		while x < g.span:
			var k := _kind(x, 900 + int(x / 32.0))
			if k == Biome.Kind.SUBURB:
				var top := base - 6.0
				draw_rect(Rect2(x, top - G, 32.0, G), OUTLINE)
				draw_rect(Rect2(x, top, 32.0, base - top + G), GRASS_DARK)
				draw_rect(Rect2(x, top, 32.0, G), GRASS)
				for t in 4:                                                    # ragged blades on the edge
					var tx := x + PixelArt.snap(_h(int(position.x + x) + t, 40) * 30.0)
					draw_rect(Rect2(tx, top - G * 2.0, G, G * 2.0), OUTLINE)
					draw_rect(Rect2(tx, top - G, G, G), GRASS)
			x += 32.0

	## Merged-outline blob: outline discs first, then dark fill, mid fill offset up-left, lit specks.
	func _blob(discs: Array, pal: Array, s: int) -> void:
		for d in discs:
			PixelArt.disc(self, d[0], d[1] + G, OUTLINE)
		for d in discs:
			PixelArt.disc(self, d[0], d[1], pal[0])
		for d in discs:
			if d[1] > G * 3.0:
				PixelArt.disc(self, d[0] + Vector2(-G, -G * 2.0), d[1] - G * 2.0, pal[1])
		var k := 0
		for d in discs:                                                       # lit leaf clusters, upper left
			var r: float = d[1]
			if r > G * 5.0:
				PixelArt.disc(self, d[0] + Vector2(-r * 0.35, -r * 0.45), maxf(r * 0.35, G * 2.0), pal[2])
			for n in int(r / 6.0):                                             # dark leaf gaps
				var a := _h(s * 31 + k, n) * TAU
				var p: Vector2 = (d[0] + Vector2.from_angle(a) * r * 0.55 * _h(s * 17 + k, n + 50)).snapped(Vector2(G, G))
				if p.y > d[0].y - r * 0.2:
					draw_rect(Rect2(p, Vector2(G * 2.0, G)), pal[0].darkened(0.2))
			k += 1


	## Low round shrub: 2-4 discs on the ground.
	func _bush(x: float, base: float, s: int, scale: float) -> void:
		var pal: Array = CANOPIES[0] if _h(s, 40) < 0.8 else CANOPIES[1]
		var n := 2 + int(_h(s, 41) * 2.99)
		var r0 := PixelArt.snap((10.0 + _h(s, 42) * 6.0) * scale)
		var discs := []
		for k in n:
			var r := PixelArt.snap(r0 * (0.75 + _h(s, 43 + k) * 0.45))
			var dx := (k - (n - 1) * 0.5) * r0 * 1.2
			discs.append([Vector2(x + dx, base - r + G * 2.0).snapped(Vector2(G, G)), r])
		_blob(discs, pal, s)
