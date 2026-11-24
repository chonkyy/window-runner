# Civilian voices

The files here now are **CC0 placeholders** from Freesound (see `../CREDITS.md`). Overwrite them with your own
takes (same names), or delete them and add yours; remove their rows from CREDITS.md when they're gone.

Drop recordings here and the game picks them up by name (no code changes). Shouts are played through the
in-game "futz" (the Voice bus: a cheap-speaker / walkie-talkie filter), so record them clean and dry, with no
effects.

```
voices/man/stomp_1.wav      voices/woman/stomp_1.wav      voices/kid/stomp_1.wav
voices/man/again_1.wav      ...                           ...
voices/man/hurt_1.wav
```

- Speakers: `man`, `woman`, `kid`.
  - Every person in the street gets one speaker (kids are always `kid`) and their own slight pitch.
  - A speaker folder with no files borrows the man's takes, pitched up (×1.22 for woman, ×1.42 for kid).
- Situations, by file-name prefix:
  - `stomp_*` plays when you first land on their head: "Hey!", "Whoa!", "Oi!", "Huh?!", "Yo!" (kid: "Whee!").
  - `again_*` plays when you stomp the same person again: "HEY!", "Ow!", "Seriously?!".
  - `hurt_*` plays when you run into them and knock them down: "Ow!", "Oof!", "Ugh!".
- Aim for 4–6 `stomp`, 2–3 `again` and 2–3 `hurt` takes per speaker, each said differently. A random take is
  picked each time, never the same one twice in a row.
- Speech bubble: a stomped person shows their shout in a comic bubble. Write what each take says in
  `voices/captions.cfg` (`[man]` then `stomp_2="OI!"`); takes without a caption show a random fitting line.
- Formats: `.wav`, `.ogg` or `.mp3`. Keep each file to the shout only, without long silence at the start.
- Open the project once (or run `godot --headless --import --path .`) after adding files, so Godot imports them.
- Test with the soundboard: `godot --path . --script tools/soundboard.gd`, then press `V`.
- Birds: `voices/bird/squawk_*` plays (random take, slight random pitch) whenever a bird dies — sliced,
  stomped, or run into. Same futz as the shouts. Test the rows in the sound dashboard ("bird squawk").
