# Z-Moves

A Pokémon Sun/Moon-inspired Z-Moves mod for Gen1Recomp, featuring Z-Crystals,
powerful Z-Moves, animations, and trainer battles.

For Pokémon Red, Blue and Yellow. It is an ordinary mod: it does not patch,
replace or rebuild any Gen1Recomp file, and it only uses the public mod API.

**Version 0.7.0** · [Changelog](CHANGELOG.md)

## Features

- Z-Moves for all 15 Gen 1 types, with Sun/Moon power and rules.
- Status Z-Moves: stat boosts, stat resets and full heals.
- Species-exclusive Z-Moves: Catastropika, Pulverizing Pancake, Genesis
  Supernova and Extreme Evoboost.
- A **Z-RING** key item in the bag, with your crystal collection, your
  party's crystals and a Z-Move record.
- Z-Crystals earned through the story, each with the key-item fanfare.
- Gym Leaders, Giovanni, the Elite Four, the Champion and the rival (from
  Silph Co. on) use Z-Moves too, with an optional Z-Ring warning.
- Every Z-Move has its own animation.
- A slim one-line preview bar that keeps the battle screen visible, in the
  classic and the widescreen battle layout.

## Installing

1. Download `z_moves_v0.7.0.zip` from the latest release, or the repository
   as a ZIP.
2. Unzip it into Gen1Recomp's `mods/` folder, so `manifest.json` sits
   directly inside the mod's folder (for example `mods/z_moves/manifest.json`).
3. Enable **Z-Moves** in the mod manager and start a Red, Blue or Yellow game.

Works on Android and Windows. An existing save is fine, even a finished one:
crystals for milestones you have already passed are there straight away, and
the Z-RING goes into your bag on your first step.

## Options

| Option | Default | What it does |
|---|---|---|
| Z-CRYSTALS | STORY | STORY: earn the Z-RING and each crystal as you play. ALL: every crystal from the start. |
| TRAINER Z-MOVES | ON | Gym Leaders, Giovanni, the Elite Four, the Champion and the rival from Silph Co. on use one Z-Move per battle. |
| Z-RING WARNING | ON | A line when such a trainer's battle opens: "MISTY wears a Z-RING!". It never says which Pokémon or move. |
| Z-MOVE ANIMATIONS | ON | ON: every Z-Move plays its own full animation. OFF: one vanilla animation of its type. |

## Using it

0. **Get the Z-Ring.** Oak hands it over with the POKéDEX, together with
   Normalium Z. The other crystals come from the story (below).
1. **Give a crystal.** Party menu → pick a Pokémon → **Z-CRYSTAL**. Crystals
   that match one of its damaging moves are listed first and marked `OK`.
   Once one is held, the row reads `Z:ELECTRIC` (or `Z:PIKANIUM`), so the
   party menu shows what each Pokémon holds. The crystal stays with that
   Pokémon (PC, save, reload) until you take it back with **TAKE CRYSTAL**.
2. **Arm Z-Power.** In battle, open FIGHT and press **START**. Moves that can
   become a Z-Move are marked with a `Z` (beside the list in the classic
   layout, on the box border in widescreen). Once armed, a slim bar shows
   the Z-Move's name and power for the highlighted move. START again
   cancels. START on the FIGHT/PKMN/ITEM/RUN menu also arms it.
3. **Pick the move.** The Pokémon unleashes the Z-Move for that type.

The bar reads like `Z:GIGAVOLT HAVOC 175` for a damaging move and
`Z:THUNDER WAVE SPC+1` for a status move. Names too long for it scroll
through. If Z-Power can't be used it says why: `Z:ALREADY USED`,
`Z:NO Z-RING YET`, `Z:NO CRYSTAL HELD` or `Z:NO MATCHING MOVE`.

## The Z-RING

**USE** the Z-RING in the bag:

- **CRYSTALS:** every crystal you have earned, marked `HELD` when a party
  Pokémon holds it; unearned ones are blank. Pick one to see what it does.
- **PARTY:** each party Pokémon and the crystal it holds.
- **RECORD:** how many Z-Moves you have used, how many trainers have used
  against you, and your most used Z-Move.

Gen 1's bag has 20 slots. If it is full when you earn the ring, you still
get the message and fanfare, and the Z-RING goes into the bag on the first
step after you make room.

## Earning the crystals

