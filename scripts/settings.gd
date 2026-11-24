class_name Settings
extends RefCounted
## Player settings (static), saved in user://settings.cfg, plus the saved best score (user://save.cfg).
## load() once at start (idempotent), apply() pushes window + volume settings out, save() after any change.

const FILE := "user://settings.cfg"
const SAVE := "user://save.cfg"
const STEPS := 10                          ## volume sliders run 0..STEPS (STEPS = 0 dB on top of the mix)
## Slider name -> audio buses it scales (Voice sends into World, so STREET covers voices too).
const BUSES := {"Music": ["Music"], "Sfx": ["Sfx", "Ui"], "World": ["World"]}
const DEFAULTS := {
	"vol": {"Master": 10, "Music": 10, "Sfx": 10, "World": 10},
	"muted": false, "fullscreen": false, "vsync": true, "shake": true, "flashes": true,
}

static var vol := {"Master": 10, "Music": 10, "Sfx": 10, "World": 10}
static var muted := false
static var fullscreen := false
static var vsync := true
static var shake := true                   ## camera shake on slices / hits
static var flashes := true                 ## full-screen flashes (electrocution, lightning)
static var _loaded := false
static var _best := -1                     ## cached best score, -1 = not read yet


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return
	muted = cfg.get_value("audio", "muted", muted)
	for k in vol:
		vol[k] = clampi(int(cfg.get_value("audio", "vol_" + k.to_lower(), vol[k])), 0, STEPS)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	shake = cfg.get_value("game", "shake", shake)
	flashes = cfg.get_value("game", "flashes", flashes)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(FILE)                         # keep anything else in the file
	cfg.set_value("audio", "muted", muted)
	for k in vol:
		cfg.set_value("audio", "vol_" + k.to_lower(), vol[k])
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("game", "shake", shake)
	cfg.set_value("game", "flashes", flashes)
	cfg.save(FILE)


## Window mode, vsync and bus volumes. Headless / embedded runs skip the window part.
static func apply() -> void:
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and (fullscreen or \
				DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(want)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Sound.apply_volumes()


static func reset() -> void:
	vol = DEFAULTS.vol.duplicate()
	muted = DEFAULTS.muted
	fullscreen = DEFAULTS.fullscreen
	vsync = DEFAULTS.vsync
	shake = DEFAULTS.shake
	flashes = DEFAULTS.flashes


## dB offset for a volume slider (0 dB at full, silent at 0).
static func db(slider: String) -> float:
	var v: int = vol.get(slider, STEPS)
	return -80.0 if v <= 0 else linear_to_db(float(v) / STEPS)


## Slider that scales this bus ("" = none).
static func slider_for(bus: String) -> String:
	for s in BUSES:
		if BUSES[s].has(bus):
			return s
	return ""


static func best_score() -> int:
	if _best < 0:
		var cfg := ConfigFile.new()
		_best = int(cfg.get_value("score", "best", 0)) if cfg.load(SAVE) == OK else 0
	return _best


static func set_best(n: int) -> void:
	if n <= best_score():
		return
	_best = n
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	cfg.set_value("score", "best", n)
	cfg.save(SAVE)
