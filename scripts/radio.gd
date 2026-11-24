class_name Radio
extends RefCounted
## The kid's car radio: R (pad Y) during play tunes to the next station (Sound.next_station + the HUD toast).
## Each station is a style (Music arranger) with one song per time-of-day phase (Dawn, Morning, Afternoon, Dusk,
## Night), so the music still follows the sky. `station` is a static: it survives restarts, not app launches.
##
## Song keys (all styles): bpm, key (pitch class of the tonic, 0 = C), prog (one entry per bar: [interval above
## the key, Music.CHORDS name], or a list of entries to split the bar), groove (the style's GROOVES), density
## (0..1, how busy the melody is), swing (late off-16ths), swing8 (late off-8ths, 0.67 = triplet jazz swing),
## scale (Music.SCALES; else the pentatonic of `minor`), bars (loop length, default 8), form (2-bar melody units,
## repeated letters repeat the motif). Style keys are listed in each Style* script.
## Every melody is generated from these settings; nothing quotes an existing tune.

const DEFAULT_STATION := 3                ## CITY POP: what the radio is on at launch
static var station := DEFAULT_STATION

const STATIONS := [
	{   # the original game music: lo-fi chiptune with vinyl crackle
		"freq": "88.3", "name": "LO-FI", "style": "lofi",
		"songs": [
			{"bpm": 74, "key": 5, "minor": false, "prog": [[5, "maj7"], [4, "m7"], [2, "m7"], [0, "maj9"]],
				"groove": "sparse", "swing": 0.15, "crackle": 0.5, "density": 0.3},
			{"bpm": 86, "key": 7, "minor": false, "prog": [[0, "maj9"], [9, "m7"], [5, "maj7"], [7, "sus"]],
				"groove": "lofi", "swing": 0.2, "crackle": 0.35, "density": 0.55},
			{"bpm": 92, "key": 2, "minor": false, "prog": [[5, "maj7"], [7, "7"], [4, "m7"], [9, "m7"]],
				"groove": "full", "swing": 0.25, "crackle": 0.3, "density": 0.7},
			{"bpm": 80, "key": 3, "minor": false, "prog": [[0, "maj7"], [10, "add9"], [5, "maj7"], [5, "m7"]],
				"groove": "dusk", "swing": 0.3, "crackle": 0.55, "density": 0.5},
			{"bpm": 70, "key": 9, "minor": true, "prog": [[0, "m9"], [5, "m9"], [10, "maj7"], [3, "maj7"]],
				"groove": "night", "swing": 0.3, "crackle": 0.8, "density": 0.35},
		],
	},
	{   # handheld-console adventure chip: hometown, route march, bike ride, rest stop, the cave
		"freq": "92.7", "name": "POCKET QUEST", "style": "rpg",
		"songs": [
			{"bpm": 100, "key": 5, "scale": "major", "bars": 16, "form": "ABACABAD", "groove": "town",
				"pad": "alberti", "duty": 0.5, "pad_duty": 0.25, "density": 0.4,
				"prog": [[0, "maj"], [5, "maj"], [0, "maj"], [7, "maj"], [9, "min"], [5, "maj"], [2, "min"], [7, "7"]]},
			{"bpm": 132, "key": 2, "scale": "major", "bars": 16, "form": "AABCAABD", "groove": "march",
				"pad": "pulse8", "duty": 0.25, "pad_duty": 0.5, "density": 0.6,
				"prog": [[0, "maj"], [7, "maj"], [5, "maj"], [0, "maj"], [9, "min"], [4, "min"], [5, "maj"], [7, "7"]]},
			{"bpm": 150, "key": 9, "scale": "major", "bars": 16, "form": "ABABCCAD", "groove": "gallop",
				"pad": "arp16", "duty": 0.5, "pad_duty": 0.125, "pad_vol": 0.45, "density": 0.75,
				"prog": [[0, "maj"], [5, "maj"], [7, "maj"], [5, "maj"], [0, "maj"], [10, "maj"], [5, "maj"], [7, "7"]]},
			{"bpm": 108, "key": 0, "scale": "major", "bars": 16, "form": "ABACABAD", "groove": "lull",
				"pad": "roll", "duty": 0.25, "pad_duty": 0.5, "pad_vol": 0.5, "density": 0.35,
				"prog": [[0, "maj"], [4, "min"], [5, "maj"], [7, "maj"], [0, "maj"], [9, "min"], [2, "min"],
					[[5, "maj"], [7, "7"]]]},
			{"bpm": 92, "key": 4, "scale": "minor", "bars": 16, "form": "ABABCDAB", "groove": "cave",
				"pad": "arp16", "duty": 0.5, "pad_duty": 0.125, "pad_vol": 0.4, "density": 0.45, "lead_echo": true,
				"prog": [[0, "min"], [8, "maj"], [5, "min"], [7, "7"], [0, "min"], [3, "maj"], [10, "maj"], [7, "7"]]},
		],
	},
	{   # 80s night-drive synthwave
		"freq": "97.1", "name": "NEON DRIVE", "style": "synthwave",
		"songs": [
			{"bpm": 88, "key": 2, "scale": "major", "groove": "halftime", "sweep": [500.0, 2200.0],
				"lead_echo": 0.45, "density": 0.35,
				"prog": [[0, "maj9"], [7, "maj"], [9, "m7"], [5, "maj7"]]},
			{"bpm": 108, "key": 9, "scale": "minor", "bars": 16, "form": "ABACABAD", "groove": "drive",
				"sweep": [800.0, 3200.0], "density": 0.5,
				"prog": [[0, "min"], [8, "maj"], [3, "maj"], [10, "maj"]]},
			{"bpm": 118, "key": 4, "scale": "minor", "bars": 16, "form": "ABABCDAB", "groove": "run",
				"sweep": [900.0, 3600.0], "density": 0.6,
				"prog": [[0, "min"], [10, "maj"], [8, "maj"], [10, "maj"], [0, "min"], [5, "min"], [8, "maj"], [7, "maj"]]},
			{"bpm": 96, "key": 6, "scale": "minor", "groove": "halftime", "sweep": [600.0, 2400.0],
				"lead_echo": 0.5, "density": 0.45,
				"prog": [[0, "m9"], [8, "maj7"], [5, "m7"], [7, "7sus4"]]},
			{"bpm": 84, "key": 0, "scale": "dorian", "groove": "slow", "sweep": [400.0, 1800.0],
				"lead_echo": 0.55, "density": 0.3,
				"prog": [[0, "m9"], [8, "maj7"], [10, "add9"], [7, "m7"]]},
		],
	},
	{   # glossy 80s city pop / boogie
		"freq": "101.5", "name": "CITY POP", "style": "citypop",
		"songs": [
			{"bpm": 98, "key": 3, "scale": "major", "bars": 16, "groove": "glide", "lead": "synth",
				"density": 0.4, "swing": 0.15,
				"prog": [[5, "maj7"], [4, "7"], [9, "m7"], [[7, "m7"], [0, "7"]]]},
			{"bpm": 112, "key": 2, "scale": "major", "bars": 16, "groove": "bright", "lead": "synth", "brass": true,
				"density": 0.55, "swing": 0.1,
				"prog": [[0, "maj9"], [[4, "m7"], [9, "7"]], [2, "m9"], [[7, "maj7"], [9, "7sus4"]]]},
			{"bpm": 120, "key": 9, "scale": "dorian", "bars": 16, "groove": "disco", "lead": "synth", "brass": true,
				"density": 0.65,
				"prog": [[0, "m9"], [5, "9"], [0, "m9"], [5, "9"], [3, "maj7"], [2, "m7"], [10, "maj7"], [7, "7sus4"]]},
			{"bpm": 104, "key": 5, "scale": "major", "bars": 16, "groove": "boogie", "lead": "sax",
				"density": 0.45, "swing": 0.2,
				"prog": [[5, "maj9"], [7, "9"], [4, "m7"], [9, "m9"], [2, "m7"], [7, "7sus4"], [0, "maj7"], [0, "6/9"]]},
			{"bpm": 92, "key": 1, "scale": "minor", "bars": 16, "groove": "latenight", "lead": "sax",
				"density": 0.35, "swing": 0.25,
				"prog": [[0, "m9"], [5, "m7"], [[10, "m7"], [3, "7"]], [8, "maj7"]]},
		],
	},
	{   # bossa nova by day, a jazz club at night
		"freq": "106.9", "name": "CAFE LOUNGE", "style": "bossa",
		"songs": [
			{"bpm": 120, "key": 5, "scale": "major", "bars": 16, "groove": "bossa", "pad": "guitar", "lead": "flute",
				"bass": "bossa", "density": 0.35,
				"prog": [[0, "maj7"], [[9, "m7"], [2, "9"]], [2, "m7"], [7, "13"], [4, "m7"], [9, "7"], [2, "m9"],
					[[7, "7sus4"], [7, "7"]]]},
			{"bpm": 132, "key": 7, "scale": "major", "bars": 16, "groove": "samba", "pad": "guitar", "lead": "flute",
				"bass": "bossa", "density": 0.6,
				"prog": [[0, "6"], [0, "6"], [2, "m7"], [7, "7"], [2, "m7"], [7, "7"], [0, "maj7"], [[4, "m7b5"], [9, "7"]]]},
			{"bpm": 126, "key": 10, "scale": "major", "bars": 16, "groove": "swing", "pad": "rhodes", "lead": "vibes",
				"bass": "walk", "swing8": 0.67, "density": 0.55,
				"prog": [[2, "m7"], [7, "7"], [0, "maj7"], [9, "7"], [2, "m7"], [7, "13"], [0, "6"], [[2, "m7"], [7, "7"]]]},
			{"bpm": 100, "key": 2, "scale": "minor", "bars": 16, "groove": "bossa", "pad": "guitar", "lead": "vibes",
				"bass": "bossa", "density": 0.35,
				"prog": [[0, "m7"], [0, "m6"], [5, "m7"], [10, "7"], [3, "maj7"], [8, "maj7"], [2, "m7b5"], [7, "7"]]},
			{"bpm": 72, "key": 8, "scale": "major", "groove": "ballad", "pad": "rhodes", "lead": "vibes",
				"bass": "walk", "swing8": 0.67, "density": 0.3,
				"prog": [[0, "maj7"], [9, "m7"], [2, "m7"], [7, "7"], [4, "m7"], [9, "7"], [2, "m9"], [[7, "13"], [1, "7"]]]},
		],
	},
]


static func count() -> int:
	return STATIONS.size()


## The song dict for a station and time-of-day phase, with the station's style filled in.
static func song(st: int, phase: int) -> Dictionary:
	var s: Dictionary = STATIONS[st % STATIONS.size()]
	var out: Dictionary = s.songs[phase % s.songs.size()].duplicate()
	out["style"] = s.style
	return out


## The song playing now: this station at the current time of day.
static func current() -> Dictionary:
	return song(station, TimeOfDay.phase())


## "FM 92.7" and "POCKET QUEST" (the HUD toast).
static func label(st := station) -> Array:
	var s: Dictionary = STATIONS[st % STATIONS.size()]
	return ["FM " + str(s.freq), str(s.name)]
