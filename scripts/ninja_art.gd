class_name NinjaArt
extends RefCounted
## Hooded ninja frames, 16x26 art px (drawn at 2x = 32x52, feet at the bottom row, body centred on
## column 8). A frame = upper body (17 rows) + legs (9 rows). Faces right. The scarf tail and the
## katana blade during a slice are drawn procedurally by Runner.

const W := 16
const H := 26
const SCALE := 2.0
const NECK := Vector2(-6, -36)            ## scarf anchor, px relative to feet
const HAND := Vector2(13, -29)            ## sword hand in the slice pose

const PALETTE := {
	"K": Color(0.06, 0.06, 0.09),         # outline
	"D": Color(0.15, 0.15, 0.21),         # cloth
	"M": Color(0.28, 0.29, 0.4),          # cloth highlight
	"X": Color(0.09, 0.09, 0.13),         # far limb
	"S": Color(0.93, 0.77, 0.6),          # skin (eye slit, hands)
	"R": Color(0.93, 0.27, 0.15),         # scarf / sash
	"r": Color(0.62, 0.13, 0.1),
	"H": Color(0.58, 0.4, 0.22),          # katana hilt on the back
}

const UPPER := [
	"..H....KKKK.....",
	"...H..KDDDDK....",
	"....HKDDDDDMK...",
	"....KDDDDDDDMK..",
	"....KDDDSSSSSK..",
	"....KDDDSKSSKK..",
	"....KDDDDDDDDK..",
	".....KRRRRRRK...",
	"....KRRrrrRRRK..",
	"...KDDDDDDDDK...",
	"..KDMDDDDDDDDK..",
	"..KDMDKDDDDDDSK.",
	"..KSKKDDDDDDKK..",
	"...K.KDDDDDDK...",
	".....KRRrRRK....",
	".....KDDDDDDK...",
	".....KDDDDDDK...",
]

## Sword arm thrust forward (rows 10-12 of UPPER); the hilt leaves the back.
const SLICE_ARM := [
	"...KDDDDDDDDKKK.",
	"..KDMDDDDDDDDSSK",
	"..KDMDDDDDDDKKK.",
]

const LEGS := {
	"stand": [
		".....KDDDDDDK...",
		".....KDDDDDDK...",
		".....KDDKKDDK...",
		".....KDDK.KDDK..",
		".....KDDK.KDDK..",
		".....KDDK.KDDK..",
		".....KDDK.KDDK..",
		".....KDDDKKDDDK.",
		".....KKKKKKKKKK.",
	],
	"tuck": [
		".....KDDDDDDK...",
		"....KDDDDDDDDK..",
		"...KDDDDKKDDDDK.",
		"...KDDDK..KKDDK.",
		"....KDDDK...KKK.",
		".....KKDDK......",
		"......KKK.......",
		"................",
		"................",
	],
	"fall": [
		".....KDDDDDDK...",
		".....KDDKKDDDK..",
		"....KDDK..KDDK..",
		"....KDDK...KDDK.",
		"...KDDK....KDDK.",
		"...KDDK.....KDK.",
		"...KDK......KDK.",
		"..KDDK......KDDK",
		"..KKK.......KKKK",
	],
}

## Tucked ball for the front flip (16x16, facing right): hood + eye slit top-right, thigh pulled to the
## chest with the hand gripping the shin, feet tucked under, sash on the hip. Drawn centred on the chest.
const BALL := [
	".....KKKKKK.....",
	"...KKDDDDDDKK...",
	"..KDDMMDDDDDDK..",
	".KDMDDDDDDDDDDK.",
	".KDMDDDDDDKKKKK.",
	"KDMDDDDDDKSSSSK.",
	"KDMDDDDDDKSKSKK.",
	"KDDDDDDKKRRRRKK.",
	"KDDDDDKMMMMMMMDK",
	"KDDDDKMDDDDDDDDK",
	"KRRrRKKKKKSSSKDK",
	"KDDDDDDDDKSSSKDK",
	".KDDDDDDDKKKKDDK",
	".KDDXXXXXXXXXDDK",
	"..KKXXXXXXXXXXK.",
	"....KKKKKKKKKK..",
]
const BALL_RECT := Rect2(-16, -42, 32, 32)   ## px relative to the feet; centred on the chest pivot (0, -26)
const BALL_NECK := Vector2(2, -28)           ## scarf anchor while balled up


static func ball(silhouette := false) -> ImageTexture:
	return PixelArt.texture("ninja_ball", PackedStringArray(BALL), PALETTE, silhouette)


## legs: a LEGS key. Upright body for standing, air, flips and deaths (the ground run is the dash).
static func frame(legs: String, slicing := false, silhouette := false) -> ImageTexture:
	var key := "ninja_%s_%s" % [legs, "slice" if slicing else "idle"]
	return PixelArt.texture(key, _build(UPPER, SLICE_ARM, 10, LEGS[legs], slicing, false), PALETTE, silhouette)


