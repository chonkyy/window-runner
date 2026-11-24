# Window Runner

An endless runner made in Godot 4. A kid stares out of the back window of the family car and pictures a ninja keeping pace outside. The ninja runs along the power lines, slices pigeons, hops across car roofs and bounces off pedestrians, and drops to the street wherever the wire runs out. Don't touch the pole transformers.

Almost everything is generated in code: the pixel art, the parallax city and suburb, the time-of-day lighting, rain, and the synthesized sound effects. Music comes from a car radio with 5 procedural stations. The only recorded audio is the vehicle horns and the people's shouts.

## Install and run (desktop)

1. Install **Godot 4.7** (standard build, not .NET) from https://godotengine.org/download, or with your package manager (`pacman -S godot`, `flatpak install flathub org.godotengine.Godot`, etc.).
2. Clone the repo:
   ```sh
   git clone https://github.com/chonkyy/window-runner.git
   cd window-runner
   ```
3. Import the assets once, then run the game:
   ```sh
   godot --headless --import --path .
   godot --path .
   ```
   You can also open `project.godot` in the Godot editor and press **F5**.

### Handy launch options

Put these after `--`, for example `godot --path . -- --no-intro --phase=4`:

| Option | Effect |
|---|---|
| `--no-intro` | Skip the intro and start menu |
| `--phase=N` | Time of day: 0 Dawn … 4 Night |
| `--seed=N` | Replay a level layout |
| `--biome=N` | 0 city, 1 suburb |
| `--rain=N` | 0 dry, 1 light, 2 heavy |
| `--touch` | Use the mouse as a finger to test the touch controls |
| `--wide=1600` | Test a 20:9 phone layout |

## Install on Android

No release build is published yet. To build a debug APK yourself and sideload it:

1. In Godot, go to **Editor → Manage Export Templates** and install the templates for 4.7.2.
2. Set up the Android export: you need **JDK 17**, and the Android SDK `platform-tools` and `build-tools` (for `adb`, `apksigner` and `zipalign`). Point to them under **Editor Settings → Export → Android**. Godot creates a debug keystore on its own.
3. Build the APK and install it on a phone with USB debugging turned on:
   ```sh
   godot --headless --path . --export-debug "Android" build/window-runner.apk
   adb install -r build/window-runner.apk
   ```
   The APK is built for arm64 phones only.

## Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Jump (press again in the air to double jump) | Space / W / Up | A | JUMP button |
| Slice | J / X | X | Tap the right side |
| Drop down | S / Down | B | DROP button |
| Next radio station | R | Y | Radio icon |
| Pause | Esc / P | Start | Pause icon / Back |
| Mute | M | | |
| Fullscreen | F11 | | |

## Credits

- Font: [Press Start 2P](fonts/OFL.txt) (SIL Open Font License)
- Horn and voice recordings: CC0 sounds from Freesound, listed in [audio/CREDITS.md](audio/CREDITS.md)
