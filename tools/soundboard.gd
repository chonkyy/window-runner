extends SceneTree
## Sound tuning by ear (Phase 4): `godot --path . --script tools/soundboard.gd`
##   Up/Down select a sound, Space/Enter play it, Left/Right scale step (pitch via Sound.note, for tuned sounds)
##   P render + play this station's song for the next time of day, S the next radio station (same time of day),
##   1-4 toggle its stems (PAD BASS DRUMS LEAD), 0 stop, Esc quit
##   H next vehicle: its recorded horn as tap, double, angry (audio/horns/<vehicle>/)
##   V next speaker x situation: a random recorded shout through the Voice bus futz (audio/voices/<speaker>/)
## Synth sounds play straight from SoundBank / Music (the raw recipe); voices go through the game's Voice bus.

var board: Board


func _initialize() -> void:
	board = Board.new()
	root.add_child(board)


class Board extends Control:
	var sel := 0
	var step := 0
	var phase := -1
	var stems := [true, true, true, true]
	var label: Label
	var player: AudioStreamPlayer
	var music: AudioStreamPlayer
	var song: AudioStreamSynchronized
	var horn_i := -1
	var voice_i := -1
	var last := ""
	var files := {}

	func _ready() -> void:
		Sound.setup_buses()
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.05, 0.1)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		label = Label.new()
		label.position = Vector2(24, 16)
		label.add_theme_font_size_override("font_size", 16)
		add_child(label)
		player = AudioStreamPlayer.new()
		add_child(player)
		music = AudioStreamPlayer.new()
		add_child(music)
		_refresh()

	func _unhandled_key_input(e: InputEvent) -> void:
		var k := e as InputEventKey
		if k == null or not k.pressed or k.echo:
			return
		var names: Array = SoundBank.NAMES
		match k.keycode:
			KEY_UP:
				sel = posmod(sel - 1, names.size())
			KEY_DOWN:
				sel = posmod(sel + 1, names.size())
			KEY_LEFT:
				step = maxi(step - 1, 0)
			KEY_RIGHT:
				step = mini(step + 1, 9)
			KEY_SPACE, KEY_ENTER:
				player.stream = SoundBank.build(names[sel])
				player.pitch_scale = Sound.note(step) if step > 0 else 1.0
				player.play()
			KEY_P:
				phase = (phase + 1) % TimeOfDay.PRESETS.size()
				await _render_song()
			KEY_S:
				Radio.station = (Radio.station + 1) % Radio.count()
				phase = maxi(phase, 0)
				await _render_song()
			KEY_1, KEY_2, KEY_3, KEY_4:
				var i: int = k.keycode - KEY_1
				stems[i] = not stems[i]
				_apply_stems()
			KEY_0:
				music.stop()
			KEY_H:
				horn_i = (horn_i + 1) % Sound.HORNS.size()
				_horn_demo(Sound.HORNS[horn_i])
			KEY_V:
				voice_i = (voice_i + 1) % (Sound.SPEAKERS.size() * Sound.SITUATIONS.size())
				var sp: String = Sound.SPEAKERS[floori(voice_i / float(Sound.SITUATIONS.size()))]
				var sit: String = Sound.SITUATIONS[voice_i % Sound.SITUATIONS.size()]
				var key := "voices/%s/%s" % [sp, sit]
				var pitch := 1.0
				if _files(key).is_empty() and sp != "man":
					key = "voices/man/" + sit
					pitch = Sound.SPEAKER_PITCH.get(sp, 1.0)
				last = "%s %s: %d takes%s" % [sp, sit, _files(key).size(),
					"" if pitch == 1.0 else " (man's, pitched x%.2f)" % pitch]
				_play_seq([key], 0.0, "Voice", pitch)
			KEY_ESCAPE:
				get_tree().quit()
		_refresh()

	func _render_song() -> void:
		TimeOfDay.force_phase = phase
		label.text = "rendering %s %s ..." % [Radio.label()[1], TimeOfDay.NAMES[phase]]
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		song = Music.render(Radio.current(), Music.seed_for(Radio.station, phase))
		last = "rendered in %d ms" % (Time.get_ticks_msec() - t0)
		music.stream = song
		_apply_stems()
		music.play()

	func _files(key: String) -> Array:
		if not files.has(key):
			files[key] = Sound.pool_files(key)
		return files[key]

	## Random files from pools, back to back (a new player each, so tails overlap like in the game).
	func _play_seq(keys: Array, gap: float, bus := "World", pitch := 1.0) -> void:
		for k in keys:
			var pool := _files(k)
			if pool.is_empty():
				continue
			var s: AudioStream = pool[randi() % pool.size()]
			var p := AudioStreamPlayer.new()
			p.stream = s
			p.bus = bus
			p.pitch_scale = pitch
			add_child(p)
			p.finished.connect(p.queue_free)
			p.play()
			await get_tree().create_timer(s.get_length() / pitch + gap).timeout

	func _horn_demo(v: String) -> void:
		var tap := "horns/%s/tap" % v
		var lean := "horns/%s/long" % v
		last = "%s horn: %d taps, %d longs  (tap .. double .. angry)" % [v, _files(tap).size(), _files(lean).size()]
		await _play_seq([tap], 0.0)
		await get_tree().create_timer(0.5).timeout
		await _play_seq([tap, tap], 0.06)
		await get_tree().create_timer(0.5).timeout
		await _play_seq([tap, tap, lean], 0.06)

	func _apply_stems() -> void:
		if song:
			for i in Music.STEMS:
				song.set_sync_stream_volume(i, 0.0 if stems[i] else -80.0)

	func _refresh() -> void:
		var names: Array = SoundBank.NAMES
		var lines := []
		var first := clampi(sel - 12, 0, maxi(names.size() - 26, 0))
		for i in range(first, mini(first + 26, names.size())):
			var tag := " (loop)" if SoundBank.LOOPS.has(names[i]) else ""
			lines.append(("> " if i == sel else "  ") + names[i] + tag)
		var song_txt := "none (P / S)" if phase < 0 else "%s %s  %s %d bpm" % [" ".join(Radio.label()),
			Radio.STATIONS[Radio.station].style, TimeOfDay.NAMES[phase], Radio.current().bpm]
		var st := ""
		for i in Music.STEMS:
			st += "%d:%s%s " % [i + 1, ["PAD", "BASS", "DRUMS", "LEAD"][i], "" if stems[i] else "(off)"]
		label.text = "SOUNDBOARD   step %d (pitch x%.2f)\nsong: %s   %s\nP phase  S station  H horns  V voices   %s\n\n%s" % [step,
			Sound.note(step) if step > 0 else 1.0, song_txt, st, last, "\n".join(lines)]
