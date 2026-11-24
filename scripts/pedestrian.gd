class_name Pedestrian
extends Node2D
## A person on the street: walker, jogger, cyclist or motorcyclist (set `kind` and call setup() before
## adding). position = feet. Any contact kills the runner (dodge only, never sliced or landed on).
## All kinds live in group "peds" so Runner/Traffic treat them uniformly.

enum Kind { WALKER, CHILD, JOGGER, CYCLIST, MOTO }

const SHIRTS := [Color(0.85, 0.65, 0.2), Color(0.8, 0.25, 0.3), Color(0.25, 0.55, 0.8), Color(0.3, 0.7, 0.45),
	Color(0.9, 0.9, 0.9), Color(0.6, 0.35, 0.75), Color(0.95, 0.5, 0.2)]
const SKINS := [Color(0.9, 0.75, 0.6), Color(0.75, 0.55, 0.4), Color(0.55, 0.38, 0.27), Color(0.95, 0.82, 0.7)]
const PANTS := [Color(0.2, 0.2, 0.3), Color(0.25, 0.3, 0.4), Color(0.35, 0.25, 0.2), Color(0.15, 0.15, 0.15)]

var kind := Kind.WALKER
var vx := 40.0
var size := Vector2(24, 46)
var bounces := true                        ## stomping bounces you back up
var hop_mult := 2.0                        ## hop score multiplier for landing on this person
var reason_name := "pedestrian"            ## used on the game-over screen
var shirt := SHIRTS[0]
var skin := SKINS[0]
var pants := PANTS[0]
var _t := 0.0
var _hair := Color(0.15, 0.1, 0.08)
var _frame := Color(0.8, 0.2, 0.2)          ## bike/moto paint

const HAIRS := [Color(0.12, 0.08, 0.06), Color(0.35, 0.2, 0.1), Color(0.8, 0.65, 0.35), Color(0.55, 0.55, 0.58),
	Color(0.55, 0.18, 0.1)]
const FRAMES := [Color(0.8, 0.2, 0.2), Color(0.2, 0.5, 0.85), Color(0.25, 0.65, 0.4), Color(0.9, 0.75, 0.2),
	Color(0.2, 0.2, 0.25)]
const UMBRELLAS := [Color(0.16, 0.16, 0.2), Color(0.78, 0.18, 0.22), Color(0.2, 0.42, 0.78), Color(0.2, 0.55, 0.4),
	Color(0.5, 0.3, 0.62), Color(0.88, 0.88, 0.86)]
const KID_UMBRELLAS := [Color(1.0, 0.82, 0.18), Color(1.0, 0.45, 0.7), Color(0.35, 0.8, 0.95), Color(0.95, 0.35, 0.2)]
const UMB_GAP := 6.0                       ## canopy hem above the head top
const UMB_FLIP := 0.6                      ## seconds a stomp keeps it blown inside-out

## Raining: everyone carries an umbrella (rolled in _ready). Stomps land on the canopy (roof_y), which
## blows inside-out for a moment; knocked over, it drops to the road. Side hits (rect) are unchanged.
var umbrella := false
var _umb_col := Color.BLACK
var _umb_flip := 0.0


## Roll looks and set size/name for the kind. Call before add_child.
func setup(k: Kind, rng: RandomNumberGenerator) -> void:
	kind = k
	shirt = SHIRTS[rng.randi() % SHIRTS.size()]
	skin = SKINS[rng.randi() % SKINS.size()]
	pants = PANTS[rng.randi() % PANTS.size()]
	_hair = HAIRS[randi() % HAIRS.size()]        # global rng: leaves Traffic's spawn sequence untouched
	_frame = FRAMES[randi() % FRAMES.size()]
	match k:
		Kind.WALKER:
			size = Vector2(24, PixelArt.snap(rng.randf_range(44.0, 52.0)))
			hop_mult = 2.0
		Kind.CHILD:
			size = Vector2(20, 36)
			hop_mult = 3.0
		Kind.JOGGER:
			size = Vector2(24, 48)
			hop_mult = 3.0
		Kind.CYCLIST:
			size = Vector2(56, 56)
			hop_mult = 4.0
			reason_name = "cyclist"
		Kind.MOTO:
			size = Vector2(68, 50)
			hop_mult = 6.0
			reason_name = "motorcyclist"


