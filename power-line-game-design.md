# Window Runner — Game Design Doc (v0.1)

> Working title. A 2D pixel-art endless runner based on the childhood daydream of imagining someone running along the street power lines while looking out the backseat car window.

---

## 1. Concept

As kids, many of us stared out of the car window and imagined a tiny figure running alongside the car — sprinting along the power lines, leaping obstacles, keeping pace. This game turns that daydream into an endless runner.

The player controls an imaginary **ninja** who runs **on top of the power lines** (the wire itself is the ground), drops down to the street when needed, dodges traffic and pedestrians, slices birds, and chains hops across car roofs.

**Pillars**
1. **Nostalgia** — it should feel like a memory, not just a runner.
2. **Flow** — rhythmic, readable movement; the sag of the wire sets the beat.
3. **Risk vs. reward** — the wires are safer, the street is where the big points are.

---

## 2. Intro Sequence

A short, non-interactive cutscene at the start of each session:

1. Camera starts **outside a moving car** on a city road.
2. Zooms **inside the car** to show the kid sitting in the backseat looking out the window.
3. Zooms **into the side window** — the view through the glass becomes the game screen.
4. Gameplay begins. The car and kid are **not shown again** after this.

Since sessions always start at Dawn (see §6), the intro always plays in dawn lighting.

---

## 3. Core Gameplay

### 3.1 Camera
- Side-scrolling, auto-scrolls to the right (this is "the car's" speed).
- Scroll speed gradually increases with distance.

### 3.2 Two layers of play

**Wire layer (upper)**
- The runner runs **on the power line itself**, not pole-to-pole.
- **Wire sag is terrain**: each span dips in the middle and rises toward the poles → natural downhill/uphill rhythm (optional momentum: faster on the dip, slower on the climb).
- **Pole tops** (crossarms, insulators) are obstacles to hop over.
- **Multiple wires at different heights** act as lanes — jump up / drop down between them.
- **Junctions** where wires branch toward side streets — choose a branch; some branches end, forcing a drop to the street.
- **Birds** sit on the wires and must be **sliced**.
- Generally the "safer" layer.

**Street layer (lower)**
- Reached by dropping off the wire on purpose, or when the power lines end.
- **Falling off the wire is NOT a fail** — it just puts you on the road/sidewalk.
- Dodge **cars** and **pedestrians**.
- **Car hopping**: with correct timing, the player can land on car roofs and hop consecutively from car to car → combo points.
- Riskier, but the only place to earn car-hop points.

### 3.3 Power line return
- Power lines reappear via **weighted procedural generation** ("well-algorithmized randomness") — unpredictable but fair.
- The player jumps back up onto the wire when it returns.
- Generation rules to tune: min/max length of wire sections and street sections, guaranteed safe landing windows, difficulty scaling with distance.

---

## 4. Controls

| Action | Purpose |
|---|---|
| **Jump** (double jump: press again in mid-air) | Hop obstacles, land on car roofs, bounce off people/birds, get back onto the wire from the street (needs the double jump) |
| **Slice** | Cut down birds on the wire |
| **Drop** | Step off the wire to a lower wire or down to the street |

Keep it to three buttons. Must feel good on keyboard and controller.

---

## 5. Fail & Scoring

### Lose conditions (run ends on)
- Running into a **car** (side collision — landing on top is a hop, not a crash)
- Running into a **person** (pedestrians are dodged only, never sliced)
- Running into a **bird you didn't slice**
- Touching a **pole-top transformer** (electrocuted) — only some poles have one

On a loss the kid's car keeps driving: the camera scrolls on and the runner is left behind before the game-over screen appears.

### Not a fail
- Falling off the wire → you land on the street and keep running.

### Score
- **Distance** travelled.
- **Car-hop bonus** — points for each car hop, multiplied for consecutive hops (combo chain).

---

## 6. Time of Day

Time of day changes **between rounds**, not during a run. Every **2 rounds** it advances to the next phase:

**Dawn → Morning → Afternoon → Dusk → Night → (loop back to Dawn)**

