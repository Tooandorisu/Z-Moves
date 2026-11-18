# Changelog

## [0.8.0]

Gold, Silver and Crystal. The same mod now runs on both generations; Red,
Blue and Yellow behave exactly as in 0.7.0.

### Added
- **Gen 2 support** (`"games": ["gen1", "gen2"]`): Gold, Silver and Crystal,
  with existing saves.
- **Darkinium Z** (Black Hole Eclipse) and **Steelium Z** (Corkscrew Crash):
  all 17 Gen 2 types have a Z-Move.
- **Gen 2 story crystals:** the Z-Ring from PROF.ELM, Normalium Z from
  Whitney, Eevium Z with Bill's Eevee, and the rest from Johto's gyms and
  story (Sudowoodo, Ilex Forest, the Kimono Girls, the Burned Tower, Amphy,
  the red Gyarados, the Rocket hideout, the Radio Tower, the Ruins of Alph),
  Pikanium and Snorlium Z in Kanto, Mewnium Z for beating RED. Each crystal
  is awarded once.
- **Gen 2 trainers with Z-Power:** all sixteen Gym Leaders, the Elite Four,
  Champion Lance, RED, and the rival from the Goldenrod Underground on.
- **Gen 2 status Z-Moves** with the split special stats, and the Sun/Moon
  bonus for every new Gen 2 status move (Belly Drum, Spikes, Sketch,
  Foresight...).
- **Gen 2 Z-Move power** for Gen 2's variable-power moves (Return, Magnitude,
  Hidden Power, Flail, Present...).
- **Gen 2 animations:** each Z-Move chains the game's own animation scripts
  (Focus Energy's charge-up, two signature moves, Explosion's shake and
  flash).
- **Gen 2 preview bar and markers** placed for the Gen 2 battle screen, in
  the classic and the widescreen layout.
- **Z-RING in Gen 2's KEY ITEMS pocket**, with the item jingle; PARTY there
  also gives and takes crystals.
- A Gen 2 test suite that fights on the engine's own Gen 2 battle.

### Unchanged
- Gen 1: every rule, crystal, screen and save behaves as in 0.7.0.
- Z-Crystals stay separate from held items in both generations.

## [0.7.0]

A Gen 1 completeness and stability release.

### Added
- **Z-RING key item** in the bag (or PC). USE it for CRYSTALS (your
  collection, with descriptions), PARTY (what each Pokémon holds) and
  RECORD (Z-Moves used and faced, most used). Existing saves get it on the
  first step; a full bag gets it once there is room.
- **Key-item fanfare** for every Z-Crystal and the Z-Ring.
- **The rival** uses a Z-Move from Silph Co. on (Silph Co., Route 22), in
  Red, Blue and Yellow.
- **Z-RING WARNING** option (on): "MISTY wears a Z-RING!" when a Z-Ring
  trainer's battle opens. It never names the Pokémon or move.
- **Widescreen `Z` markers**, as tabs on the move box border.
- **Party menu shows the held crystal:** the row reads `Z:ELECTRIC`,
  `Z:PIKANIUM` and so on.
- **Gen1 Modern UI:** a Z badge on crystal holders and a Z-CRYSTAL summary
  page, through its documented extensions.
- Descriptions on every option, and exports for battle UI mods
  (`preview`, `record`).

### Changed
- **Z-Power is spent when the Z-Move fires, not when it is chosen**, as in
  Sun/Moon: sleep, paralysis, confusion, a flinch, an item or a switch leave
  it for a later turn. Applies to trainers too.
- The "unleashes its full-force Z-Move!" and Z-Power lines now come right
  before the move, so nothing is announced on a turn the Z-Move doesn't
  happen.
- All battle and map lines are registered text a translation can replace.
- The preview bar measures text by font width, so other fonts never overflow.

### Fixed
- The party menu's Z-CRYSTAL label ran past its box (the box is six columns
  wide without a field move).
- Healing status Z-Moves (Z-Mist, Z-Haze, Z-Teleport, Z-Transform) now slide
  the HP bar up the way Recover does.
- Restoring a battle checkpoint could give a second Z-Move. The "used" mark
  now lives in the battle's own side data, which checkpoints keep.
- A Pokémon that fainted or was switched out before its Z-Move fired kept the
  Z-Move in its move slot until the turn ended.
- No longer reads engine internals for the bag or type names; only the
  public mod API and game data.

## [0.6.1]

### Changed
- The Z-Power preview is now one slim bar between the two Pokémon, e.g.
  `Z:GIGAVOLT HAVOC 175` or `Z:THUNDER WAVE SPC+1`. Your name, HP bar and
  TYPE/PP panel stay visible. Names too long for the bar scroll through.
- The "can't use Z-Power" notices use the same bar.

## [0.6.0]

### Added
- Every Z-Move has its own animation: Z-Power charge-up, two signature
  animations of its type, flash-and-shake finish. Built at load from the
  game's own animations.
- Z-MOVE ANIMATIONS option (on by default) to go back to the borrowed ones.

## [0.5.0]

### Added
- Gym Leaders, Giovanni, the Elite Four and the Champion use one Z-Move per
  battle with their last Pokémon.
- TRAINER Z-MOVES option (on by default).

## [0.4.1]

### Fixed
- Crash after beating Lance (and possibly other story moments): the "got a
  crystal" message opened in the middle of the step that starts a cutscene
  or warp. It now waits in the game's own script queue until the map is idle.
- A message that was missed (crash, reset, Hall of Fame) is no longer lost:
  which crystals were announced is kept with the save.
- The messages are registered game text, so the Norwegian translation can
  translate them.

## [0.4.0]

### Added
- Crystals are earned in the story: the Z-Ring and Normalium Z with the
  POKéDEX, the others from gym leaders and story milestones. A message shows
  on the next step after each one.
- Z-CRYSTALS option: STORY (default) or ALL.

### Changed
- No Z-CRYSTAL row in the party menu before you have the Z-Ring.

## [0.3.0]

### Added
- Species-exclusive Z-Moves: Catastropika (Pikachu), Pulverizing Pancake
  (Snorlax), Genesis Supernova (Mew) and Extreme Evoboost (Eevee), each with
  its own crystal.

## [0.2.0]

### Added
- Status Z-Moves: 55 Gen 1 status moves get their Sun/Moon bonus (a stat
  boost, a reset of lowered stats, or a full heal) before the move runs.
- The preview box and the `Z` markers cover status moves too.

## [0.1.1]

### Fixed
- The `Z` marker sat directly after 12-letter move names (THUNDERSHOCKZ). It
  now sits in the empty panel left of the move list.

## [0.1.0]

### Changed
- Rebuilt as a standalone mod. The engine patches, the patched copies of
  `BattleState.lua`, `BattleAPI.lua`, `Game.lua`, `Checkpoint.lua`, `Party.lua`,
  `Commands.lua` and `World.lua`, the overlay installer and the custom Android
  build workflow are all gone; nothing in Gen1Recomp is modified.

### Added
- Z-Moves for all 15 Gen 1 types (the prototype handled Thunderbolt only).
- Z-CRYSTAL entry in the party menu; the crystal is stored on the Pokémon.
- START in the move list arms Z-Power, with an on-screen preview.
- Sun/Moon power table, accuracy bypass, one use per battle.