## Walkers, kids and joggers use the sidewalk; bikes and motos ride the road with the cars.
func on_sidewalk() -> bool:
	return kind == Kind.WALKER or kind == Kind.CHILD or kind == Kind.JOGGER


var _motor: AudioStreamPlayer2D
var _bell := false                         ## cyclist: rings once when near (rolled in _ready)
var speaker := "man"                       ## voice (Sound.SPEAKERS), rolled in _ready
var _vpitch := 1.0                         ## this person's own pitch, so they always sound the same
var _stomps := 0


func _ready() -> void:
	add_to_group("peds")
	_t = randf() * 6.0
	if kind == Kind.MOTO:                    # fast and oncoming: you hear it before you see it
		_motor = Sound.emitter(self, "moto", -6.0, Vector2(0, -20), 1900.0)
		if _motor:
			_motor.pitch_scale = 0.9 + absf(vx) / 1400.0
	_bell = kind == Kind.CYCLIST and randf() < 0.45
	speaker = "kid" if kind == Kind.CHILD else ("woman" if randf() < 0.5 else "man")   # global rng
	_vpitch = randf_range(0.94, 1.06)
	umbrella = umbrella or Weather.active()        # preset true = always (sprite dashboard)
	var cols: Array = KID_UMBRELLAS if kind == Kind.CHILD else UMBRELLAS
	_umb_col = cols[randi() % cols.size()]


## Stomped on by the runner (Runner._bounce_off): "Hey!" (or whatever was recorded), angrier the second time.
## Cyclists ring the bell, moto riders beep.
func bounced() -> void:
	_stomps += 1
	if umbrella:
		_umb_flip = UMB_FLIP
	var pos := global_position + Vector2(0, -size.y)
	var said := false
	const REACT := 0.06                       # a beat after the bounce "boing", so it doesn't mask the shout
	if _stomps > 1:
		said = Sound.voice(speaker, "again", pos, _vpitch, 2.0, REACT) \
			or Sound.voice(speaker, "stomp", pos, _vpitch * 1.06, 2.0, REACT)
	else:
		said = Sound.voice(speaker, "stomp", pos, _vpitch, 0.0, REACT)
	if not said:                              # no recordings yet: the synth grunt
		Sound.play_at("oof", pos, _grunt_pitch(), -4.0)
	var line := shout_text(speaker, "again" if _stomps > 1 else "stomp", Sound.last_take if said else "")
	get_tree().create_timer(REACT).timeout.connect(shout.bind(line, _stomps > 1))
	match kind:
		Kind.CYCLIST:
			Sound.play_at("bell", pos, 1.0, -7.0, 0.12)
		Kind.MOTO:
			var tap := "horns/moto/tap"
			if not Sound.pool_seq([tap, tap], pos, _vpitch, 2.0, 0.05, "World", 0.12):
				Sound.play_at("horn", pos, 1.35, -9.0, 0.12)


## Run into and knocked down by the runner (Runner._die).
func cry() -> void:
	var pos := global_position + Vector2(0, -size.y)
	var said := Sound.voice(speaker, "hurt", pos, _vpitch, 0.0, 0.04)
	if not said:
		Sound.play_at("oof", pos, _grunt_pitch(), -2.0, 0.04)
	shout(shout_text(speaker, "hurt", Sound.last_take if said else ""), true, true)


## What a stomped person shouts, shown in their speech bubble when there's no caption for the take.
const SHOUTS := {
	"man": {"stomp": ["HEY!", "WHOA!", "OI!", "HUH?!", "YO!", "WHAT?!"],
		"again": ["HEY!!", "OW!", "SERIOUSLY?!", "QUIT IT!", "AGAIN?!"],
		"hurt": ["OW!", "OOF!", "MY BACK!", "WATCH IT!", "UGH!"]},
	"woman": {"stomp": ["HEY!", "WHOA!", "OI!", "HUH?!", "EXCUSE ME?!"],
		"again": ["HEY!!", "OW!", "SERIOUSLY?!", "UGH, AGAIN?!", "STOP IT!"],
		"hurt": ["OW!", "OOF!", "HEY, WATCH IT!", "RUDE!", "UGH!"]},
	"kid": {"stomp": ["WHEE!", "HEY!", "WOW!", "COOL!"],
		"again": ["AGAIN! AGAIN!", "HEY!!", "MOM!!", "NOT FAIR!"],
		"hurt": ["WAAAH!", "MOM!!", "OWIE!", "I'M TELLING!"]},
}
## Optional caption per recorded take: [<speaker>] <take>="TEXT" (e.g. [man] stomp_2="OI!").
const CAPTIONS := "res://audio/voices/captions.cfg"
static var _captions: ConfigFile