- Full cycle = 10 rounds.
- Phase index: `(round / 2) % 5` (integer division).
- **Resets to Dawn** every time the game is launched (not saved).

| Phase | Mood / gameplay ideas |
|---|---|
| Dawn | Soft pink-orange haze, empty roads, early birds on the wires |
| Morning | Bright and clear, traffic picking up |
| Afternoon | Peak traffic — most car-hop chances, most danger |
| Dusk | Gradient sky, street lights flickering on, long shadows |
| Night | Dark, sodium street lights, headlights glowing, strongest wet-road reflections; wires harder to see except near lights |

Implementation: each phase = one lighting preset (sky gradient, `CanvasModulate` tint, parallax layer brightness, which lights are on).

---

## 7. Art Direction

- **Style**: detailed ("hyper") pixel art, more expressive animation.
- **Primary inspiration**: *Kingdom: New Lands* / *Kingdom Two Crowns* — chunky pixels with soft painterly lighting, gradient skies, hazy layered parallax, water reflections.
- **Other references**: *The Last Night* (detailed pixel city), *Katana ZERO* (city/rooftops), *Owlboy* (expressive characters).
- **Setting**: a **generic city** — no specific local elements.
- **Colors**: casual daytime palette, shifting per time-of-day phase.
- **Signature effect**: **wet-road reflections** in the bottom strip of the screen (our version of Kingdom's water reflection).
- **Parallax**: far buildings hazy/desaturated, near street detailed/saturated.
- **Car framing**: subtle — no heavy window border during gameplay.

### Runner — the Ninja
- Hooded dark ninja with katana (reference sprite provided).
- **Readability fix**: add a bright trailing accent (e.g. red/orange scarf or headband) + subtle rim light at night, so he doesn't disappear in Dusk/Night phases.
- Expressive animations: run, lean, crouch-before-jump, jump, land, slice, roll/land on car roof, hit/fail.

---

## 8. Tech

- **Engine**: Godot 4 (GDScript), developed on Linux.
- **Targets**: Windows + Linux (Linux covers Steam Deck).
- **Art tools**: Aseprite.
- **Useful nodes**: `Line2D` (wire with sag curve), `ParallaxBackground`, `CanvasModulate`, `PointLight2D` for street lights at night.
- **Reflections**: shader that mirrors/distorts the scene into the road strip.

---

## 9. Build Plan

### Milestone 1 — Gray-box prototype
- Auto-scrolling camera
- Procedural poles + sagging wire (`Line2D`)
- Runner that sticks to the wire, jumps, drops
- Placeholder birds + slice
- Goal: running on the wire **feels good** with just boxes

### Milestone 2 — Street layer
- Drop to street, power lines ending / returning (weighted random generator)
- Cars + pedestrians, collision rules
- Car-roof hopping + combo scoring
- Distance score + game over + restart

### Milestone 3 — Look & feel
- Ninja sprite + animations
- Parallax city layers
- Time-of-day presets + round counter
- Wet-road reflection shader
- Intro cutscene (outside car → kid → window)

### Milestone 4 — Ship
- Audio (engine hum, wind, city ambience, music)
- Menus, settings
- Free demo on itch.io → feedback → Steam ($100 USD Steam Direct fee per game, recoupable after $1,000 in sales)

---

## 10. Open Questions
- Final game title
- Does scroll speed ever slow down (e.g. traffic lights / "car stops")?
- Any power-ups or unlockables (e.g. ninja skins)?
- ~~Music direction~~ — decided: dreamy lo-fi chiptune, one procedural song per time of day (see §11)
- High score saving / leaderboard

---

## 11. As-built changes (Phase 2)

Where the build deviates from or extends the sections above:

- **One wire per pole** (not multiple lanes): lower wires caught every jump off a car roof. The wire sits high (y250); reaching it from the street/roof takes a double jump. Multi-lane/junctions (§3.2) are deferred; the code still supports multiple `lane_y`.
- **Double jump** added to Jump (§4): second jump in mid-air, refreshed on every landing and bounce.
- **Wire runs and street runs** (§3.3): sequential weighted generator, wire 3–8 spans, street 1–4, harder with distance. Traffic never meets the runner in the 700 px after a wire ends or 500 px before it returns.
- **Birds**: perched single, perched line of 2–4, flying mid-air, and long **frenzy** wire runs (5–8 spans) packed with perched birds for a slicing/stomping spree. Birds can also be **stomped** (bounce, bird dies).
- **People** (§3.2): walkers, groups, children, joggers, cyclists and fast oncoming motorcyclists. All kill on side contact (§5) but can be **bounced off** (landing on the head), which scores a bonus and chains the combo.
- **Cars** are stood on (hop chains); people/birds are bounced off, never stood on.
- **Scoring** (§5): distance (m) + `100 × combo × target bonus` per hop. Target bonus: car 1x, street lamp 1x (bounce), walker/group 2x, bird 2x, child/jogger 3x, cyclist 4x, motorcycle 6x. Combo = consecutive hop targets without touching street/wire. Game over screen shows cause, score, distance, hop points, session best (not saved to disk; §10 high-score question still open).
- **Transformers** sit on only some poles (≈20% → 45% of eligible poles with difficulty), never where the wire ends/returns or inside frenzy runs. Touching one is fatal.
- **Slice** (§4) is tuned for mashing: hitbox starts on the press frame, 0.10 s swing + 0.10 s cooldown, presses buffered 0.15 s, 130 px reach. Slicing birds scores `50 × slice chain` (chain window 1.2 s, cap x10) with a small camera shake and a feather pop.
- **Look (Milestone 3, built)**: art is procedural pixel art in code (ASCII sprite grids + pixel-snapped drawing) standing in for Aseprite sheets. The pole obstacle is a pole-top transformer with a hazard band. Each loss cause has its own death animation; sliced/stomped birds leave drifting feathers. Time of day changes every 2 rounds as specified; each preset also scales traffic (sparse Dawn → peak Afternoon) and bird density (more at Dawn). Night: sodium lamps (Dusk: some still flickering on), headlight beams, rim-lit ninja, strongest reflections.
- **Intro + menus (§2, built)**: once per launch the family car drives in → push into the rear window → back seat, kid (yellow hoodie) watching the city through a window that is a hole in the drawn interior (the live game world). That shot is the **start menu** (title, PRESS SPACE TO START, controls); pressing zooms into the window until it fills the screen and the ninja pops in on the wire. On a loss the camera **zooms back out** of the window to the kid and the **game-over menu** (stats panel over the glass); retry fades to black and zooms back in. R restarts instantly. Font: Press Start 2P (OFL).
- **Audio (Milestone 4, built)**: every sound is synthesized in code (no asset files; files dropped into `audio/` replace sounds by name). In the menu we're inside the car: engine drone, the world muffled through the glass, the music soft like a car radio; zooming into the window opens the sound up and the drums come in (the daydream starts). Music: dreamy lo-fi chiptune, one 8-bar loop per time of day (Dawn slow and sparse … Night minor and crackly), layered by play state — the lead melody joins as speed rises or on a combo / slice chain, and dying stops it like a tape. Slice chains, hop combos and the score count-up climb the song's scale. Positional world sounds double as cues: transformers hum, incoming motorbikes and flying birds are audible before they arrive. Ambience per phase: city rumble, wind that grows with speed, songbirds at dawn, crickets at night. M mutes (saved). Exceptions that are real recordings: every vehicle type honks its own horn when you land on it (CC0 field recordings; tap → beep-beep → angry as you keep landing on the same car, taxis angrier, trucks/buses long blasts), and stomped people shout ("Hey!", "Whoa!", kids "Whee!"; "Ow!" when knocked down) through a cheap-speaker "futz" filter, each person with their own voice and pitch (CC0 placeholder voices for now; the developer will record their own).
- **Not done yet**: settings menu (volume sliders), itch.io demo.
