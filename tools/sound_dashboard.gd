extends SceneTree
## Sound dashboard (temporary tool): `godot --path . --script tools/sound_dashboard.gd`
## Every game sound in one list: play it, set its volume, or drag an audio file from the file manager onto its row to
## replace it (ogg/wav/mp3 copied as-is, anything else converted to ogg with ffmpeg). Volumes are saved to
## res://audio/levels.cfg (Sound.LEVELS) and, while the game is running, sent to it live over UDP (Sound.LINK_PORT), so
## you can play in one window and mix in the other. Replaced files are backed up to audio/_replaced/<time>/ first;
## Revert brings the previous sound back (synth recipe or the original recording).

var dash: Dash


func _initialize() -> void:
	dash = Dash.new()
	root.add_child(dash)


class Dash extends Control:
	const GROUPS := [
		["Runner", ["jump", "double_jump", "drop", "wire_land", "land_street", "roof_land", "bounce", "slash",
			"slash_spin", "step_wire", "step_street", "step_roof"]],
		["Deaths", ["crash", "horn", "thud", "oof", "bell", "moto_rev", "squawk", "zap", "body_thud"]],
		["Scoring / feedback", ["slice_hit", "feathers", "hop", "bonus", "ninja_pop", "lamp_clang", "spark_crackle",
			"lamp_fixed", "trunk_pop", "clatter", "tick"]],
		["Menus", ["ui_start", "confirm", "ui_tick", "score_punch", "fanfare", "zoom_whoosh", "zoom_out",
			"push_whoosh"]],
		["World", ["coo", "chirp", "chirp2"]],
		["Loops", ["flutter", "transformer_hum", "lamp_buzz", "engine_car", "engine_big", "moto", "car_engine_ext",
			"car_drone", "amb_city", "amb_wind", "amb_crickets"]],
	]
	const HORN_KINDS := ["tap", "long"]
	const RAW_EXTS := ["ogg", "wav", "mp3"]
	const BACKUP := "res://audio/_replaced"
	const C_BG := Color(0.06, 0.05, 0.1)
	const C_ROW := Color(0.11, 0.1, 0.17)
	const C_SEL := Color(0.22, 0.17, 0.36)
	const C_ADD := Color(0.08, 0.13, 0.12)
	const C_FILE := Color(1.0, 0.75, 0.35)
	const C_SYNTH := Color(0.55, 0.75, 1.0)
	const C_DIM := Color(0.6, 0.6, 0.7)
	const C_OFF := Color(1.0, 0.45, 0.45)

	var rows: Array[Dictionary] = []
	var selected := -1
	var list: VBoxContainer
	var scroll: ScrollContainer
	var status: Label
	var link_label: Label
	var player: AudioStreamPlayer
	var playing_key := ""
	var stop_at := 0.0
	var dialog: FileDialog
	var dialog_row := -1
	var udp := PacketPeerUDP.new()
	var last_ok := -100.0
	var linked := false
	var ping_t := 0.0
	var save_t := -1.0
	var bold: SystemFont
	var tabs: TabContainer

	# sprites tab
	const MAX_CELL := 560.0                    ## widest stage; bigger sprites zoom less
	const BGS := ["dark", "light", "checker"]
	var sprite_box: VBoxContainer
	var zoom := 2
	var bg_mode := 0
	var animate := true
	var ped_seed := 1
	var live: Array[Node2D] = []               ## holders of live game nodes (paused by ANIMATE)
	var loops: Array[Dictionary] = []         ## one-shot states replayed on a timer (see _loop)
	var ticked: Array[Node2D] = []             ## Cabin nodes the dashboard animates itself (FamilyCar, Interior)
	var zoom_btns: Array[Button] = []
	var bg_b: Button
	var phase_b: Button
	var anim_b: Button
	var checker: ImageTexture

	func _ready() -> void:
		Sound.load_levels()
		Sound.setup_buses()
		_setup_font()
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = C_BG
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		var root_box := VBoxContainer.new()
		root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root_box.offset_left = 16
		root_box.offset_right = -16
		root_box.offset_top = 16
		root_box.offset_bottom = -16
		root_box.add_theme_constant_override("separation", 8)
		add_child(root_box)
		var head := HBoxContainer.new()
		root_box.add_child(head)
		var title := _label("DASHBOARD", 22, Color.WHITE)
		title.add_theme_font_override("font", bold)
		head.add_child(title)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		link_label = _label("", 14, C_DIM)
		head.add_child(link_label)
		tabs = TabContainer.new()
		tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root_box.add_child(tabs)
		var sounds := VBoxContainer.new()
		sounds.name = "Sounds"
		sounds.add_theme_constant_override("separation", 8)
		tabs.add_child(sounds)
		sounds.add_child(_label("Drag an audio file onto a row to replace it  -  click a row to select (Space = play)" +
			"  -  volumes save to audio/levels.cfg", 14, C_DIM))
		scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sounds.add_child(scroll)
		list = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 2)
		scroll.add_child(list)
		status = _label("ready", 14, Color(0.7, 1.0, 0.7))
		sounds.add_child(status)
		_setup_sprites_tab()
		player = AudioStreamPlayer.new()
		add_child(player)
		dialog = FileDialog.new()
		dialog.theme = theme
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.ogg, *.wav, *.mp3, *.flac, *.m4a, *.aac, *.opus, *.webm ; Audio"])
		dialog.size = Vector2i(900, 560)
		dialog.file_selected.connect(func(p: String) -> void: _replace(dialog_row, p))
		add_child(dialog)
		get_window().files_dropped.connect(_on_drop)
		udp.bind(0, "127.0.0.1")
		udp.set_dest_address("127.0.0.1", Sound.LINK_PORT)
		_build()
		_build_sprites()
		if OS.get_cmdline_user_args().has("--tab=sprites"):
			tabs.current_tab = 1

	## Plain readable system sans font for the whole dashboard (the game keeps its pixel font).
	func _setup_font() -> void:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans", "Sans-Serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		bold = f.duplicate()
		bold.font_weight = 700
		var t := Theme.new()
		t.default_font = f
		t.default_font_size = 15
		for type in ["Label", "Button", "TabContainer", "TabBar", "LineEdit", "Tree", "ItemList", "PopupMenu",
				"OptionButton", "AcceptDialog", "FileDialog", "TooltipLabel", "CheckBox"]:
			t.set_font("font", type, f)
			t.set_font_size("font_size", type, 15)
		theme = t

	# --- list ---

	func _build() -> void:
		var keep := scroll.scroll_vertical
		var sel_key: String = rows[selected].key if selected >= 0 and selected < rows.size() else ""
		for c in list.get_children():
			c.queue_free()
		rows.clear()
		selected = -1
		_header("Buses (master faders)")
		for b in Sound.BUS_DB:
			_row({"kind": "bus", "key": b, "title": b})
		for g in GROUPS:
			_header(g[0])
			for n in g[1]:
				_row({"kind": "synth", "key": n, "title": n})
		var others := SoundBank.NAMES.filter(func(n: String) -> bool:
			return not GROUPS.any(func(g: Array) -> bool: return g[1].has(n)))
		if not others.is_empty():
			_header("Other")
			for n in others:
				_row({"kind": "synth", "key": n, "title": n})
		_header("Horns (recorded)")
		for v in Sound.HORNS:
			for k in HORN_KINDS:
				_pool_rows("horns/%s/%s" % [v, k], "%s %s" % [v, k])
		_header("Voices (recorded, through the Voice futz)")
		for s in Sound.SPEAKERS:
			for sit in Sound.SITUATIONS:
				_pool_rows("voices/%s/%s" % [s, sit], "%s %s" % [s, sit])
		_pool_rows(Sound.BIRD_VOICE, "bird squawk")
		for i in rows.size():
			if rows[i].key == sel_key:
				_select(i)
		await get_tree().process_frame
		scroll.scroll_vertical = keep

	func _pool_rows(pool: String, title: String) -> void:
		for f: String in _takes(pool):
			var key := pool.get_base_dir() + "/" + f.get_basename()
			_row({"kind": "take", "key": key, "title": "%s  %s" % [title, f.get_basename().get_slice("_", 1)],
				"pool": pool})
		for key: String in _deleted(pool):
			_row({"kind": "deleted", "key": key, "title": "%s  %s" % [title, key.get_file().get_slice("_", 1)],
				"pool": pool})
		_row({"kind": "add", "key": pool, "title": "+ new %s take" % title, "pool": pool})

	## Takes of `pool` that only exist in a backup (deleted, not replaced), by key.
	func _deleted(pool: String) -> Array:
		var out := []
		if not DirAccess.dir_exists_absolute(BACKUP):
			return out
		var prefix := pool.get_file() + "_"
		for d in DirAccess.get_directories_at(BACKUP):
			var dir := "%s/%s/%s" % [BACKUP, d, pool.get_base_dir()]
			if not DirAccess.dir_exists_absolute(dir):
				continue
			for f in DirAccess.get_files_at(dir):
				if f.begins_with(prefix) and RAW_EXTS.has(f.get_extension().to_lower()):
					var key := pool.get_base_dir() + "/" + f.get_basename()
					if _file(key) == "" and not out.has(key):
						out.append(key)
		out.sort_custom(func(a: String, b: String) -> bool:
			return a.get_file().get_slice("_", 1).to_int() < b.get_file().get_slice("_", 1).to_int())
		return out

	## Files in a pool folder (one per take, any extension), sorted by take number.
	func _takes(pool: String) -> Array:
		var dir := "res://audio/" + pool.get_base_dir()
		var out := []
		if not DirAccess.dir_exists_absolute(dir):
			return out
		var prefix := pool.get_file() + "_"
		for f in DirAccess.get_files_at(dir):
			if f.begins_with(prefix) and RAW_EXTS.has(f.get_extension().to_lower()):
				out.append(f)
		out.sort_custom(func(a: String, b: String) -> bool:
			return a.get_basename().get_slice("_", 1).to_int() < b.get_basename().get_slice("_", 1).to_int())
		return out

	func _header(t: String) -> void:
		var l := _label(t.to_upper(), 20, Color(1.0, 0.85, 0.4))
		l.add_theme_font_override("font", bold)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 12)
		m.add_theme_constant_override("margin_bottom", 4)
		m.add_child(l)
		list.add_child(m)

	func _row(r: Dictionary) -> void:
		var i := rows.size()
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_ADD if r.kind == "add" else C_ROW
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", sb)
		panel.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_select(i))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		panel.add_child(h)
		var name_l := _label(r.title, 15, Color.WHITE if r.kind != "add" else C_DIM)
		name_l.custom_minimum_size.x = 240
		h.add_child(name_l)
		var src := _label("", 14, C_SYNTH)
		src.custom_minimum_size.x = 210
		h.add_child(src)
		r.panel = panel
		r.style = sb
		r.src = src
		r.name_l = name_l
		if r.kind == "add" or r.kind == "deleted":
			src.text = "drop a file here to add a take" if r.kind == "add" else "DELETED"
			src.add_theme_color_override("font_color", C_DIM if r.kind == "add" else C_OFF)
			if r.kind == "deleted":
				name_l.add_theme_color_override("font_color", C_DIM)
				h.add_child(_button("PLAY", func() -> void: _play(i)))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(sp)
			if r.kind == "deleted":
				h.add_child(_button("RESTORE", func() -> void: _restore(i)))
			else:
				h.add_child(_button("...", func() -> void: _browse(i)))
		else:
			if r.kind != "bus":
				h.add_child(_button("PLAY", func() -> void: _play(i)))
			var slider := HSlider.new()
			slider.min_value = -30.0
			slider.max_value = 12.0
			slider.step = 0.5
			slider.custom_minimum_size.x = 240
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.value = _trim(r)
			h.add_child(slider)
			var db := _label("", 14, Color.WHITE)
			db.custom_minimum_size.x = 80
			h.add_child(db)
			r.slider = slider
			r.db = db
			slider.value_changed.connect(func(v: float) -> void: _set_trim(i, v))
			h.add_child(_button("0dB", func() -> void: slider.value = 0.0))
			if r.kind != "bus":
				h.add_child(_button("REVERT", func() -> void: _revert(i)))
				h.add_child(_button("...", func() -> void: _browse(i)))
			if r.kind == "synth":
				r.off_b = _button("OFF", func() -> void: _toggle_off(i))
				r.off_b.custom_minimum_size.x = 72
				h.add_child(r.off_b)
			elif r.kind == "take":
				var del := _button("DELETE", func() -> void: _delete(i))
				del.custom_minimum_size.x = 72
				del.add_theme_color_override("font_color", C_OFF)
				h.add_child(del)
		list.add_child(panel)
		rows.append(r)
		_refresh_row(i)

	func _refresh_row(i: int) -> void:
		var r := rows[i]
		if r.kind == "bus":
			r.src.text = "base %+.0f dB" % Sound.BUS_DB[r.key]
			r.src.add_theme_color_override("font_color", C_DIM)
		elif r.kind != "add":
			var f := _file(r.key)
			if f == "":
				r.src.text = "SYNTH" + (" (loop)" if SoundBank.LOOPS.has(r.key) else "")
				r.src.add_theme_color_override("font_color", C_SYNTH)
			else:
				r.src.text = ("FILE " if r.kind == "take" else "REPLACED ") + f.get_file()
				r.src.add_theme_color_override("font_color", C_FILE if r.kind == "synth" else Color.WHITE)
		if r.has("db"):
			r.db.text = "%+.1f dB" % r.slider.value
		if r.has("off_b"):
			var is_off := Sound.off.has(r.key)
			r.off_b.text = "ON" if is_off else "OFF"
			r.off_b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if is_off else C_OFF)
			r.slider.editable = not is_off
			r.name_l.add_theme_color_override("font_color", C_DIM if is_off else Color.WHITE)
			if is_off:
				r.db.text = "OFF"
				r.src.text = "SWITCHED OFF"
				r.src.add_theme_color_override("font_color", C_OFF)

	func _select(i: int) -> void:
		if selected >= 0 and selected < rows.size():
			rows[selected].style.bg_color = C_ADD if rows[selected].kind == "add" else C_ROW
		selected = i
		rows[i].style.bg_color = C_SEL

	# --- volume ---

	func _trim(r: Dictionary) -> float:
		return Sound.bus_trims.get(r.key, 0.0) if r.kind == "bus" else Sound.trims.get(r.key, 0.0)

	func _set_trim(i: int, v: float) -> void:
		var r := rows[i]
		if r.kind == "bus":
			Sound.bus_trims[r.key] = v
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index(r.key), Sound.BUS_DB[r.key] + v)
			_send("bus %s %s" % [r.key, v])
		else:
			if playing_key == r.key and player.playing:
				player.volume_db += v - Sound.trims.get(r.key, 0.0)
			Sound.trims[r.key] = v
			_send("trim %s %s" % [r.key, v])
		_refresh_row(i)
		save_t = 0.4

	func _save() -> void:
		var cfg := ConfigFile.new()
		var keys := Sound.trims.keys()
		keys.sort()
		for k in keys:
			if not is_zero_approx(Sound.trims[k]):
				cfg.set_value("db", k, Sound.trims[k])
		for k in Sound.bus_trims:
			if not is_zero_approx(Sound.bus_trims[k]):
				cfg.set_value("bus", k, Sound.bus_trims[k])
		for k in Sound.off:
			cfg.set_value("off", k, true)
		var err := cfg.save(Sound.LEVELS)
		if err != OK:
			_status("could not save levels.cfg (error %d)" % err, true)

	## Synth sounds can't be removed (game code triggers them), so "delete" = switched off: never plays.
	func _toggle_off(i: int) -> void:
		_select(i)
		var r := rows[i]
		var now_off := not Sound.off.has(r.key)
		if now_off:
			Sound.off[r.key] = true
			if playing_key == r.key:
				player.stop()
		else:
			Sound.off.erase(r.key)
		_send("off %s %d" % [r.key, 1 if now_off else 0])
		_refresh_row(i)
		_save()
		_status("%s switched %s%s" % [r.key, "off" if now_off else "back on", "  (live in game)" if linked else ""])

	## Delete a recorded take: its file goes to the backup folder (the row stays as DELETED with RESTORE).
	func _delete(i: int) -> void:
		var r := rows[i]
		if playing_key == r.key:
			player.stop()
			player.stream = null
		_backup(r.key)
		_after_change(r.key, "%s deleted (RESTORE brings it back)" % r.key, false)

	func _restore(i: int) -> void:
		var r := rows[i]
		var prev := _latest_backup(r.key)
		if prev == "":
			_status("no backup of %s found" % r.key, true)
			return
		_move_back(prev, r.key)
		_after_change(r.key, "%s restored" % r.key)

	## Move a backed-up file (+ its .import) back to audio/<key>.<ext>.
	func _move_back(prev: String, key: String) -> void:
		var to := "res://audio/%s.%s" % [key, prev.get_extension()]
		DirAccess.rename_absolute(ProjectSettings.globalize_path(prev), ProjectSettings.globalize_path(to))
		if FileAccess.file_exists(prev + ".import"):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(prev + ".import"),
				ProjectSettings.globalize_path(to + ".import"))

	# --- playback ---

	func _play(i: int) -> void:
		_select(i)
		var r := rows[i]
		if player.playing and playing_key == r.key:
			player.stop()
			playing_key = ""
			return
		var s := _stream(r)
		if s == null:
			_status("nothing to play for " + r.key, true)
			return
		player.stop()
		player.stream = s
		player.bus = "Voice" if r.key.begins_with("voices/") else (
			"World" if r.kind == "take" or SoundBank.LOOPS.has(r.key) else "Sfx")
		player.volume_db = Sound.trims.get(r.key, 0.0)
		player.play()
		playing_key = r.key
		stop_at = Time.get_ticks_msec() / 1000.0 + (4.0 if SoundBank.LOOPS.has(r.key) else 60.0)

	func _stream(r: Dictionary) -> AudioStream:
		var f := _latest_backup(r.key) if r.kind == "deleted" else _file(r.key)
		if f != "":
			var s := Sound.load_raw(f)             # raw: never a stale cached import of a replaced file
			if s and r.kind == "synth":
				Sound._set_loop(s, SoundBank.LOOPS.has(r.key))
			return s
		return SoundBank.build(r.key) if r.kind == "synth" else null

	# --- replacing ---

	## Current file for a sound key (res://audio/<key>.<ext>), or "".
	func _file(key: String) -> String:
		for e in RAW_EXTS:
			var p := "res://audio/%s.%s" % [key, e]
			if FileAccess.file_exists(p):
				return p
		return ""

	func _browse(i: int) -> void:
		_select(i)
		dialog_row = i
		var dl := OS.get_environment("HOME").path_join("Downloads")
		if DirAccess.dir_exists_absolute(dl):
			dialog.current_dir = dl
		dialog.popup_centered()

	func _on_drop(files: PackedStringArray) -> void:
		if files.is_empty() or tabs.current_tab != 0:
			return
		var target := -1
		var m := get_global_mouse_position()
		for i in rows.size():
			if rows[i].panel.get_global_rect().has_point(m) and rows[i].kind != "bus":
				target = i
				break
		if target < 0:
			target = selected
		if target < 0 or rows[target].kind == "bus":
			_status("drop onto a sound's row (or click one first)", true)
			return
		_replace(target, files[0])

	func _replace(i: int, src: String) -> void:
		if i < 0 or i >= rows.size():
			return
		var r := rows[i]
		var ext := src.get_extension().to_lower()
		var key: String = r.key
		if r.kind == "add":
			var n := 1
			for f: String in _takes(r.pool):
				n = maxi(n, f.get_basename().get_slice("_", 1).to_int() + 1)
			for k: String in _deleted(r.pool):          # don't reuse a deleted take's number
				n = maxi(n, k.get_file().get_slice("_", 1).to_int() + 1)
			key = "%s_%d" % [r.pool, n]
		var out_ext := ext if RAW_EXTS.has(ext) else "ogg"
		var dst := ProjectSettings.globalize_path("res://audio/%s.%s" % [key, out_ext])
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		_backup(key)
		if RAW_EXTS.has(ext):
			var err := DirAccess.copy_absolute(src, dst)
			if err != OK:
				_status("copy failed (error %d): %s" % [err, src], true)
				return
		else:
			var out_log := []
			var code := OS.execute("ffmpeg", ["-y", "-loglevel", "error", "-i", src, "-vn", "-c:a", "libvorbis",
				"-q:a", "5", dst], out_log, true)
			if code != 0:
				_status("ffmpeg could not convert %s: %s" % [src.get_file(), "".join(out_log).strip_edges()], true)
				return
		if Sound.load_raw(dst) == null:
			_status("Godot can't read %s - try another format" % src.get_file(), true)
			DirAccess.remove_absolute(dst)
			return
		_after_change(key, "%s  <-  %s" % [key, src.get_file()])

	## Move every file of `key` (any extension + .import) into a fresh backup folder. True if anything was moved.
	func _backup(key: String) -> bool:
		var moved := false
		var dir := "%s/%s" % [BACKUP, _stamp()]
		for e in RAW_EXTS:
			var p := "res://audio/%s.%s" % [key, e]
			if not FileAccess.file_exists(p):
				continue
			var to := "%s/%s.%s" % [dir, key, e]
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.get_base_dir()))
			_ignore_backups()
			DirAccess.rename_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(to))
			if FileAccess.file_exists(p + ".import"):
				DirAccess.rename_absolute(ProjectSettings.globalize_path(p + ".import"),
					ProjectSettings.globalize_path(to + ".import"))
			moved = true
		return moved

	func _revert(i: int) -> void:
		var r := rows[i]
		var prev: String = _latest_backup(r.key) if r.kind == "take" else ""
		if r.kind == "take" and prev == "":
			_status("no earlier version of %s to go back to" % r.key, true)
			return
		if r.kind == "synth" and _file(r.key) == "":
			_status("%s is already the synth sound" % r.key)
			return
		_backup(r.key)
		if prev != "":
			_move_back(prev, r.key)
		_after_change(r.key, "%s reverted to %s" % [r.key, "the original" if prev != "" else "the synth sound"])

	## Newest backed-up file of `key` that isn't the current file, or "".
	func _latest_backup(key: String) -> String:
		if not DirAccess.dir_exists_absolute(BACKUP):
			return ""
		var dirs := Array(DirAccess.get_directories_at(BACKUP))
		dirs.sort()
		dirs.reverse()
		for d in dirs:
			for e in RAW_EXTS:
				var p := "%s/%s/%s.%s" % [BACKUP, d, key, e]
				if FileAccess.file_exists(p):
					return p
		return ""

	func _after_change(key: String, msg: String, play := true) -> void:
		_send("reload " + key)
		_reimport()
		await _build()
		for i in rows.size():
			if rows[i].key == key:
				_select(i)
				if play:
					_play(i)
				break
		_status(msg + ("  (live in game)" if linked else ""))

	## Background re-import so next launches use proper imported resources (the game decodes raw files until then).
	func _reimport() -> void:
		OS.create_process(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--import"])

	func _ignore_backups() -> void:
		var gi := BACKUP + "/.gdignore"
		if not FileAccess.file_exists(gi):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP))
			FileAccess.open(gi, FileAccess.WRITE).store_string("")

	func _stamp() -> String:
		var t := Time.get_datetime_dict_from_system()
		return "%04d%02d%02d-%02d%02d%02d-%03d" % [t.year, t.month, t.day, t.hour, t.minute, t.second,
			Time.get_ticks_msec() % 1000]

	# --- live link ---

	func _send(msg: String) -> void:
		udp.put_packet(msg.to_utf8_buffer())

	func _process(delta: float) -> void:
		var now := Time.get_ticks_msec() / 1000.0
		while udp.get_available_packet_count() > 0:
			if udp.get_packet().get_string_from_utf8() == "ok":
				last_ok = now
		ping_t -= delta
		if ping_t <= 0.0:
			ping_t = 1.0
			_send("ping")
		var was := linked
		linked = now - last_ok < 2.5
		if linked and not was:                       # game (re)started: push the whole mix
			for k in Sound.trims:
				_send("trim %s %s" % [k, Sound.trims[k]])
			for b in Sound.bus_trims:
				_send("bus %s %s" % [b, Sound.bus_trims[b]])
		link_label.text = "GAME LINKED - changes are live" if linked else "game not running - saved for next launch"
		link_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if linked else C_DIM)
		if save_t > 0.0:
			save_t -= delta
			if save_t <= 0.0:
				_save()
		if player.playing and now > stop_at:
			player.stop()
		_tick_sprites(delta)

	func _unhandled_key_input(e: InputEvent) -> void:
		var k := e as InputEventKey
		if k == null or not k.pressed or k.echo:
			return
		if k.keycode == KEY_SPACE and tabs.current_tab == 0 and selected >= 0 and rows[selected].kind in ["synth", "take", "deleted"]:
			_play(selected)
		elif k.keycode == KEY_ESCAPE:
			get_tree().quit()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
			if save_t > 0.0:
				save_t = -1.0
				_save()

	# --- sprites tab ---
	# Every sprite in a grid: ASCII-grid textures (PixelArt.texture) and live game nodes that draw themselves
	# (cars, people, birds, poles, the family car). Lists come from the game's own constants.

	func _setup_sprites_tab() -> void:
		Pedestrian.Shout.untint = false             # no world tint here
		var page := VBoxContainer.new()
		page.name = "Sprites"
		page.add_theme_constant_override("separation", 8)
		tabs.add_child(page)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 8)
		page.add_child(bar)
		bar.add_child(_label("ZOOM", 14, C_DIM))
		for z in [1, 2, 3, 4]:
			var b := _button("%dx" % z, func() -> void:
				zoom = z
				_build_sprites())
			b.custom_minimum_size.x = 44
			zoom_btns.append(b)
			bar.add_child(b)
		bar.add_child(_gap(16))
		bg_b = _button("", func() -> void:
			bg_mode = (bg_mode + 1) % BGS.size()
			_build_sprites())
		bar.add_child(bg_b)
		TimeOfDay.phase()                            # reads --phase=N first, so the cycle starts from it
		phase_b = _button("", func() -> void:
			TimeOfDay.force_phase = (TimeOfDay.phase() + 1) % TimeOfDay.PRESETS.size()
			_build_sprites())
		bar.add_child(phase_b)
		anim_b = _button("", func() -> void:
			animate = not animate
			_apply_animate())
		bar.add_child(anim_b)
		bar.add_child(_button("REROLL PEOPLE", func() -> void:
			ped_seed += 1
			_build_sprites()))
		bar.add_child(_gap(16))
		bar.add_child(_label("world tint (CanvasModulate) not applied here", 14, C_DIM))
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(sc)
		sprite_box = VBoxContainer.new()
		sprite_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sprite_box.add_theme_constant_override("separation", 4)
		sc.add_child(sprite_box)
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				img.set_pixel(x, y, Color(0.42, 0.42, 0.46) if (x < 8) == (y < 8) else Color(0.3, 0.3, 0.34))
		checker = ImageTexture.create_from_image(img)

	func _build_sprites() -> void:
		for c in sprite_box.get_children():
			sprite_box.remove_child(c)
			c.queue_free()
		live.clear()
		ticked.clear()
		loops.clear()
		for i in zoom_btns.size():
			zoom_btns[i].add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if i + 1 == zoom else C_DIM)
		bg_b.text = "BG: " + BGS[bg_mode].to_upper()
		phase_b.text = "PHASE: " + TimeOfDay.phase_name().to_upper()
		_apply_animate()

		var sec := _sprite_section("Runner", "NinjaArt frames; the scarf and katana blade are drawn by Runner")
		for k: String in NinjaArt.LEGS:
			_tex_cell(sec, "ninja %s" % k, NinjaArt.frame(k))
			_tex_cell(sec, "ninja %s slice" % k, NinjaArt.frame(k, true))
		for k: String in NinjaArt.DASH:
			_tex_cell(sec, "dash %s" % k, NinjaArt.dash_frame(k))
		for k: String in NinjaArt.DASH:
			_tex_cell(sec, "dash %s slice" % k, NinjaArt.dash_frame(k, true))
		_tex_cell(sec, "ninja ball", NinjaArt.ball())
		sec = _sprite_section("Runner states", "rim light (Dusk/Night) and death tints, as Runner draws them")
		for k: String in NinjaArt.LEGS:
			_ninja_cell(sec, "%s rim light" % k, NinjaArt.frame(k), NinjaArt.frame(k, false, true))
		_ninja_cell(sec, "dash rim light", NinjaArt.dash_frame("contact"), NinjaArt.dash_frame("contact", false, true))
		_ninja_cell(sec, "ball rim light", NinjaArt.ball(), NinjaArt.ball(true))
		_ninja_cell(sec, "hit (death tint)", NinjaArt.frame("fall"), null, Color(1.0, 0.75, 0.75))
		_ninja_cell(sec, "zapped flash", NinjaArt.frame("fall"), null, Color(3.0, 3.2, 4.0))
		_ninja_cell(sec, "zapped dark", NinjaArt.frame("fall"), null, Color(0.2, 0.2, 0.3))
		_ninja_cell(sec, "charred", NinjaArt.frame("fall"), null, Color(0.35, 0.3, 0.3))

		sec = _sprite_section("Birds")
		var bird_box := func(_n: Node2D) -> Rect2: return Rect2(-22, -38, 44, 42)
		_node_cell(sec, "perched (pecks now and then)", Bird.new(), bird_box)
		var flyer := Bird.new()
		flyer.flying = true
		_node_cell(sec, "flying right", flyer, bird_box)
		flyer = Bird.new()
		flyer.flying = true
		flyer.vx = -0.0001                            # faces left; drift is invisible
		_node_cell(sec, "flying left", flyer, bird_box)
		var pop := Bird.new()
		pop.alive = false
		_node_cell(sec, "sliced pop (loops)", pop, func(_n: Node2D) -> Rect2: return Rect2(-80, -96, 160, 160))
		_loop(pop, 0.9, func(n: Node2D) -> void:
			n.set("_dead_t", 0.0)
			var dirs: Array[Vector2] = []
			for i in 7:
				dirs.append(Vector2.from_angle(randf() * TAU) * randf_range(0.6, 1.0))
			n.set("_feathers", dirs))
		var holder := Node2D.new()
		_node_cell(sec, "feather burst (loops)", holder, func(_n: Node2D) -> Rect2: return Rect2(-200, -200, 400, 380), 1.0)
		_loop(holder, 2.8, func(n: Node2D) -> void:
			var f := Bird.Feathers.new()
			f.cols = [Bird.PIGEON.G, Bird.PIGEON.g, Bird.PIGEON.W, Bird.PIGEON.W, Bird.PIGEON.b]
			n.add_child(f))
		_tex_cell(sec, "pigeon", PixelArt.texture("pigeon", PackedStringArray(Bird.PERCHED), Bird.PIGEON))
		_tex_cell(sec, "pigeon_up", PixelArt.texture("pigeon_up", PackedStringArray(Bird.WINGS_UP), Bird.PIGEON))
		_tex_cell(sec, "pigeon_down", PixelArt.texture("pigeon_down", PackedStringArray(Bird.WINGS_DOWN), Bird.PIGEON))
		sec = _sprite_section("Feathers", "every shape x rotation frame (negative steps; positive ones draw mirrored)")
		for i in Bird.Feathers.SHAPES.size():
			for c in [["grey", Bird.PIGEON.G], ["white", Bird.PIGEON.W]]:
				for st in range(-Bird.Feathers.ROT_FRAMES, 1):
					_tex_cell(sec, "feather %d %s %+d" % [i, c[0], st], Bird.Feathers._frame(i, c[1], st))

		for m: int in Car.Model.values():
			var mname := String(Car.Model.keys()[m]).to_lower()
			sec = _sprite_section("Car: " + mname, "headlights follow the phase" if m == 0 else "")
			for st in ["driving", "oncoming", "hazard blinkers", "trunk open", "trunk knocked + junk (loops)"]:
				var car := Car.new()
				car.model = m as Car.Model
				car.preset = true
				car.vx = 120.0
				car.color = Traffic.CAR_COLORS[m % Traffic.CAR_COLORS.size()]
				car.length = 304.0 if m == Car.Model.BUS else (376.0 if m == Car.Model.TRUCK else 150.0)
				var junk := false
				match st:
					"oncoming":
						car.vx = -120.0
					"hazard blinkers":
						car.set("_hazard", 1.0e9)
					"trunk open":
						car.set("_trunk_t", 10.0)
					"trunk knocked + junk (loops)":
						car.vx = 0.0                          # junk lies still instead of sliding off
						junk = true
				_node_cell(sec, st, car, func(n: Node2D) -> Rect2:
					var c := n as Car
					var left := 190.0 if junk else 12.0
					return Rect2(-left, -c.height - 16, c.length + left + 12, c.height + 24))
				if junk:
					_loop(car, 2.6, func(n: Node2D) -> void:
						n.set("_trunk_t", -1.0)
						n.set("_junk", [])
						n.set("_clattered", false)
						(n as Car).knock_trunk())

		var rng := RandomNumberGenerator.new()
		rng.seed = ped_seed
		seed(ped_seed)                               # setup() rolls hair / bike paint on the global rng
		for k: int in Pedestrian.Kind.values():
			var kname := String(Pedestrian.Kind.keys()[k]).to_lower()
			sec = _sprite_section("Person: " + kname, "REROLL PEOPLE for other clothes / colours" if k == 0 else "")
			for st in ["look A", "look B", "oncoming", "knocked over (loops)", "stomped: shout (loops)",
					"stomped again (loops)", "umbrella (rain)", "umbrella stomped: inside-out (loops)",
					"umbrella knocked over (loops)"]:
				var p := Pedestrian.new()
				p.setup(k as Pedestrian.Kind, rng)
				p.umbrella = st.begins_with("umbrella")
				var knock: bool = st.contains("knocked")
				if st == "oncoming":
					p.vx = -40.0
				if knock:
					p.vx = 0.0
					p.knocked = true
					p.set("_knock_t", 1.0)
				var shouts: bool = st.begins_with("stomped")
				_node_cell(sec, st, p, func(n: Node2D) -> Rect2:
					var sz: Vector2 = (n as Pedestrian).size
					var ped := n as Pedestrian
					if ped.umbrella and not knock:                    # canopy above the head
						var top := ped.roof_y() - ped.position.y
						return Rect2(-sz.x / 2.0 - 24, top - 12, sz.x + 48, -top + 18)
					if shouts:
						return Rect2(-120, -sz.y - 76, 240, sz.y + 82)
					if knock:
						var reach := maxf(sz.x, sz.y)
						return Rect2(-sz.x / 2.0 - 16, -reach - 16, reach + sz.x / 2.0 + 32, reach + 40)
					return Rect2(-sz.x / 2.0 - 16, -sz.y - 16, sz.x + 32, sz.y + 22))
				if knock:
					_loop(p, 2.0, func(n: Node2D) -> void: n.set("_knock_t", 0.0))
				if st.begins_with("umbrella stomped"):
					_loop(p, 1.2, func(n: Node2D) -> void: (n as Pedestrian).set("_umb_flip", Pedestrian.UMB_FLIP))
				if shouts:
					var again: bool = st.begins_with("stomped again")
					_loop(p, 1.6, func(n: Node2D) -> void:
						var ped := n as Pedestrian
						ped.shout(Pedestrian.shout_text(ped.speaker, "again" if again else "stomp"), again))

		sec = _sprite_section("Street")
		for ob in [true, false]:
			var pole := WireGenerator.Pole.new()
			pole.top_y = 60.0
			pole.bottom_y = 260.0
			pole.lane_ys.append(60.0)
			pole.obstacle = ob
			_node_cell(sec, "pole + transformer" if ob else "pole", pole,
				func(_n: Node2D) -> Rect2: return Rect2(-44, 0, 88, 264))
		_lamp_cell(sec, "lamp (this phase)", -1, false)
		_lamp_cell(sec, "lamp lit", 0, false)
		_lamp_cell(sec, "lamp dead", 1, false)
		_lamp_cell(sec, "lamp flickering", 2, false)
		_lamp_cell(sec, "lamp bounced + sparks (loops)", 0, true)
		_lamp_cell(sec, "dead lamp fixed by a bounce (loops)", 1, true)

		sec = _sprite_section("Greenery", "one SUBURB pole span (REROLL PEOPLE reseeds); poles at the edges, lamp mid-span")
		for kind: int in [Biome.Kind.SUBURB]:
			var gr := Greenery.new()
			gr.floor_y = 280.0
			gr.seed_value = ped_seed
			gr.force_kind = kind
			gr.scroll(0.0)
			_node_cell(sec, Biome.NAMES[kind].to_lower(), gr,
				func(n: Node2D) -> Rect2: return Rect2(-8, (n as Greenery).base_y() - 230.0, 656, 246))

		sec = _sprite_section("Backdrop", "each biome's three parallax layers + haze, this phase (no sky)")
		for kind: int in Biome.Kind.values():
			var bs := Backdrop.build_set(kind, ped_seed)
			bs.scroll(0.0)
			_node_cell(sec, Biome.NAMES[kind].to_lower(), bs, func(_n: Node2D) -> Rect2: return Rect2(0, 180, 1280, 440))

		sec = _sprite_section("Kid's car / cabin", "kid textures at 4 px per art pixel x zoom (8 px in the menu)")
		_tex_cell(sec, "kid", Cabin.kid_texture(false), 4.0)
		_tex_cell(sec, "kid blink", Cabin.kid_texture(true), 4.0)
		_tex_cell(sec, "kid_small", PixelArt.texture("kid_small", PackedStringArray(Cabin.KID_SMALL),
			Cabin.KID_PALETTE), 4.0)
		for lit in [false, true]:
			var fam := Cabin.FamilyCar.new()
			fam.lights = lit
			ticked.append(fam)
			_node_cell(sec, "family car, lights " + ("on" if lit else "off"), fam,
				func(_n: Node2D) -> Rect2: return Rect2(-8, -240, 472, 252))
		for g in [1.0, 0.0]:
			var interior := Cabin.Interior.new()
			interior.glass = g
			if g > 0.0:
				ticked.append(interior)
			_node_cell(sec, "interior, glass reflections " + ("on" if g > 0.0 else "off (zoomed in)"), interior,
				func(_n: Node2D) -> Rect2: return Rect2(Vector2.ZERO, Cabin.VIEW), 0.5)

	## Ninja frame as Runner draws it: optional rim-light silhouette behind (offset 1 art px up-left), tint.
	func _ninja_cell(flow: HFlowContainer, title: String, tex: Texture2D, sil: Texture2D, mod := Color.WHITE) -> void:
		var art := Vector2(tex.get_size())
		var s := _fit(art * PixelArt.PX)
		var stage := _cell(flow, "%s\nx%d" % [title, s])
		var pad := PixelArt.PX * s
		stage.custom_minimum_size = art * PixelArt.PX * s + Vector2(pad, pad)
		for layer in [[sil, Color(1.8, 2.1, 2.8, 0.85), Vector2.ZERO], [tex, mod, Vector2(pad, pad)]]:
			if layer[0] == null:
				continue
			var tr := TextureRect.new()
			tr.texture = layer[0]
			tr.self_modulate = layer[1]
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.position = layer[2]
			tr.size = art * PixelArt.PX * s
			stage.add_child(tr)

	## A Street cut down to one lamp k. fault -1 = as this phase has it; 0 lit, 1 dead, 2 flickering (forced
	## to night power). bounce = the runner bounces on it every 1.6 s (sparks; a faulty lamp gets fixed).
	func _lamp_cell(flow: HFlowContainer, title: String, fault: int, bounce: bool) -> void:
		var st := Street.new()
		st.floor_y = 0.0
		var k := 0
		if fault >= 0:
			st.set("_phase", TimeOfDay.Phase.NIGHT)
			st.set("_lamp_energy", 1.0)
			while st._fault(k) != fault:
				k += 1
		var bx := Street.LAMP_OFFSET + k * Street.LAMP_SPACING
		st.cam_x = bx
		_node_cell(flow, title, st, func(_n: Node2D) -> Rect2: return Rect2(bx - 110, -260, 240, 280))
		for l: PointLight2D in st.get("_lights"):    # real lights would light up the dashboard UI too
			l.queue_free()
		st.get("_lights").clear()
		if fault >= 0:                               # _ready set them from the phase: force them again
			st.set("_phase", TimeOfDay.Phase.NIGHT)
			st.set("_lamp_energy", TimeOfDay.PRESETS[TimeOfDay.Phase.NIGHT].lamps)
		if bounce:
			_loop(st, 1.6, func(n: Node2D) -> void:
				n.set("_fixed", {})
				for lamp: Street.Lamp in n.get("_lamps"):
					if lamp.k == k:
						lamp.bounced())

	## Call f(node) now and every `period` s while animating (replays one-shot states).
	func _loop(node: Node2D, period: float, f: Callable) -> void:
		loops.append({"node": node, "period": period, "t": 0.0, "f": f})
		f.call(node)

	## Section header + the flow container its cells go in.
	func _sprite_section(title: String, note := "") -> HFlowContainer:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		var l := _label(title.to_upper(), 20, Color(1.0, 0.85, 0.4))
		l.add_theme_font_override("font", bold)
		head.add_child(l)
		if note != "":
			head.add_child(_label(note, 14, C_DIM))
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_top", 12)
		m.add_child(head)
		sprite_box.add_child(m)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		sprite_box.add_child(flow)
		return flow

	## A cell: background stage (clipped) + caption. Returns the stage; its caption is meta "label".
	func _cell(flow: HFlowContainer, title: String) -> Control:
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_ROW
		sb.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		panel.add_child(v)
		var stage := Control.new()
		stage.clip_contents = true
		stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		v.add_child(stage)
		match BGS[bg_mode]:
			"checker":
				var tr := TextureRect.new()
				tr.texture = checker
				tr.stretch_mode = TextureRect.STRETCH_TILE
				tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				stage.add_child(tr)
			_:
				var cr := ColorRect.new()
				cr.color = Color(0.03, 0.03, 0.05) if bg_mode == 0 else Color(0.84, 0.86, 0.9)
				cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				stage.add_child(cr)
		var l := _label(title, 13, Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		stage.set_meta("label", l)
		flow.add_child(panel)
		return stage

	## Biggest whole zoom (<= the chosen one) that keeps a stage of base size `sz` under MAX_CELL wide.
	func _fit(sz: Vector2) -> int:
		var s := zoom
		while s > 1 and sz.x * s > MAX_CELL:
			s -= 1
		return s

	## ASCII-grid texture at `px` screen px per art pixel (PixelArt.PX in the world) times the zoom.
	func _tex_cell(flow: HFlowContainer, title: String, tex: Texture2D, px := PixelArt.PX) -> void:
		var art := Vector2(tex.get_size())
		var s := _fit(art * px)
		var stage := _cell(flow, "%s\n%dx%d  x%d" % [title, art.x, art.y, s])
		stage.custom_minimum_size = art * px * s
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(tr)

	## A real game node drawing itself. `bounds(node)` (node-local px, read after it entered the tree, so
	## per-model sizes are set) frames it; `fixed` overrides the zoom.
	func _node_cell(flow: HFlowContainer, title: String, node: Node2D, bounds: Callable, fixed := 0.0) -> void:
		var stage := _cell(flow, title)
		var holder := Node2D.new()
		holder.process_mode = Node.PROCESS_MODE_INHERIT if animate else Node.PROCESS_MODE_DISABLED
		stage.add_child(holder)
		holder.add_child(node)
		var b: Rect2 = bounds.call(node)
		var s := fixed if fixed > 0.0 else float(_fit(b.size))
		stage.custom_minimum_size = (b.size * s).round()
		holder.scale = Vector2(s, s)
		holder.position = (-b.position * s).round()
		if fixed <= 0.0:
			(stage.get_meta("label") as Label).text += "\nx%d" % int(s)
		live.append(holder)

	func _apply_animate() -> void:
		anim_b.text = "ANIMATE: " + ("ON" if animate else "OFF")
		for h in live:
			if is_instance_valid(h):
				h.process_mode = Node.PROCESS_MODE_INHERIT if animate else Node.PROCESS_MODE_DISABLED

	## FamilyCar / Interior are animated by Cabin in the game; tick them here.
	func _tick_sprites(delta: float) -> void:
		if not animate or tabs.current_tab != 1:
			return
		for l in loops:
			if not is_instance_valid(l.node):
				continue
			l.t += delta
			if l.t >= l.period:
				l.t = 0.0
				l.f.call(l.node)
		for n in ticked:
			if not is_instance_valid(n):
				continue
			n.set("t", float(n.get("t")) + delta)
			if n is Cabin.FamilyCar:
				n.spin += delta * 4.0
			n.queue_redraw()

	func _gap(w: float) -> Control:
		var c := Control.new()
		c.custom_minimum_size.x = w
		return c

	# --- widgets ---

	func _status(t: String, err := false) -> void:
		status.text = t
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5) if err else Color(0.7, 1.0, 0.7))

	func _label(t: String, size: int, c: Color) -> Label:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", c)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return l

	func _button(t: String, f: Callable) -> Button:
		var b := Button.new()
		b.text = t
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(f)
		return b