| Crystal | Earned by |
|---|---|
| Z-Ring + Normalium Z | getting the POKéDEX from Oak |
| Buginium Z | beating a trainer in Viridian Forest |
| Rockium Z | beating Brock |
| Waterium Z | beating Misty |
| Electrium Z + Pikanium Z | beating Lt. Surge |
| Grassium Z + Eevium Z | beating Erika |
| Fightinium Z | beating the Karate Master in Saffron |
| Ghostium Z | calming the ghost Marowak in Pokémon Tower |
| Flyinium Z | getting HM02 Fly |
| Snorlium Z | battling either Snorlax |
| Poisonium Z | beating Koga |
| Psychium Z | beating Sabrina |
| Firium Z | beating Blaine |
| Groundium Z | beating Giovanni in Viridian Gym |
| Icium Z | battling Articuno |
| Dragonium Z | beating Lance |
| Mewnium Z | battling Mewtwo |

The message and the key-item fanfare come the next time you take a step on
the map, once any cutscene has finished. A missed message (a crash, a reset,
the Hall of Fame) still shows later.

## Trainers with Z-Power

Like the Kahunas in Sun/Moon, the big fights use Z-Moves against you:
every Gym Leader, Giovanni, the Elite Four, the Champion, and the rival from
Silph Co. on (Silph Co. and Route 22).

- Their **last Pokémon** holds the crystal.
- It is **their own type** (Brock Rock, Misty Water, Lance Dragon...) when
  that Pokémon knows a damaging move of it; otherwise the type of its
  strongest damaging move. The rival and Champion always use the strongest.
- They use it **the first turn they can**, once per battle. A turn they
  spend on an item or a switch, or lose to sleep or paralysis, does not use
  it up.
- Same rules as yours: Sun/Moon power, never misses, own animation.

## Animations

Every Z-Move has its own animation, built from the game's own pieces when
the mod loads: a Z-Power charge-up on a dark screen, two signature
animations of its type back to back (Gigavolt Havoc: Thunderbolt, then
Thunder), then a double flash and a screen shake. Extreme Evoboost charges
up through Growth, Swords Dance and Agility instead. Every one ends with the
normal palette back and both Pokémon in place.

## Rules (as in Sun/Moon)

- One Z-Move per battle for you and one for the trainer.
- Z-Power is spent when the Z-Move fires. If sleep, paralysis, confusion or
  a flinch stops the Pokémon, it keeps its Z-Power for a later turn (arm it
  again).
- The move must be a damaging move of the crystal's type.
- Power comes from the base move: up to 55 → 100, 60–65 → 120, 70–75 → 140,
  80–85 → 160, 90–95 → 175, 100 → 180, 110 → 185, 120–125 → 190, 130 → 195,
  140+ → 200. OHKO moves → 180; Seismic Toss, Night Shade, Sonicboom, Dragon
  Rage, Psywave, Super Fang, Counter and Bide → 100; Mega Drain → 120.
- It keeps the base move's type, so STAB, type matchups and immunities
  apply (Gigavolt Havoc still does nothing to a Ground type). It bypasses
  the accuracy roll, and has none of the base move's extras: no secondary
  effect, no recoil, no charge turn, no recharge, single hit.
- It uses 1 PP of the base move.

### Status Z-Moves

A status move of the crystal's type becomes its Z-version: the move runs as
normal, and the Pokémon first gets the Sun/Moon bonus. The preview bar shows
which.

- **Stat +1:** Attack (Tail Whip, Leer, Meditate, Screech, Sharpen), Defense
  (Growl, Roar, Poisonpowder, Toxic, Harden, Withdraw, Reflect, Poison Gas),
  Speed (Sing, Supersonic, Sleep Powder, String Shot, Hypnosis, Lovely Kiss),
  Special (Whirlwind, Growth, Stun Spore, Thunder Wave, Confuse Ray, Light
  Screen, Glare), Accuracy (Mimic, Defense Curl, Focus Energy), Evasion (Sand
  Attack, Smokescreen, Kinesis, Flash).
- **More:** Splash is Attack +3, Mirror Move is Attack +2, Conversion is
  Attack, Defense, Speed and Special +1.
- **Reset lowered stats:** Swords Dance, Disable, Leech Seed, Agility, Double
  Team, Recover, Minimize, Barrier, Amnesia, Softboiled, Spore, Acid Armor,
  Rest, Substitute.
- **Restore all HP:** Mist, Teleport, Haze, Transform.