## Bubble text for `speaker` in `situation`: the caption of the recorded `take` ("voices/man/stomp_2") if
## captions.cfg has one, else a random line from SHOUTS for the situation the take was (or would have been).
static func shout_text(speaker: String, situation: String, take := "") -> String:
	if _captions == null:
		_captions = ConfigFile.new()
		_captions.load(CAPTIONS)                   # missing file = empty, fallbacks only
	if take != "":
		var who := take.get_base_dir().get_file()
		var file := take.get_file()
		var cap := str(_captions.get_value(who, file, ""))
		if cap != "":
			return cap.to_upper()
		situation = file.get_slice("_", 0)
	var lines: Dictionary = SHOUTS.get(speaker, SHOUTS["man"])
	return (lines.get(situation, lines["stomp"]) as Array).pick_random()


var _bubble: Shout

## Pop a speech bubble with `text` out of this person's head (replaces the one still showing). `down` = they
## were just run into: the bubble comes out of where the head lands once they've tipped over (knock_over pivots
## on the feet, so the head ends up size.y away along the road) and lingers a little longer.
func shout(text: String, angry := false, down := false) -> void:
	if (knocked and not down) or not is_inside_tree():
		return
	if is_instance_valid(_bubble):
		_bubble.queue_free()
	_bubble = Shout.new()
	_bubble.text = text
	_bubble.angry = angry
	_bubble.kid = kind == Kind.CHILD
	if down:
		_bubble.life = 1.7
		_bubble.position = Vector2(PixelArt.snap(size.y * 0.7), -18)   # knock_over(1.0): tips to the right
	else:
		_bubble.position = Vector2(0, roof_y() - position.y - 6.0)
	add_child(_bubble)


func _grunt_pitch() -> float:
	return _vpitch * (1.0 if speaker == "man" else Sound.SPEAKER_PITCH.get(speaker, 1.0))


func roof_y() -> float:
	if umbrella and not knocked:
		return position.y + _canopy_top()
	return position.y - size.y


## Local y of the head top (walkers: the size; riders sit at a fixed height).
func _head_top() -> float:
	return -60.0 if kind == Kind.CYCLIST or kind == Kind.MOTO else -PixelArt.snap(size.y)


## Canopy size in px: half width, height.
func _canopy() -> Vector2:
	return Vector2(14.0, 8.0) if kind == Kind.CHILD else Vector2(20.0, 10.0)


func _canopy_top() -> float:
	return _head_top() - UMB_GAP - _canopy().y


func x_min() -> float:
	return position.x - size.x / 2.0


func x_max() -> float:
	return position.x + size.x / 2.0


func rect() -> Rect2:
	return Rect2(position - Vector2(size.x / 2.0, size.y), size)


var knocked := false
var _knock_t := 0.0
var _knock_dir := 1.0
var _knock_face := 1.0


## Ran into by the runner: leaves the hazard group, tips over toward `dir` (+1 = right) and slides to a
## stop (bikes go down with the rider). Traffic stops moving it, so this node moves itself.
func knock_over(dir: float) -> void:
	knocked = true
	if _motor:
		_motor.stop()
	_knock_dir = dir
	_knock_face = 1.0 if vx >= 0.0 else -1.0
	remove_from_group("peds")
	get_tree().create_timer(8.0).timeout.connect(queue_free)


