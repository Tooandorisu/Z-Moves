# Z-Moves

A Pokémon Sun/Moon-inspired Z-Moves mod for Gen1Recomp, featuring Z-Crystals,
powerful Z-Moves, animations, and trainer battles.

For Pokémon Red, Blue and Yellow. It is an ordinary mod: it does not patch,
replace or rebuild any Gen1Recomp file.

**Version 0.6.1** · [Changelog](CHANGELOG.md)

## Features

- Z-Moves for all 15 Gen 1 types, with Sun/Moon power and rules.
- Status Z-Moves: stat boosts, stat resets and full heals.
- Species-exclusive Z-Moves: Catastropika, Pulverizing Pancake, Genesis
  Supernova and Extreme Evoboost.
- Z-Crystals earned through the story, from Gym Leaders and story milestones.
- Gym Leaders, Giovanni, the Elite Four and the Champion use Z-Moves too.
- Every Z-Move has its own animation.
- A slim one-line preview bar that keeps the battle screen visible.

## Installing

1. Download `z_moves_v0.6.1.zip` from the latest release, or the repository
   as a ZIP.
2. Unzip it into Gen1Recomp's `mods/` folder, so `manifest.json` sits
   directly inside the mod's folder (for example `mods/z_moves/manifest.json`).
3. Enable **Z-Moves** in the mod manager and start a Red, Blue or Yellow game.

Works on Android and Windows. An existing save is fine: crystals for
milestones you have already passed are there straight away.

## Options

| Option | Default | What it does |
|---|---|---|
| Z-CRYSTALS | STORY | STORY: earn crystals as you play. ALL: every crystal and the Z-Ring from the start. |
| TRAINER Z-MOVES | on | Gym Leaders, Giovanni, the Elite Four and the Champion use one Z-Move per battle. |
| Z-MOVE ANIMATIONS | on | Off: each Z-Move borrows one vanilla animation of its type. |

## Using it

0. **Get the Z-Ring.** Oak hands it over with the POKéDEX, together with
   Normalium Z. The other crystals come from the story (below).
1. **Give a crystal.** Party menu → pick a Pokémon → **Z-CRYSTAL**. Crystals
   that match one of its damaging moves are listed first and marked `OK`.
   The crystal stays with that Pokémon (PC, save, reload) until you take it
   back with **TAKE CRYSTAL**.
2. **Arm Z-Power.** In battle, open FIGHT and press **START**. Moves that can
   become a Z-Move have a `Z` beside them before you arm; once armed, a slim
   bar shows the Z-Move's name and power for the highlighted move. START again
   cancels. START on the FIGHT/PKMN/ITEM/RUN menu also arms it.
3. **Pick the move.** The Pokémon unleashes the Z-Move for that type.

The bar reads like `Z:GIGAVOLT HAVOC 175` for a damaging move and
`Z:THUNDER WAVE SPC+1` for a status move. Names too long for it scroll
through.

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

A message shows the next time you take a step on the map. A save that is
already past a milestone has that crystal straight away.

## Trainers with Z-Power

Like the Kahunas in Sun/Moon, the big fights use Z-Moves against you:
every Gym Leader, Giovanni, the Elite Four and the Champion.

- Their **last Pokémon** holds the crystal.
- It is **their own type** (Brock Rock, Misty Water, Lance Dragon...) when
  that Pokémon knows a damaging move of it; otherwise the type of its
  strongest damaging move. The Champion always uses his strongest.
- They use it **the first turn they can**, once per battle. If something
  stops it (an item, a switch, sleep), they try again later.
- Same rules as yours: Sun/Moon power, never misses.

## Animations

Every Z-Move has its own animation, built from the game's own pieces when
the mod loads: a Z-Power charge-up on a dark screen, two signature
animations of its type back to back (Gigavolt Havoc: Thunderbolt, then
Thunder), then a double flash and a screen shake. Extreme Evoboost charges
up through Growth, Swords Dance and Agility instead.

## Rules (as in Sun/Moon)


- One Z-Move per battle.
- The move must be a damaging move of the crystal's type.
- Power comes from the base move: up to 55 → 100, 60–65 → 120, 70–75 → 140,
  80–85 → 160, 90–95 → 175, 100 → 180, 110 → 185, 120–125 → 190, 130 → 195,
  140+ → 200. OHKO moves → 180; Seismic Toss, Night Shade, Sonicboom, Dragon
  Rage, Psywave, Super Fang, Counter and Bide → 100; Mega Drain → 120.
- It keeps the base move's type (so STAB and type matchups apply), bypasses
  the accuracy roll, and has none of the base move's extras: no secondary
  effect, no recoil, no charge turn, no recharge, single hit.
- It uses 1 PP of the base move.
- Z-Power is spent when the Z-Move is chosen, even if sleep, paralysis or a
  flinch then stops the Pokémon.

### Status Z-Moves

A status move of the crystal's type becomes its Z-version: the move runs as
normal, and first gives the Sun/Moon bonus. The preview bar shows which.

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

## Not in this version

- Alolan Raichu's and cap Pikachu's Z-Moves (those forms are not in Gen 1).
- Ordinary trainers and the rival before the Champion never use Z-Moves.
- Gold/Silver/Crystal and the Gen 3 games. The mod only loads on Gen 1.
- Link battles are left untouched.

## Tests

From a Gen1Recomp source checkout with this folder at `mods/z_moves`:

    luajit mods/z_moves/tests/z_moves_test.lua

It loads the mod through the real loader and walks a battle turn through the
engine's own hook bus and damage formula. No ROM needed.

## Credits

- bryanthaboi, for Gen1Recomp and its mod API.
- pret/pokered, for the battle engine the hooks sit on.
- Pokémon and all related names are trademarks of Nintendo, Game Freak and
  Creatures. This is a fan project; it contains no ROM data.