## --- Dash: the ground run ("Naruto run"). Torso one straight diagonal pitched hard forward, head leading,
## both arms stiff and swept straight back, an 8-frame sprint cycle. 22x26 art px; column DASH_COL sits on
## the runner's x, feet on the bottom row. Leg poses differ in height and _build pads the top, so the body
## bobs with the stride (low on contact, high in the airborne drive); dash_bob() moves the anchors with it.
const DASH_W := 22
const DASH_COL := 11
const DASH_RECT := Rect2(-DASH_COL * SCALE, -H * SCALE, DASH_W * SCALE, H * SCALE)
## Anchors for a 9-row leg pose; add dash_bob(legs).
const DASH_NECK := Vector2(4, -36)          ## scarf anchor (back of the hood, streams above the arms)
const DASH_HAND := Vector2(18, -26)         ## forward sword hand in the dash slice pose
const DASH_CHEST := Vector2(4, -28)         ## slash arc centre (leading shoulder)

const DASH_UPPER := [
	"...H..................",
	"....H..........KKKK...",
	".....H........KDDDDKK.",
	"......H......KDDDDDMMK",
	".......H....KDDDDDDDMK",
	"........H...KDDDDSSSSK",
	".........H.KDDDDDSKSKK",
	".......KKKKRRRRRRRRK..",
	".....KKKXXXMDDDDDDDK..",
	"..KKKXXXDDDMDDDDDK....",
	"KSXXXDDDKKDDDDDDK.....",
	"KSDDDKKKKDDDDDDK......",
	"KKKKK..KDDDDDDK.......",
	"......KRRrRRRK........",
]

## Dash slice (rows 8-12 of DASH_UPPER): the near arm whips forward with the sword, the far arm stays back.
const DASH_SLICE_ARM := [
	".....KKKXXXMDDDDDDDK..",
	"..KKKXXXKKMDDDDDDDKKK.",
	"KSXXXKKKKDMDDDDDDDDSSK",
	"KKKKK...KDDDDDDKKKKKK.",
	".......KDDDDDDK.......",
]

## Near leg D, far leg X; row 0 is the hips. Posed from joint angles (hip/knee/ankle/toe), then outlined.
const DASH_LEGS := {
	"contact": [  # front foot lands ahead, rear leg trailing with the heel up
		"......KDDDDDDK........",
		".......KDDDDK.........",
		"......KXKDDDDK........",
		"..KKKKXXXKDDDDK.......",
		".KXXXXXXXKKDDDK.......",
		"KXXXXXXXK..KDDDKK.....",
		"KXXXKKKK...KDDDDDK....",
		".KXXK.......KDDDDK....",
		"..KK........KDDDDK....",
		".............KKKK.....",
	],
	"down": [  # weight on the bent front leg, rear heel swinging up to the seat
		"......KDDDDDDK........",
		".....KXKDDDDK.........",
		"....KXXXKDDDDK........",
		"....KXXXXKDDDDK.......",
		".....KKKXXKDDDK.......",
		".......KXXKDDDK.......",
		"........KKDDDK........",
		".........KDDDK........",
		".........KDDDDK.......",
		"..........KDDDK.......",
		"...........KKK........",
	],
	"pass": [  # support leg straight under the hips, free knee coming through
		"......KDDDDDDK........",
		".......KDDDKK.........",
		"........KDDKXK........",
		"........KDDKXXK.......",
		"........KDDKXXK.......",
		".......KKDDKXK........",
		".......KKDDKK.........",
		".......KDDDK..........",
		".......KDDDK..........",
		".......KDDDDK.........",
		".......KDDDDK.........",
		"........KKKK..........",
	],
	"drive": [  # airborne: push-off leg stretched behind, knee high in front
		"......KDDDDDDK........",
		".......KDDKXXXXK......",
		"......KDDDKXXXXK......",
		".....KDDDDKKKXXK......",
		"....KDDDDK..KXXKKK....",
		"...KDDDDK...KXXXXXK...",
		"..KDDDDK....KXXXXXK...",
		"..KDDDK......KKKKK....",
		"..KDDDK...............",
		"..KDDDK...............",
		"...KKK................",
		"......................",
	],
}

## Sprint cycle; "~" swaps near/far leg shading, so the second half is the other leg's stride.
const DASH := ["contact", "down", "pass", "drive", "contact~", "down~", "pass~", "drive~"]


static func dash_frame(legs: String, slicing := false, silhouette := false) -> ImageTexture:
	var key := "ninja_dash_%s_%s" % [legs, "slice" if slicing else "idle"]
	return PixelArt.texture(key, _build(DASH_UPPER, DASH_SLICE_ARM, 8, DASH_LEGS[legs.trim_suffix("~")], slicing, legs.ends_with("~")), PALETTE, silhouette)


## Vertical px offset of the dash anchors for this leg pose (negative = body raised).
static func dash_bob(legs: String) -> float:
	return (9 - DASH_LEGS[legs.trim_suffix("~")].size()) * SCALE


## Blank rows on top (up to H), upper body (slice arm rows swapped in from arm_row, hilt removed), then legs
## (near/far shading optionally swapped).
static func _build(upper: Array, arm: Array, arm_row: int, leg_rows: Array, slicing: bool, swap: bool) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in H - upper.size() - leg_rows.size():
		rows.append(".".repeat(upper[0].length()))
	for y in upper.size():
		var row: String = upper[y]
		if slicing:
			if y >= arm_row and y < arm_row + arm.size():
				row = arm[y - arm_row]
			row = row.replace("H", ".")
		rows.append(row)
	for y in leg_rows.size():
		var row: String = leg_rows[y]
		if swap and y > 0:
			row = row.replace("X", "x").replace("D", "X").replace("x", "D")
		rows.append(row)
	return rows