func _process(delta: float) -> void:
	_umb_flip = maxf(_umb_flip - delta, 0.0)
	if knocked:
		_knock_t += delta
		position.x += vx * delta
		vx = move_toward(vx, 0.0, 700.0 * delta)
		queue_redraw()
		return
	if _bell and Sound.near(global_position, 520.0):
		_bell = false
		Sound.play_at("bell", global_position + Vector2(0, -40), 1.0, -9.0)
	match kind:
		Kind.JOGGER:
			_t += delta * 14.0
		Kind.CYCLIST, Kind.MOTO:
			_t += delta * absf(vx) / 12.0       # wheel spin follows speed
		_:
			_t += delta * 8.0
	queue_redraw()


func _draw() -> void:
	var dir := 1.0 if vx >= 0.0 else -1.0
	var tip := 0.0
	if knocked:
		dir = _knock_face
		tip = PI / 2.0 * _knock_dir * ease(minf(_knock_t / 0.3, 1.0), 2.0)
	draw_set_transform(Vector2(position.round().x - position.x, 0), tip, Vector2(dir, 1.0))
	match kind:
		Kind.CYCLIST:
			_draw_cycle(dir, false)
		Kind.MOTO:
			_draw_cycle(dir, true)
		_:
			_draw_walker(dir)
	if umbrella and knocked:                     # dropped: lies upturned on the road where they fell
		draw_set_transform(Vector2(position.round().x - position.x, 0), 0.0, Vector2.ONE)
		_dropped_umbrella(PixelArt.snap(-22.0 * _knock_dir))


const OUTLINE := PixelArt.OUTLINE
const SHOES := Color(0.12, 0.1, 0.1)