Gen 1 has one SPECIAL stat, so Sun/Moon's Sp. Atk and Sp. Def bonuses both
raise SPECIAL. Metronome has no Z-version.

| Type | Crystal | Z-Move |
|---|---|---|
| Normal | Normalium Z | Breakneck Blitz |
| Fire | Firium Z | Inferno Overdrive |
| Water | Waterium Z | Hydro Vortex |
| Electric | Electrium Z | Gigavolt Havoc |
| Grass | Grassium Z | Bloom Doom |
| Ice | Icium Z | Subzero Slammer |
| Fighting | Fightinium Z | All-Out Pummeling |
| Poison | Poisonium Z | Acid Downpour |
| Ground | Groundium Z | Tectonic Rage |
| Flying | Flyinium Z | Supersonic Skystrike |
| Psychic | Psychium Z | Shattered Psyche |
| Bug | Buginium Z | Savage Spin-Out |
| Rock | Rockium Z | Continental Crush |
| Ghost | Ghostium Z | Never-Ending Nightmare |
| Dragon | Dragonium Z | Devastating Drake |

## Species-exclusive Z-Moves

Four Gen 1 Pokémon have their own crystal, listed at the top of their
Z-CRYSTAL menu. It only works on the one base move, and it does not power
ordinary Z-Moves.

| Pokémon | Crystal | Base move here | Z-Move |
|---|---|---|---|
| Pikachu | Pikanium Z | Thunder | Catastropika, power 210 |
| Snorlax | Snorlium Z | Hyper Beam | Pulverizing Pancake, power 210 |
| Mew | Mewnium Z | Psychic | Genesis Supernova, power 185 |
| Eevee | Eevium Z | Take Down | Extreme Evoboost, every stat +2 |

Volt Tackle, Giga Impact and Last Resort do not exist in Gen 1, so Thunder,
Hyper Beam and Take Down stand in for them. If another mod adds the real
move, the crystal uses that instead. Genesis Supernova sets no Psychic
Terrain, since Gen 1 has no terrain.

## Saves and turning the mod off

- A held crystal is a plain field on the Pokémon. It survives the PC,
  evolution, saving and reloading.
- A Z-Move never reaches a save: the move slot is handed back before every
  save, when a Pokémon faints or switches out, and at the end of every turn.
- "Z-Power used" is kept in the battle itself, so restoring a battle
  checkpoint cannot give a second Z-Move.
- **Turning the mod off is safe.** Your Pokémon and moves are untouched. The
  Z-RING is set aside by Gen1Recomp's own quarantine (it may tell you an item
  was set aside) and comes back to your bag when you turn the mod on again.
  Crystals, earned milestones and the record are all still there.

## Other mods

- **Translations:** every line Z-Moves shows in battle and on the map is
  registered game text (`_ZMoves...Text`), so a translation mod can replace
  it. Z-Moves fills its own `{USER}`, `{STAT}` and `{TRAINER}` slots; a
  translation that leaves one out or adds another shows the slot as written
  instead of stopping the game.
- **Gen1 Modern UI:** when it is installed, Z-Moves adds a **Z** badge to
  crystal holders on its party list and a **Z-CRYSTAL** page to its summary,
  through Modern UI's documented extensions. Z-Moves draws nothing on Modern
  UI's own screens.
- **Battle UI mods:** `mod.find("z_moves").exports` offers `state(battle)`,
  `preview(battle, slot)`, `crystalOf(mon)`, `zPower(moveDef)`,
  `zStatus(moveDef)`, `unlocked(key)` and `record()` for drawing your own Z
  button.

## Not in this version

- Alolan Raichu's and cap Pikachu's Z-Moves (those forms are not in Gen 1).
- Ordinary trainers and the rival before Silph Co. never use Z-Moves.
- Gold/Silver/Crystal and the Gen 3 games. The mod only loads on Gen 1.
- Link battles are left untouched.

## Tests

From a Gen1Recomp source checkout with this folder at `mods/z_moves`:

    luajit mods/z_moves/tests/z_moves_test.lua

It loads the mod through the real loader and walks battle turns through the
engine's own hook order, damage formula, bag and save repair. No ROM needed.

## Credits

- bryanthaboi, for Gen1Recomp and its mod API.
- pret/pokered, for the battle engine the hooks sit on.
- Pokémon and all related names are trademarks of Nintendo, Game Freak and
  Creatures. This is a fan project; it contains no ROM data.