func _limb(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	PixelArt.limb(self, a, b, col, w)


## Sleeved arm: shirt-coloured upper arm, 2x2-pixel hand. far = shaded (behind the torso).
func _arm(a: Vector2, b: Vector2, far: bool) -> void:
	_limb(a, b, shirt.darkened(0.3) if far else shirt.darkened(0.1), 4.0)
	var h := b.snapped(Vector2(2, 2))
	draw_rect(Rect2(h - Vector2(2, 0), Vector2(4, 4)), skin.darkened(0.25) if far else skin)


func _box(r: Rect2, col: Color) -> void:
	PixelArt.box(self, r, col)


## Walker/child/jogger on the 2 px art grid (2 px outlines, even sizes), local space faces +x (mirrored
## by the caller's transform). Child = smaller head/torso, same pixel size.
func _draw_walker(_dir: float) -> void:
	var child := kind == Kind.CHILD
	var jog := kind == Kind.JOGGER
	var H := PixelArt.snap(size.y)
	var swing := sin(_t) * (10.0 if jog else (4.0 if child else 6.0))
	var lean := 4.0 if jog else 0.0
	var bob := 2.0 if jog and absf(sin(_t)) > 0.6 else 0.0
	var hw := 10.0 if child else 12.0                                  # head fill size
	var tw := 10.0 if child else 12.0                                  # torso fill width
	var hip_y := -PixelArt.snap(H * 0.38) - bob
	var head := Rect2(lean - hw / 2.0 + 2.0, -H + 2.0 - bob, hw, hw)
	var torso := Rect2(lean - tw / 2.0, head.end.y + 2.0, tw, hip_y - head.end.y - 2.0)
	var shoulder := torso.position + Vector2(tw / 2.0, 4.0)
	var hand := Vector2(0, hip_y - 2.0)
	draw_rect(Rect2(-10, -2, 20, 4), Color(0, 0, 0, 0.3))                          # shadow
	# legs share one outline pass (so both stay readable), toes point forward; they go under the torso
	var feet := [Vector2(-2 - swing, -4), Vector2(2 + swing, -4)]
	for i in 2:
		var f: Vector2 = feet[i].snapped(Vector2(2, 2))
		PixelArt.line(self, Vector2(i * 4 - 2, hip_y), f, OUTLINE, 8.0)
		draw_rect(Rect2(f.x - 4, -6, 10, 6), OUTLINE)
	for i in 2:
		var f: Vector2 = feet[i].snapped(Vector2(2, 2))
		PixelArt.line(self, Vector2(i * 4 - 2, hip_y), f, pants.darkened(0.3) if i == 0 else pants, 4.0)
		draw_rect(Rect2(f.x - 2, -4, 6, 2), SHOES.lightened(0.15) if i == 1 else SHOES)
	_arm(shoulder, hand + Vector2(shoulder.x - swing * 0.8, 0), true)
	_box(torso, shirt)
	draw_rect(Rect2(torso.end.x - 4, torso.position.y, 4, torso.size.y), shirt.darkened(0.2))
	draw_rect(Rect2(torso.position.x, torso.end.y - 4, tw, 4), pants)             # waistband
	var ux := PixelArt.snap(lean + 6.0)                                 # umbrella shaft x
	if umbrella:
		var grip := Vector2(ux, shoulder.y + 6.0)
		_shaft(ux, grip.y)
		_arm(shoulder, grip, false)
	else:
		_arm(shoulder, hand + Vector2(shoulder.x + swing * 0.8, 0), false)
	# head + hair
	_box(head, skin)
	draw_rect(Rect2(head.position, Vector2(hw, 4)), _hair)
	draw_rect(Rect2(head.position, Vector2(4, hw - 4)), _hair)
	draw_rect(Rect2(head.position + Vector2(hw - 4, 6), Vector2(2, 2)), OUTLINE)  # eye
	if umbrella:
		_canopy_at(ux, _canopy_top() - bob)


func _draw_cycle(_dir: float, moto: bool) -> void:
	var half := size.x / 2.0 - 12.0
	var r := 14.0 if moto else 12.0
	var wy := -r
	draw_rect(Rect2(-half - r, -2, (half + r) * 2.0, 4), Color(0, 0, 0, 0.3))         # shadow
	for wx in [-half, half]:
		if moto:
			PixelArt.wheel(self, Vector2(wx, wy), r, 4.0, 2.0, Color(0.32, 0.32, 0.36), Color(0.12, 0.12, 0.14),
				Color(0.45, 0.45, 0.5), _t, 4)
		else:
			PixelArt.wheel(self, Vector2(wx, wy), r, 2.0, 2.0, Color(0.7, 0.72, 0.76), Color(0.22, 0.22, 0.26),
				Color(0.55, 0.55, 0.6), _t, 4)
	var pedal := Vector2.from_angle(_t * 0.5) * 6.0
	if moto:
		_box(Rect2(-20, -30, 40, 12), _frame)                                             # tank/body
		draw_rect(Rect2(-20, -24, 40, 2), _frame.lightened(0.3))
		_box(Rect2(half - 6, -36, 8, 8), Color(0.2, 0.2, 0.24))                            # fairing
		var lit := TimeOfDay.lights_on()
		draw_rect(Rect2(half + 2, -34, 4, 4), Color(2.2, 2.1, 1.6) if lit else Color(1.0, 0.95, 0.6))
		if lit:
			draw_polygon(PackedVector2Array([Vector2(half + 6, -34), Vector2(half + 130, -44),
				Vector2(half + 130, 0), Vector2(half + 6, -30)]), PackedColorArray([Color(1.6, 1.5, 1.1, 0.35),
				Color(1.6, 1.5, 1.1, 0.0), Color(1.6, 1.5, 1.1, 0.0), Color(1.6, 1.5, 1.1, 0.35)]))
		_limb(Vector2(-2, -32), Vector2(6, -16), pants, 4.0)                                # leg on peg
	else:
		var segs := [[Vector2(-half, wy), Vector2(-2, -28)], [Vector2(-2, -28), Vector2(half - 4, -30)],
				[Vector2(half - 4, -30), Vector2(half, wy)], [Vector2(-half, wy), Vector2(0, wy + 2)],
				[Vector2(0, wy + 2), Vector2(-2, -28)], [Vector2(0, wy + 2), Vector2(half - 4, -30)]]
		for seg in segs:                                                                     # one merged outline
			PixelArt.line(self, seg[0], seg[1], OUTLINE, 6.0)
		for seg in segs:
			PixelArt.line(self, seg[0], seg[1], _frame, 2.0)
		var foot := Vector2(0, wy + 2) + pedal                                              # pedalling leg
		var knee := Vector2(6, -24) + pedal * 0.5
		PixelArt.line(self, Vector2(-2, -32), knee, OUTLINE, 8.0)
		PixelArt.line(self, knee, foot, OUTLINE, 8.0)
		PixelArt.line(self, Vector2(-2, -32), knee, pants, 4.0)
		PixelArt.line(self, knee, foot, pants, 4.0)
	# rider
	var lean := 8.0
	var torso := Rect2(lean - 8, -46, 12, 16)
	_box(torso, shirt)
	draw_rect(Rect2(torso.end.x - 4, torso.position.y, 4, torso.size.y), shirt.darkened(0.2))
	_limb(torso.position + Vector2(8, 4), Vector2(half - 4, -36), skin, 2.0)               # arm to bars
	var head := Rect2(lean - 4, -60, 12, 12)
	var ux := lean + 4.0
	if umbrella:                                                                         # held in the other hand
		_shaft(ux, -38.0)
		_limb(torso.position + Vector2(4, 4), Vector2(ux, -38), shirt.darkened(0.1), 2.0)
	_box(head, skin)
	if moto:
		_box(Rect2(head.position, Vector2(12, 8)), Color(0.12, 0.12, 0.15))                  # helmet
		draw_rect(Rect2(head.position + Vector2(6, 2), Vector2(6, 4)), Color(0.5, 0.7, 0.9))    # visor
	else:
		draw_rect(Rect2(head.position, Vector2(12, 4)), _hair)
		draw_rect(Rect2(head.position, Vector2(4, 6)), _hair)
		draw_rect(Rect2(head.position + Vector2(8, 6), Vector2(2, 2)), OUTLINE)
	if umbrella:
		_canopy_at(ux, _canopy_top())


## Umbrella shaft from the grip (hook handle) up to the canopy hem.
func _shaft(x: float, grip_y: float) -> void:
	var hem := _canopy_top() + _canopy().y
	draw_rect(Rect2(x, hem, 2, grip_y - hem + 4.0), OUTLINE)
	draw_rect(Rect2(x - 4, grip_y + 2.0, 4, 2), OUTLINE)                                  # hook
	draw_rect(Rect2(x - 4, grip_y - 0.0, 2, 2), OUTLINE)


## Canopy with its top at local y `top`, centred on the shaft x: stepped dome, 4 panels in two shades, lit
## upper-left, scalloped hem, finial. Inside-out after a stomp: the cup opens upward and shudders.
func _canopy_at(x: float, top: float) -> void:
	var c := _canopy()
	var rows := int(c.y / 2.0)
	var inside_out := _umb_flip > 0.0
	if inside_out:
		top += PixelArt.snap(2.0 * sin(_umb_flip * 60.0))
	var halves := []
	for i in rows:
		var u := (i + 0.5) / rows                       # 0 top .. 1 hem
		if inside_out:
			u = 1.0 - u
		halves.append(PixelArt.snap(c.x * sqrt(1.0 - (1.0 - u) * (1.0 - u)) + (4.0 * u if inside_out else 0.0)))
	for i in rows:                                       # outline pass
		var hw: float = halves[i] + 2.0
		draw_rect(Rect2(x - hw, top + i * 2.0 - 2.0, hw * 2.0 + 2.0, 6.0), OUTLINE)
	var dark := _umb_col.darkened(0.25)
	for i in rows:
		var hw: float = halves[i]
		var y := top + i * 2.0
		var xx := x - hw                                 # odd art-pixel width: the shaft is the centre column
		while xx < x + 2.0 + hw:                         # panels: alternate shades every quarter width
			var panel := int(floorf((xx - (x - c.x)) / (c.x * 0.5)))
			var w := 2.0
			draw_rect(Rect2(xx, y, w, 2), _umb_col if panel % 2 == 0 else dark)
			xx += 2.0
		if i == 0 or (i == 1 and not inside_out):
			draw_rect(Rect2(x - hw + 2.0, y, maxf(hw - 4.0, 2.0), 2), _umb_col.lightened(0.3))
	var hem := top + rows * 2.0
	if not inside_out:
		for k in 5:                                      # rib tips under the hem
			draw_rect(Rect2(PixelArt.snap(x - c.x + k * c.x * 0.5), hem, 2, 2), OUTLINE)
		draw_rect(Rect2(x, top - 4.0, 2, 4), OUTLINE)    # finial
	else:
		draw_rect(Rect2(x, hem, 2, 4), OUTLINE)


## Knocked over: the umbrella lies upturned next to them (cup up, handle sticking out).
func _dropped_umbrella(x: float) -> void:
	var c := _canopy()
	var rows := int(c.y / 2.0)
	for i in rows:
		var u := 1.0 - (i + 0.5) / rows
		var hw := PixelArt.snap(c.x * sqrt(1.0 - (1.0 - u) * (1.0 - u)))
		var y := -c.y + i * 2.0
		draw_rect(Rect2(x - hw - 2.0, y - 2.0, hw * 2.0 + 4.0, 6.0), OUTLINE)
	for i in rows:
		var u := 1.0 - (i + 0.5) / rows
		var hw := PixelArt.snap(c.x * sqrt(1.0 - (1.0 - u) * (1.0 - u)))
		draw_rect(Rect2(x - hw, -c.y + i * 2.0, hw * 2.0, 2), _umb_col if i % 2 == 0 else _umb_col.darkened(0.25))
	PixelArt.line(self, Vector2(x, -c.y), Vector2(x + 12.0, -c.y - 14.0), OUTLINE, 2.0)
	draw_rect(Rect2(x + 12.0, -c.y - 14.0, 4, 2), OUTLINE)


## Comic speech bubble over a stomped person's head: their shout, popped out of the head (origin = tail tip),
## letters bouncing in a wave; a stomp-again is a red spiky burst that shakes. Shape rasterised once on the
## 2 px art grid (outline + 1-art-pixel drop shadow); undoes the world tint like Game._popup.
class Shout extends Node2D:
	const FONT := preload("res://fonts/PressStart2P-Regular.ttf")
	const FS := 16                           ## font size (pixel font: multiple of 8)
	const G := PixelArt.PX
	const LIFE := 1.15
	const INK := Color(0.1, 0.05, 0.1)
	const PAPER := Color(1.0, 0.98, 0.92)
	const KID_PAPER := Color(1.0, 0.93, 0.55)
	const ANGRY_PAPER := Color(1.0, 0.28, 0.32)

	static var untint := true                ## undo the world CanvasModulate (the sprite dashboard has none)

	var text := "HEY!"
	var life := LIFE                         ## seconds on screen
	var angry := false
	var kid := false
	var _t := 0.0
	var _tex: ImageTexture
	var _tex_at := Vector2.ZERO              ## texture top-left, px
	var _body := Rect2()                     ## text box, px
	var _shake := Vector2.ZERO
	var _rise := 0.0

	func _ready() -> void:
		z_index = 20
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if untint:
			var tint: Color = TimeOfDay.tint()
			modulate = Color(1.0 / tint.r, 1.0 / tint.g, 1.0 / tint.b)
		scale = Vector2(0.2, 0.2)
		_build()

	## Body + tail polygons (px, tail tip at the origin) → cell mask → outlined texture.
	func _build() -> void:
		var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var w := PixelArt.snap(tw + 16.0, G * 2.0)
		var h := float(FS) + 12.0
		var lean := -1.0 if randf() < 0.5 else 1.0          # tail leans left or right of the head
		_body = Rect2(-w / 2.0 + lean * 6.0, -h - (22.0 if angry else 12.0), w, h)
		var polys: Array[PackedVector2Array] = []
		var b := _body
		if angry:                                         # spiky burst around an ellipse
			var c := b.get_center()
			var rx := b.size.x / 2.0 + 10.0
			var ry := b.size.y / 2.0 + 8.0
			var n := 10 + int(b.size.x / 24.0)
			var star := PackedVector2Array()
			for i in n * 2:
				var a := TAU * i / (n * 2.0) + 0.2
				var e := Vector2(cos(a) * rx, sin(a) * ry)
				if i % 2 == 1:                            # spike tip, pushed straight out
					e += e.normalized() * randf_range(8.0, 14.0)
				star.append(c + e)
			polys.append(star)
		else:                                             # rounded box, corners cut 2 art px
			var r := 4.0
			polys.append(PackedVector2Array([b.position + Vector2(r, 0), Vector2(b.end.x - r, b.position.y),
				Vector2(b.end.x, b.position.y + r), b.end - Vector2(0, r), b.end - Vector2(r, 0),
				Vector2(b.position.x + r, b.end.y), Vector2(b.position.x, b.end.y - r), b.position + Vector2(0, r)]))
		var base := b.end.y - 2.0
		polys.append(PackedVector2Array([Vector2(-4.0 * lean, base), Vector2(6.0 * lean, base), Vector2(0, 0)]))
		# cell mask
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in polys:
			for v in p:
				lo = lo.min(v)
				hi = hi.max(v)
		lo = (lo / G).floor() - Vector2(1, 1)
		hi = (hi / G).ceil() + Vector2(1, 1)
		var cw := int(hi.x - lo.x)
		var ch := int(hi.y - lo.y)
		var mask := PackedByteArray()
		mask.resize(cw * ch)
		for y in ch:
			for x in cw:
				var at := (lo + Vector2(x + 0.5, y + 0.5)) * G
				for p in polys:
					if Geometry2D.is_point_in_polygon(at, p):
						mask[y * cw + x] = 1
						break
		var paper := ANGRY_PAPER if angry else (KID_PAPER if kid else PAPER)
		var img := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		for y in ch:
			for x in cw:
				if mask[y * cw + x] == 0:
					continue
				var edge := x == 0 or y == 0 or x == cw - 1 or y == ch - 1 \
					or mask[y * cw + x - 1] == 0 or mask[y * cw + x + 1] == 0 \
					or mask[(y - 1) * cw + x] == 0 or mask[(y + 1) * cw + x] == 0
				var col := PixelArt.OUTLINE if edge else paper
				if not edge and not angry and mask[(y + 1) * cw + x] == 1 and y + 2 < ch \
						and mask[(y + 2) * cw + x] == 0:
					col = paper.darkened(0.12)             # shade row along the bottom edge
				img.set_pixel(x, y, col)
		_tex = ImageTexture.create_from_image(img)
		_tex_at = lo * G

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		# pop out of the head: overshoot, settle; squash + rise + fade at the end
		var s := 1.0
		if _t < 0.09:
			s = lerpf(0.2, 1.3, ease(_t / 0.09, 0.5))
		elif _t < 0.2:
			s = lerpf(1.3, 1.0, ease((_t - 0.09) / 0.11, 2.0))
		var out := clampf((_t - (life - 0.3)) / 0.3, 0.0, 1.0)
		scale = Vector2(s * (1.0 + 0.15 * out), s * (1.0 - 0.3 * out))
		_rise = -PixelArt.snap(16.0 * ease(out, 2.0))
		modulate.a = 1.0 - out
		var shake_for := 0.45 if angry else 0.15
		if _t < shake_for:
			var amp := (2.0 if angry else 1.0) * G
			_shake = Vector2(PixelArt.snap(randf_range(-amp, amp)), PixelArt.snap(randf_range(-amp, amp) * 0.5))
		else:
			_shake = Vector2.ZERO
		queue_redraw()

	func _draw() -> void:
		var parent := get_parent() as Node2D
		var snap_x := parent.position.round().x - parent.position.x if parent else 0.0
		draw_set_transform(Vector2(snap_x, _rise) + _shake)
		var sz := _tex.get_size() * G                     # texture is one texel per art pixel
		draw_texture_rect(_tex, Rect2(_tex_at + Vector2(G, G), sz), false, Color(0, 0, 0, 0.35))   # drop shadow
		draw_texture_rect(_tex, Rect2(_tex_at, sz), false)
		# letters in a bouncing wave (whole art pixels), left to right
		var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var x := PixelArt.snap(_body.get_center().x - tw / 2.0)
		var base := PixelArt.snap(_body.position.y + (_body.size.y - FS) / 2.0 + FONT.get_ascent(FS))
		var wave := maxf(0.0, 1.0 - _t / 0.7)
		var ink := Color.WHITE if angry else INK
		var offs := []
		var xs := []
		for i in text.length():
			var dy := -PixelArt.snap(maxf(0.0, sin(_t * 16.0 - i * 0.8)) * 3.0 * G * wave)
			offs.append(dy)
			xs.append(x)
			x += FONT.get_char_size(text.unicode_at(i), FS).x
		if angry:
			for i in text.length():
				draw_string_outline(FONT, Vector2(xs[i], base + offs[i]), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FS,
					6, PixelArt.OUTLINE)
		for i in text.length():
			draw_char(FONT, Vector2(xs[i], base + offs[i]), text[i], FS, ink)
