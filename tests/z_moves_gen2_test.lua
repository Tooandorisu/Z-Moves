-- Z-Moves test suite (Gen 2).  Run from a Gen1Recomp source checkout with
-- this mod at mods/z_moves:
--   luajit mods/z_moves/tests/z_moves_gen2_test.lua
--
-- ROM-free.  The mod loads through the real loader and sandbox as if Gold
-- were running (generation 2), and every battle is the engine's own Gen 2
-- battle (src/battle/gen2/Battle.lua) fed a fixture dataset: turns, damage,
-- accuracy, PP, faints and switches are the engine's, not a model of them.
-- Animation chains run on the engine's own Gen 2 animation interpreter
-- (src/battle/gen2/AnimRunner.lua).  The overworld script queue is the real
-- Gen 2 WorldAPI over a stub world.  Only drawing is stubbed.
package.path = "./?.lua;./?/init.lua;" .. package.path

-- LuaJIT's bit library, for a plain Lua 5.3 run
if not pcall(require, "bit") then
  package.preload.bit = function()
    return assert(load([[return {
      band = function(a, b) return a & b end, bor = function(a, b) return a | b end,
      bxor = function(a, b) return a ~ b end, bnot = function(a) return ~a end,
      lshift = function(a, n) return a << n end, rshift = function(a, n) return a >> n end,
      tobit = function(a) return a end }]]))()
  end
end

-- ------- drawing stubs (installed before anything requires them)

local drawn = {}
local function resetDrawn() drawn = { texts = {}, rects = {} } end
resetDrawn()
love = love or {}
love.graphics = {
  setColor = function() end, getColor = function() return 1, 1, 1, 1 end,
  rectangle = function(_, x, y, w, h) drawn.rects[#drawn.rects + 1] = { x, y, w, h } end,
}
local glyph = 8
package.loaded["src.render.Font"] = {
  drawBox = function() end, drawCode = function() end,
  draw = function(t, x, y) drawn.texts[#drawn.texts + 1] = { t = t, x = x, y = y } end,
  width = function(t) return #t * glyph end,
}
package.loaded["src.ui.ListMenu"] = { new = function(_, title, items, opts)
  return { kind = "list", title = title, items = items, opts = opts,
           close = function() end } end }
package.loaded["src.render.TextBox"] = { new = function(_, text)
  return { kind = "text", text = text } end, strip = function(t)
    return (tostring(t):gsub("{PROMPT}", ""):gsub("{DONE}", "")) end,
  substitute = function(t) return t end }

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local AnimRunner = require("src.battle.gen2.AnimRunner")

local checks, failures = 0, 0
local function check(cond, name)
  checks = checks + 1
  if not cond then failures = failures + 1 print("FAIL " .. name) end
end
local function eq(got, want, name)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
  end
end

-- ------- fixture dataset (Gen 2 record shapes)

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical", name = "NORMAL" },
  FIGHTING = { id = "FIGHTING", index = 1, category = "physical", name = "FIGHTING" },
  FLYING = { id = "FLYING", index = 2, category = "physical", name = "FLYING" },
  POISON = { id = "POISON", index = 3, category = "physical", name = "POISON" },
  GROUND = { id = "GROUND", index = 4, category = "physical", name = "GROUND" },
  ROCK = { id = "ROCK", index = 5, category = "physical", name = "ROCK" },
  BUG = { id = "BUG", index = 7, category = "physical", name = "BUG" },
  GHOST = { id = "GHOST", index = 8, category = "physical", name = "GHOST" },
  STEEL = { id = "STEEL", index = 9, category = "physical", name = "STEEL" },
  CURSE_TYPE = { id = "CURSE_TYPE", index = 19, category = "physical", name = "???" },
  FIRE = { id = "FIRE", index = 20, category = "special", name = "FIRE" },
  WATER = { id = "WATER", index = 21, category = "special", name = "WATER" },
  GRASS = { id = "GRASS", index = 22, category = "special", name = "GRASS" },
  ELECTRIC = { id = "ELECTRIC", index = 23, category = "special", name = "ELECTRIC" },
  PSYCHIC_TYPE = { id = "PSYCHIC_TYPE", index = 24, category = "special", name = "PSYCHIC" },
  ICE = { id = "ICE", index = 25, category = "special", name = "ICE" },
  DRAGON = { id = "DRAGON", index = 26, category = "special", name = "DRAGON" },
  DARK = { id = "DARK", index = 27, category = "special", name = "DARK" },
}
local MATCHUPS = {
  { attacker = "ELECTRIC", defender = "GROUND", multiplier = 0 },
  { attacker = "ELECTRIC", defender = "WATER", multiplier = 20 },
  { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
}

local function mv(id, name, power, typ, pp, effect, accuracy)
  accuracy = accuracy or 100
  return { id = id, name = name, power = power, type = typ, pp = pp,
    accuracy = accuracy, accuracyRaw = math.floor(accuracy * 255 / 100 + 0.5),
    effect = effect or "EFFECT_NORMAL_HIT", effectChance = 10, effectChanceRaw = 25 }
end
local MOVES = {
  TACKLE = mv("TACKLE", "TACKLE", 35, "NORMAL", 35, nil, 95),
  HYPER_BEAM = mv("HYPER_BEAM", "HYPER BEAM", 150, "NORMAL", 5, "EFFECT_HYPER_BEAM", 90),
  EXTREMESPEED = mv("EXTREMESPEED", "EXTREMESPEED", 80, "NORMAL", 5, "EFFECT_PRIORITY_HIT"),
  BODY_SLAM = mv("BODY_SLAM", "BODY SLAM", 85, "NORMAL", 15, "EFFECT_PARALYZE_HIT"),
  TAKE_DOWN = mv("TAKE_DOWN", "TAKE DOWN", 90, "NORMAL", 20, "EFFECT_RECOIL_HIT", 85),
  QUICK_ATTACK = mv("QUICK_ATTACK", "QUICK ATTACK", 40, "NORMAL", 30, "EFFECT_PRIORITY_HIT"),
  GROWL = mv("GROWL", "GROWL", 0, "NORMAL", 40, "EFFECT_ATTACK_DOWN"),
  RECOVER = mv("RECOVER", "RECOVER", 0, "NORMAL", 20, "EFFECT_HEAL"),
  SWORDS_DANCE = mv("SWORDS_DANCE", "SWORDS DANCE", 0, "NORMAL", 30, "EFFECT_ATTACK_UP_2"),
  FOCUS_ENERGY = mv("FOCUS_ENERGY", "FOCUS ENERGY", 0, "NORMAL", 30, "EFFECT_FOCUS_ENERGY"),
  EXPLOSION = mv("EXPLOSION", "EXPLOSION", 250, "NORMAL", 5, "EFFECT_SELFDESTRUCT"),
  FIRE_BLAST = mv("FIRE_BLAST", "FIRE BLAST", 120, "FIRE", 5, "EFFECT_BURN_HIT", 85),
  HYDRO_PUMP = mv("HYDRO_PUMP", "HYDRO PUMP", 120, "WATER", 5, nil, 80),
  THUNDER = mv("THUNDER", "THUNDER", 120, "ELECTRIC", 10, "EFFECT_THUNDER", 70),
  THUNDERBOLT = mv("THUNDERBOLT", "THUNDERBOLT", 95, "ELECTRIC", 15, "EFFECT_PARALYZE_HIT"),
  THUNDER_WAVE = mv("THUNDER_WAVE", "THUNDER WAVE", 0, "ELECTRIC", 20, "EFFECT_PARALYZE"),
  ZAP_CANNON = mv("ZAP_CANNON", "ZAP CANNON", 100, "ELECTRIC", 5, "EFFECT_PARALYZE_HIT", 50),
  SOLARBEAM = mv("SOLARBEAM", "SOLARBEAM", 120, "GRASS", 10, "EFFECT_SOLARBEAM"),
  GROWTH = mv("GROWTH", "GROWTH", 0, "NORMAL", 40, "EFFECT_SP_ATK_UP"),
  BLIZZARD = mv("BLIZZARD", "BLIZZARD", 120, "ICE", 5, "EFFECT_FREEZE_HIT", 70),
  MIST = mv("MIST", "MIST", 0, "ICE", 30, "EFFECT_MIST"),
  HI_JUMP_KICK = mv("HI_JUMP_KICK", "HI JUMP KICK", 85, "FIGHTING", 20, "EFFECT_JUMP_KICK", 90),
  SLUDGE = mv("SLUDGE", "SLUDGE", 65, "POISON", 20, "EFFECT_POISON_HIT"),
  EARTHQUAKE = mv("EARTHQUAKE", "EARTHQUAKE", 100, "GROUND", 10, "EFFECT_EARTHQUAKE"),
  SKY_ATTACK = mv("SKY_ATTACK", "SKY ATTACK", 140, "FLYING", 5, "EFFECT_SKY_ATTACK", 90),
  WING_ATTACK = mv("WING_ATTACK", "WING ATTACK", 60, "FLYING", 35),
  GUST = mv("GUST", "GUST", 40, "FLYING", 35, "EFFECT_GUST"),
  PSYCHIC_M = mv("PSYCHIC_M", "PSYCHIC", 90, "PSYCHIC_TYPE", 10, "EFFECT_SP_DEF_DOWN_HIT"),
  PIN_MISSILE = mv("PIN_MISSILE", "PIN MISSILE", 14, "BUG", 20, "EFFECT_MULTI_HIT", 85),
  ROCK_SLIDE = mv("ROCK_SLIDE", "ROCK SLIDE", 75, "ROCK", 10, "EFFECT_FLINCH_HIT", 90),
  SHADOW_BALL = mv("SHADOW_BALL", "SHADOW BALL", 80, "GHOST", 15, "EFFECT_SP_DEF_DOWN_HIT"),
  OUTRAGE = mv("OUTRAGE", "OUTRAGE", 90, "DRAGON", 15, "EFFECT_RAMPAGE"),
  DRAGONBREATH = mv("DRAGONBREATH", "DRAGONBREATH", 60, "DRAGON", 20, "EFFECT_PARALYZE_HIT"),
  CRUNCH = mv("CRUNCH", "CRUNCH", 80, "DARK", 15, "EFFECT_SP_DEF_DOWN_HIT"),
  IRON_TAIL = mv("IRON_TAIL", "IRON TAIL", 100, "STEEL", 15, "EFFECT_DEFENSE_DOWN_HIT", 75),
  CURSE = mv("CURSE", "CURSE", 0, "CURSE_TYPE", 10, "EFFECT_CURSE"),
  SEISMIC_TOSS = mv("SEISMIC_TOSS", "SEISMIC TOSS", 1, "FIGHTING", 20, "EFFECT_LEVEL_DAMAGE"),
  RETURN = mv("RETURN", "RETURN", 1, "NORMAL", 20, "EFFECT_RETURN"),
  AGILITY = mv("AGILITY", "AGILITY", 0, "PSYCHIC_TYPE", 30, "EFFECT_SPEED_UP_2"),
  CUT = mv("CUT", "CUT", 50, "NORMAL", 30),
  FLY = mv("FLY", "FLY", 70, "FLYING", 15, "EFFECT_FLY", 95),
  SURF = mv("SURF", "SURF", 95, "WATER", 15),
  STRENGTH = mv("STRENGTH", "STRENGTH", 80, "NORMAL", 15),
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 },
}
local function species(id, index, types, base)
  return { id = id, index = index, name = id, baseStats = base,
    types = types, catchRate = 45, baseExp = 100, growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = 127, levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} }
end
local STATS = { hp = 60, attack = 70, defense = 60, speed = 90,
                specialAttack = 80, specialDefense = 60 }
local SLOW = { hp = 60, attack = 70, defense = 60, speed = 10,
               specialAttack = 80, specialDefense = 60 }
local FAST = { hp = 60, attack = 70, defense = 60, speed = 200,
               specialAttack = 80, specialDefense = 60 }
local POKEMON = {
  growthRates = GROWTH,
  PIKACHU = species("PIKACHU", 25, { "ELECTRIC", "ELECTRIC" }, STATS),
  EEVEE = species("EEVEE", 133, { "NORMAL", "NORMAL" }, STATS),
  LAPRAS = species("LAPRAS", 131, { "WATER", "ICE" }, STATS),
  RATTATA = species("RATTATA", 19, { "NORMAL", "NORMAL" }, SLOW),
  GEODUDE = species("GEODUDE", 74, { "ROCK", "GROUND" }, SLOW),
  SLOWPOKE = species("SLOWPOKE", 79, { "WATER", "PSYCHIC_TYPE" }, SLOW),
  PIDGEOTTO = species("PIDGEOTTO", 17, { "NORMAL", "FLYING" }, SLOW),
  DRAGONITE = species("DRAGONITE", 149, { "DRAGON", "FLYING" }, SLOW),
  JOLTEON = species("JOLTEON", 135, { "ELECTRIC", "ELECTRIC" }, FAST),
  HAUNTER = species("HAUNTER", 93, { "GHOST", "POISON" }, STATS),
}

-- the event flags the story uses, at made-up indices
local FLAG_ORDER = {
  "EVENT_GOT_A_POKEMON_FROM_ELM", "EVENT_BEAT_FALKNER", "EVENT_BEAT_BUGSY",
  "EVENT_BEAT_WHITNEY", "EVENT_GOT_EEVEE", "EVENT_FOUGHT_SUDOWOODO",
  "EVENT_HERDED_FARFETCHD", "EVENT_BEAT_MORTY",
  "EVENT_BEAT_KIMONO_GIRL_NAOKO", "EVENT_BEAT_KIMONO_GIRL_SAYO",
  "EVENT_BEAT_KIMONO_GIRL_ZUKI", "EVENT_BEAT_KIMONO_GIRL_KUNI",
  "EVENT_BEAT_KIMONO_GIRL_MIKI", "EVENT_RELEASED_THE_BEASTS", "EVENT_BEAT_CHUCK",
  "EVENT_JASMINE_RETURNED_TO_GYM", "EVENT_BEAT_JASMINE",
  "EVENT_LAKE_OF_RAGE_RED_GYARADOS", "EVENT_CLEARED_ROCKET_HIDEOUT",
  "EVENT_BEAT_PRYCE", "EVENT_CLEARED_RADIO_TOWER", "EVENT_BEAT_CLAIR",
  "EVENT_SOLVED_KABUTO_PUZZLE", "EVENT_BEAT_LTSURGE", "EVENT_FOUGHT_SNORLAX",
}
local FLAG = {}
for i, name in ipairs(FLAG_ORDER) do FLAG[name] = i - 1 end

-- Gen 2 animation scripts, shaped as the importer writes them (pool keyed by
-- address, branch targets rewritten to pool keys), modelled on
-- data/moves/animations.asm: FOCUS ENERGY with its loop and two calls,
-- EXPLOSION with its param branch and the sub-script holding its sound.
local ANIMS = {
  scripts = {
    ["4000"] = { { "1gfx", 5 }, { "call", "5000" }, { "bgeffect", 1, 0, 1, 64 },
                 { "sound", 0, 7 }, { "wait", 2 }, { "loop", 3, "4001" },
                 { "wait", 8 }, { "incbgeffect", 1 }, { "call", "5001" }, { "ret" } },
    ["4001"] = { { "sound", 0, 7 }, { "wait", 2 }, { "loop", 3, "4001" },
                 { "wait", 8 }, { "incbgeffect", 1 }, { "call", "5001" }, { "ret" } },
    ["4100"] = { { "1gfx", 9 }, { "sound", 0, 32 }, { "wait", 32 }, { "ret" } },
    ["4200"] = { { "1gfx", 9 }, { "sound", 1, 33 }, { "wait", 16 },
                 { "sound", 1, 33 }, { "wait", 48 }, { "ret" } },
    ["4300"] = { { "1gfx", 2 }, { "bgeffect", 5, 96, 4, 16 }, { "bgeffect", 6, 0, 8, 36 },
                 { "if_param_equal", 1, "4301" }, { "call", "5002" }, { "wait", 16 }, { "ret" } },
    ["4301"] = { { "call", "5002" }, { "wait", 16 }, { "ret" } },
    ["4400"] = { { "1gfx", 3 }, { "bgeffect", 5, 48, 4, 16 }, { "call", "5003" },
                 { "wait", 48 }, { "ret" } },
    ["4500"] = { { "1gfx", 9 }, { "sound", 0, 34 }, { "wait", 40 }, { "ret" } },
    ["5000"] = { { "battlergfx_1row" }, { "wait", 1 }, { "ret" } },
    ["5001"] = { { "wait", 1 }, { "ret" } },
    ["5002"] = { { "sound", 0, 48 }, { "wait", 5 }, { "ret" } },
    ["5003"] = { { "sound", 0, 49 }, { "wait", 4 }, { "ret" } },
  },
  moves = { FOCUS_ENERGY = "4000", THUNDERBOLT = "4100", THUNDER = "4200",
            EXPLOSION = "4300", HYPER_BEAM = "4400", ZAP_CANNON = "4500" },
  ids = {},
  objects = {},
}

local function freshData()
  local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
    return out
  end
  local text = require("tests.gen2_battle_text_fixture")()
  text["StatNames#5"] = "SPCL.DEF"
  text["StatNames#1"] = "ATTACK"
  return {
    pokemon = copy(POKEMON),
    moves = copy(MOVES),
    text = text,
    type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(),
                   types = copy(TYPES), matchups = copy(MATCHUPS) },
    items = {},
    gen2Constants = { eventFlagOrder = copy(FLAG_ORDER) },
    gen2BattleAnims = copy(ANIMS),
  }
end

-- ------- a game the loader can hand out as mod.game

local Events = require("src.world.gen2.Events")

local function newGame(data)
  local game = { data = data, options = {}, save = {
    player = { name = "GOLD" }, party = {}, inventory = {}, pcItems = {},
    events = {}, modData = {} } }
  game.stack = { states = {} }
  function game.stack:top() return self.states[#self.states] end
  function game.stack:push(s) self.states[#self.states + 1] = s end
  function game.stack:pop() self.states[#self.states] = nil end
  game.pressed = {}
  game.input = { wasPressed = function(_, b) return game.pressed[b] == true end }
  local world = { map = { id = "NEW_BARK_TOWN" }, events = Events.new(),
    player = { moving = false }, shown = {}, sounds = {} }
  function world:busy() return self.isBusy == true end
  function world:showText(body, onDone)
    self.shown[#self.shown + 1] = body
    if onDone then onDone() end
  end
  function world:playSfxNamed(name) self.sounds[#self.sounds + 1] = name end
  game.world = world
  return game
end

local function setFlag(game, name, value)
  game.world.events:set(FLAG[name], value ~= false)
end

-- ------- loading

local function loadMod(opts)
  opts = opts or {}
  local data = freshData()
  local run = T.sdk.loadMod("mods/z_moves", { generation = 2, data = data })
  local game = newGame(run.data)
  run.loader.game = game
  run.game = game
  local mod = run.loader.mods.z_moves
  if opts.options then
    run.loader.modOptions.z_moves = run.loader.modOptions.z_moves or {}
    for k, v in pairs(opts.options) do run.loader.modOptions.z_moves[k] = v end
  end
  -- mod.save: the loader's per-save bucket
  run.loader.modSave = game.save.modData
  run.exports = mod and mod.api and mod.api.exports or run.loader.exports.z_moves
  return run, game, mod
end

local run, game, mod = loadMod()
eq(mod and mod.state, "loaded", "loads on Gen 2")
local errs = {}
for _, e in ipairs(run.errors) do errs[#errs + 1] = tostring(type(e) == "table" and (e.message or e.text) or e) end
eq(#errs, 0, "no load errors: " .. table.concat(errs, " | "))

local data = run.data
local count = 0
for _, key in ipairs({ "NORMAL", "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE",
    "FIGHTING", "POISON", "GROUND", "FLYING", "PSYCHIC", "BUG", "ROCK", "GHOST",
    "DRAGON", "DARK", "STEEL" }) do
  local z = data.moves["ZMOVE_" .. key]
  if z then count = count + 1 end
end
eq(count, 17, "a Z-Move for each of the 17 Gen 2 types")
eq(data.moves.ZMOVE_DARK.type, "DARK", "Black Hole Eclipse is Dark")
eq(data.moves.ZMOVE_STEEL.type, "STEEL", "Corkscrew Crash is Steel")
eq(data.moves.ZMOVE_PSYCHIC.type, "PSYCHIC_TYPE", "Shattered Psyche keeps Gen 2's type id")
eq(data.moves.ZMOVE_DARK.name, "BLACK HOLE\nECLIPSE", "two-line name")
check(data.moves.ZMOVE_PIKANIUM and data.moves.ZMOVE_EEVIUM and data.moves.ZMOVE_SNORLIUM
  and data.moves.ZMOVE_MEWNIUM, "the four exclusive Z-Moves")
eq(data.moves.ZMOVE_EEVIUM.effect, "EFFECT_ATTACK_UP_2", "Evoboost carries Swords Dance's effect")
eq(data.items.Z_RING and data.items.Z_RING.pocket, "KEY_ITEM", "Z-RING is a key item")
eq(data.text._ZMovesUnleashText ~= nil, true, "lines are ROM text a translation can override")
eq(data.text._ZMovesGotNORMALText, "{PLAYER} got\nNORMALIUM Z!", "reward line registered")

-- ------- animations: chains of the game's own scripts

local anims = data.gen2BattleAnims
local chainKey = anims.moves.ZMOVE_ELECTRIC
check(type(chainKey) == "string" and chainKey:sub(1, 7) == "zmoves:", "electric Z-Move has its own chain")
eq(anims.moves.THUNDERBOLT, "4100", "vanilla move pointers untouched")
eq(#anims.scripts["4100"], 4, "vanilla scripts untouched")
-- every branch in every chain lands on a script that exists
local broken = 0
for key, rows in pairs(anims.scripts) do
  if key:sub(1, 7) == "zmoves:" then
    for _, row in ipairs(rows) do
      local at = ({ jump = 2, loop = 3, if_param_equal = 3, call = 2 })[row[1]]
      if at and not anims.scripts[row[at]] then broken = broken + 1 end
    end
  end
end
eq(broken, 0, "every jump, loop and call in a chain has a target")

local function runAnim(key)
  local sounds = {}
  local runner = AnimRunner.new({ data = anims, constants = {}, battleTurn = 0,
    sfxOrder = setmetatable({}, { __index = function(_, i) return "SFX_" .. tostring(i) end }),
    hooks = { sound = function(_, _, _, id) sounds[#sounds + 1] = "SFX_" .. tostring(id) end,
              cry = function() end } })
  runner:start(key)
  local frames = 0
  while runner:step() do
    frames = frames + 1
    if frames > 5000 then break end
  end
  return frames, sounds
end
local frames, sounds = runAnim(chainKey)
check(frames > 80 and frames < 1200, "the chain plays through and ends (" .. frames .. " frames)")
local heard = table.concat(sounds, ",")
check(heard:find("SFX_7") ~= nil, "it opens with FOCUS ENERGY's charge-up")
check(heard:find("SFX_32") and heard:find("SFX_34"), "then THUNDERBOLT and ZAP CANNON")
check(heard:find("SFX_48") ~= nil, "and ends on EXPLOSION's sound")
local fe = 0
for _, s in ipairs(sounds) do if s == "SFX_7" then fe = fe + 1 end end
eq(fe, 4, "FOCUS ENERGY's loop still runs its count in the copy")
-- a type with only one signature move present still gets intro + finish
check(anims.moves.ZMOVE_NORMAL and anims.moves.ZMOVE_NORMAL:sub(1, 7) == "zmoves:",
  "Normal chain (only HYPER BEAM present) is built")
-- a type with none falls back to its sample move's animation, if it has one
eq(anims.moves.ZMOVE_ROCK, nil, "no rock animation in the fixture: nothing borrowed")

-- ------- battles

local function perfect()
  local dv = { attack = 15, defense = 15, speed = 15, special = 15 }
  dv.hp = Mon.hpDV(dv)
  return dv
end

local function newMon(id, level, moves, crystal)
  local m = Mon.new(data, id, level, { dvs = perfect() })
  m.moves = {}
  for i, move in ipairs(moves) do
    local def = data.moves[move]
    m.moves[i] = { id = move, pp = def.pp, maxPp = def.pp }
  end
  m.zCrystal = crystal
  return m
end

local function zeroRandom() return 0 end

-- a Pokemon that survives anything the test throws at it
local function tank(m)
  m._tank = true
  m.hp, m.maxHp = 999, 999
  m.stats = m.stats or {}
  m.stats.hp = 999
end

local function newBattle(opts)
  local party = opts.party
  game.save.party = party
  local b = Battle.new({ data = data, party = party, wild = opts.wild,
    trainer = opts.trainer, random = opts.random or zeroRandom })
  b:takeEvents()
  -- the battle sets up its own HP; re-apply the test's bulk
  for _, m in ipairs({ b.enemy, b.player }) do
    if m and m._tank then tank(m) end
  end
  return b
end

local function screenFor(b, phase)
  return { isGen2BattleState = true, screenId = "Gen2BattleState", battle = b,
           phase = phase or "moves", moveIndex = 1, game = game,
           wideLayout = function(self) return self.wide == true end,
           extendedHUD = function(self) return self.dock == true end,
           pushed = {}, push = function(self, e) self.pushed[#self.pushed + 1] = e end }
end

local function pressStart(screen)
  game.stack.states = { screen }
  game.pressed.start = true
  Runtime.call("input.step", function() end, game, 1 / 60)
  game.pressed.start = false
  game.stack.states = {}
end

local function texts(events)
  local out = {}
  for _, e in ipairs(events or {}) do
    if e.text then out[#out + 1] = (e.text:gsub("\n", " "):gsub("\v", " ")) end
  end
  return out
end
local function find(events, needle)
  for i, t in ipairs(texts(events)) do
    if t:find(needle, 1, true) then return i end
  end
end
local function damageTo(events, side)
  local total = 0
  for _, e in ipairs(events or {}) do
    if e.kind == "damage" and e.side == side then total = total + (e.amount or 0) end
  end
  return total
end
local function moveEvent(events, side)
  for _, e in ipairs(events or {}) do
    if e.kind == "move" and e.side == side then return e end
  end
end
local function state(b) return run.exports.state(b) end

-- story flags for the Z-Ring and the Electrium
setFlag(game, "EVENT_GOT_A_POKEMON_FROM_ELM")
setFlag(game, "EVENT_JASMINE_RETURNED_TO_GYM")

-- 1. a damaging Z-Move, end to end
do
  local pika = newMon("PIKACHU", 30, { "THUNDERBOLT", "TACKLE", "THUNDER_WAVE" }, "ELECTRIC")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local b = newBattle({ party = { pika }, wild = foe })
  -- the reference: a plain THUNDERBOLT
  local plain = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  local plainDamage = damageTo(plain, "enemy")
  eq(pika.moves[1].pp, 14, "plain THUNDERBOLT spent 1 PP")
  local screen = screenFor(b, "moves")
  pressStart(screen)
  eq(state(b).armed, true, "START in the move list arms Z-Power")
  local events = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  local unleash = find(events, "unleashes its")
  local used = find(events, "GIGAVOLT")
  check(unleash and used and unleash < used, "'unleashes' comes right before 'used GIGAVOLT HAVOC'")
  local me = moveEvent(events, "player")
  eq(me and me.move, "ZMOVE_ELECTRIC", "the move event plays the Z-Move's own animation")
  local zDamage = damageTo(events, "enemy")
  check(zDamage > plainDamage * 1.5, ("Z damage %d > THUNDERBOLT %d"):format(zDamage, plainDamage))
  eq(pika.moves[1].pp, 13, "the Z-Move spent THUNDERBOLT's PP")
  eq(pika.moves[1].id, "THUNDERBOLT", "the slot is THUNDERBOLT again")
  eq(state(b).used, true, "Z-Power spent")
  eq(state(b).armed, false, "and disarmed")
  local lm = pika.volatile and pika.volatile.lastMove
  check(lm ~= "ZMOVE_ELECTRIC", "nothing remembers the Z-Move's id as the last move")
  check(foe.status ~= "par", "a Z-Move has no secondary effect (no paralysis roll)")
  pressStart(screen)
  eq(state(b).armed, false, "once per battle: cannot arm again")
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  local bar = drawn.texts[1] and drawn.texts[1].t or ""
  check(bar:find("ALREADY USED", 1, true), "the bar says ALREADY USED")
  local tokens = b.sides[1].tokens
  check(tokens and tokens[1] and tokens[1].id == "z_moves.used", "spent mark on the side")
  local r = run.exports.record()
  eq(r.used, 1, "record counts the Z-Move")
  eq(r.byKey.ELECTRIC, 1, "by crystal")
end

-- 2. the bar and markers, classic and widescreen
do
  local pika = newMon("PIKACHU", 30, { "TACKLE", "THUNDERBOLT", "THUNDER_WAVE" }, "ELECTRIC")
  local b = newBattle({ party = { pika }, wild = newMon("RATTATA", 5, { "TACKLE" }) })
  local screen = screenFor(b, "moves")
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  local zs = {}
  for _, t in ipairs(drawn.texts) do if t.t == "Z" then zs[#zs + 1] = t end end
  eq(#zs, 2, "markers on THUNDERBOLT and THUNDER WAVE only")
  eq(zs[1] and zs[1].x, 144, "marker in the list's last column")
  eq(zs[1] and zs[1].y, 112, "on THUNDERBOLT's row (row 14)")
  pressStart(screen)
  screen.moveIndex = 2
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(drawn.texts[1] and drawn.texts[1].t, "Z:GIGAVOLT HAVOC", "bar: Z:GIGAVOLT HAVOC")
  eq(drawn.texts[2] and drawn.texts[2].t, "175", "with its power (95 -> 175)")
  eq(drawn.rects[1] and drawn.rects[1][2], 40, "bar on rows 5-6, clear of both HUDs")
  eq(drawn.rects[1] and drawn.rects[1][1], 0, "classic bar from the left edge")
  screen.moveIndex = 3
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(drawn.texts[1] and drawn.texts[1].t, "Z:THUNDER WAVE", "status move keeps its name")
  eq(drawn.texts[2] and drawn.texts[2].t, "SPD+1", "Z-Thunder Wave: Sp. Def +1")
  screen.moveIndex = 1
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(drawn.texts[1] and drawn.texts[1].t, "Z:NO Z-MOVE", "TACKLE with Electrium: NO Z-MOVE")
  screen.wide = true
  screen.moveIndex = 2
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(drawn.rects[1] and drawn.rects[1][1], 72, "widescreen bar over the field")
  pressStart(screen)
  eq(state(b).armed, false, "START again disarms")
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  local wideZ = 0
  for _, t in ipairs(drawn.texts) do if t.t == "Z" then wideZ = wideZ + 1 end end
  eq(wideZ, 2, "widescreen markers")
  screen.dock = true
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(#drawn.texts, 0, "no markers when the HUD is docked (its offset is unknown)")
  screen.phase = "resolving"
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(#drawn.texts, 0, "nothing drawn while the turn plays")
  -- long names scroll inside the bar
  local long = newMon("PIKACHU", 30, { "TACKLE", "THUNDERBOLT" }, "ELECTRIC")
  local b2 = newBattle({ party = { long }, wild = newMon("RATTATA", 5, { "TACKLE" }) })
  local s2 = screenFor(b2, "moves")
  glyph = 10
  pressStart(s2)
  s2.moveIndex = 2
  resetDrawn()
  Runtime.call("battle.overlay", function() end, s2)
  check(#(drawn.texts[1] and drawn.texts[1].t or "") <= 16, "a wide font never runs past the bar")
  glyph = 8
end

-- 3. sleep keeps the Z-Power for a later turn
do
  local pika = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  pika.status, pika.statusTurns = "sleep", 2
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local b = newBattle({ party = { pika }, wild = foe })
  local screen = screenFor(b)
  pressStart(screen)
  local events = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(find(events, "unleashes"), nil, "asleep: no Z line")
  eq(state(b).used, false, "asleep: Z-Power not spent")
  eq(pika.moves[1].id, "THUNDERBOLT", "slot restored after a skipped turn")
  eq(pika.moves[1].pp, 15, "no PP spent while asleep")
  pika.status, pika.statusTurns = nil, nil
  pressStart(screen)
  events = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  check(find(events, "unleashes"), "awake: the Z-Move fires")
  eq(state(b).used, true, "and is spent")
end

-- 4. status Z-Moves
do
  local pika = newMon("PIKACHU", 30, { "THUNDER_WAVE" }, "ELECTRIC")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  local b = newBattle({ party = { pika }, wild = foe })
  pressStart(screenFor(b))
  local events = b:takeTurn({ kind = "move", move = "THUNDER_WAVE" })
  local aura, used = find(events, "Z-Power"), find(events, "THUNDER WAVE")
  check(aura and used and aura < used, "aura line before 'used THUNDER WAVE'")
  check(find(events, "boosted SPCL.DEF"), "Sp. Def boost line with the game's stat name")
  eq(b.stages.player.specialDefense, 1, "Sp. Def +1")
  eq(foe.status, "paralyze", "the move itself still runs")
  eq(state(b).used, true, "spent")
  eq(pika.moves[1].pp, 19, "one PP")

  local lapras = newMon("LAPRAS", 30, { "MIST" }, "ICE")
  lapras.hp = 10
  setFlag(game, "EVENT_BEAT_PRYCE")
  local b2 = newBattle({ party = { lapras }, wild = newMon("RATTATA", 5, { "GROWL" }) })
  pressStart(screenFor(b2))
  events = b2:takeTurn({ kind = "move", move = "MIST" })
  local healed = false
  for _, e in ipairs(events) do if e.kind == "heal" and e.side == "player" then healed = true end end
  check(healed, "Z-Mist: a heal event slides the HP bar up")
  check(lapras.hp > 10, "and HP is restored")
  check(find(events, "restored its HP"), "heal line")

  -- Curse is the ??? type in Gen 2: no crystal makes it a Z-Move
  eq(data.moves.ZMOVE_CURSE, nil, "CURSE's ??? type has no crystal")
end

-- 5. accuracy, immunity, fixed and variable power
do
  local pika = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local always = function(n) return (n or 1) - 1 end  -- every roll as high as it goes
  local b = newBattle({ party = { pika }, wild = foe, random = always })
  b.stages.enemy.evasion = 6
  local plain = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(damageTo(plain, "enemy"), 0, "plain THUNDERBOLT misses at +6 evasion")
  pressStart(screenFor(b))
  local events = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  check(damageTo(events, "enemy") > 0, "the Z-Move cannot miss")

  local ground = newMon("GEODUDE", 30, { "TACKLE" })
  local b2 = newBattle({ party = { newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC") }, wild = ground })
  pressStart(screenFor(b2))
  events = b2:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(damageTo(events, "enemy"), 0, "Gigavolt Havoc does not affect GROUND")
  eq(state(b2).used, true, "and the Z-Power is still spent (as in Sun/Moon)")

  local zp = run.exports.zPower
  eq(zp(data.moves.SEISMIC_TOSS), 100, "Seismic Toss -> 100")
  eq(zp(data.moves.RETURN), 160, "Return -> 160")
  eq(zp(data.moves.HYPER_BEAM), 200, "Hyper Beam -> 200")
  eq(zp(data.moves.PIN_MISSILE), 100, "Pin Missile -> 100")
  eq(zp(data.moves.GROWL), nil, "Growl has no damaging Z-Move")
end

-- 6. exclusive Z-Moves: Catastropika and Extreme Evoboost
do
  setFlag(game, "EVENT_BEAT_LTSURGE")
  local pika = newMon("PIKACHU", 30, { "THUNDER", "THUNDERBOLT" }, "PIKANIUM")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local b = newBattle({ party = { pika }, wild = foe })
  local screen = screenFor(b)
  pressStart(screen)
  screen.moveIndex = 2
  resetDrawn()
  Runtime.call("battle.overlay", function() end, screen)
  eq(drawn.texts[1] and drawn.texts[1].t, "Z:NO Z-MOVE", "Pikanium works on THUNDER only")
  local events = b:takeTurn({ kind = "move", move = "THUNDER" })
  check(find(events, "CATASTROPIKA"), "Catastropika")
  check(damageTo(events, "enemy") > 0, "hits (no accuracy roll at 70%)")

  setFlag(game, "EVENT_GOT_EEVEE")
  local eevee = newMon("EEVEE", 30, { "TAKE_DOWN" }, "EEVIUM")
  local b2 = newBattle({ party = { eevee }, wild = newMon("RATTATA", 30, { "TACKLE" }) })
  pressStart(screenFor(b2))
  events = b2:takeTurn({ kind = "move", move = "TAKE_DOWN" })
  check(find(events, "EXTREME"), "Extreme Evoboost")
  local s = b2.stages.player
  eq(s.attack, 2, "Attack +2 (the engine's Swords Dance effect)")
  eq(s.defense, 2, "Defense +2")
  eq(s.speed, 2, "Speed +2")
  eq(s.specialAttack, 2, "Sp. Atk +2")
  eq(s.specialDefense, 2, "Sp. Def +2")
  eq(damageTo(events, "enemy"), 0, "and no attack")
end

-- 7. trainers: Falkner, both sides in one turn, Lance, Red and the rival
local function trainerBattle(classId, partyList, playerMon, name)
  return newBattle({ party = { playerMon },
    trainer = { class = classId, classId = classId, name = name or classId,
                party = partyList } })
end

setFlag(game, "EVENT_BEAT_FALKNER")
do
  local first = newMon("PIDGEOTTO", 20, { "GUST" })
  local ace = newMon("PIDGEOTTO", 22, { "GUST", "WING_ATTACK", "TACKLE" })
  local me = newMon("PIKACHU", 30, { "TACKLE" })
  tank(me)
  local b = trainerBattle("FALKNER", { first, ace }, me, "FALKNER")
  first.hp = 1
  b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(b.enemy, ace, "Falkner's ace comes out")
  eq(state(b).foeUsed, false, "no Z-Move from the first Pokemon")
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  local foeMove = moveEvent(events, "enemy")
  check(find(events, "Enemy PIDGEOTTO used SUPERSONIC"), "Falkner's ace unleashes Supersonic Skystrike")
  eq(foeMove and foeMove.move, "SKY_ATTACK", "no Flying chain in the fixture: SKY ATTACK's animation")
  check(find(events, "Enemy PIDGEOTTO unleashes"), "with the enemy's name")
  eq(ace.moves[2].pp, 34, "WING ATTACK (his strongest Flying move) pays the PP")
  eq(state(b).foeUsed, true, "the trainer's Z-Power is spent")
  eq(ace.moves[2].id, "WING_ATTACK", "his move list is untouched")
  events = b:takeTurn({ kind = "move", move = "TACKLE" })
  local again = moveEvent(events, "enemy")
  check(again and not find(events, "SUPERSONIC"), "only once per battle")
  eq(run.exports.record().faced, 1, "record counts the foe's Z-Move")
end

do -- both sides in the same turn
  local ace = newMon("PIDGEOTTO", 30, { "WING_ATTACK" })
  tank(ace)
  local me = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  tank(me)
  local b = trainerBattle("FALKNER", { ace }, me)
  tank(b.enemy)
  pressStart(screenFor(b))
  local events = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(moveEvent(events, "player").move, "ZMOVE_ELECTRIC", "player's Z-Move")
  if not moveEvent(events, "enemy") then print(table.concat(texts(events), " / ")) end
  check(find(events, "Enemy PIDGEOTTO used SUPERSONIC"), "and the trainer's, same turn")
  eq(me.moves[1].id, "THUNDERBOLT", "player's slot restored")
  eq(ace.moves[1].id, "WING_ATTACK", "trainer's slot never changed")
  eq(state(b).used and state(b).foeUsed, true, "both spent")
end

do -- Lance (the CHAMPION class) and RED
  local dnite = newMon("DRAGONITE", 50, { "OUTRAGE", "HYPER_BEAM" })
  local me = newMon("PIKACHU", 50, { "TACKLE" })
  tank(me)
  local b = trainerBattle("CHAMPION", { dnite }, me, "LANCE")
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  check(find(events, "used DEVASTATING"),
    "Lance's Dragonite: Devastating Drake (his own type beats a stronger HYPER BEAM)")

  local red = newMon("PIKACHU", 80, { "THUNDERBOLT", "QUICK_ATTACK" })
  local me2 = newMon("SLOWPOKE", 50, { "TACKLE" })
  tank(me2)
  local b2 = trainerBattle("RED", { red }, me2, "RED")
  events = b2:takeTurn({ kind = "move", move = "TACKLE" })
  check(find(events, "Enemy PIKACHU used GIGAVOLT"), "RED picks his strongest move's type")
  local b3 = trainerBattle("RED", { newMon("PIKACHU", 80, { "THUNDERBOLT" }) },
    newMon("SLOWPOKE", 50, { "TACKLE" }), "RED")
  b3:endBattle("win")
  eq(run.exports.unlocked("MEWNIUM"), true, "beating RED earns MEWNIUM Z")
end

do -- the rival: from level 30 on only
  local early = newMon("PIDGEOTTO", 22, { "WING_ATTACK" })
  local me = newMon("PIKACHU", 30, { "TACKLE" })
  tank(me)
  local b = trainerBattle("RIVAL1", { early }, me, "SILVER")
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  check(not find(events, "SUPERSONIC"), "Burned Tower rival (22): no Z-Move")
  local late = newMon("PIDGEOTTO", 32, { "WING_ATTACK" })
  local b2 = trainerBattle("RIVAL1", { late }, newMon("PIKACHU", 30, { "TACKLE" }), "SILVER")
  events = b2:takeTurn({ kind = "move", move = "TACKLE" })
  check(find(events, "used SUPERSONIC"), "Goldenrod Underground rival (32): Z-Move")
  local youngster = newMon("RATTATA", 50, { "TACKLE" })
  local b3 = trainerBattle("YOUNGSTER", { youngster }, newMon("PIKACHU", 30, { "TACKLE" }), "JOEY")
  events = b3:takeTurn({ kind = "move", move = "TACKLE" })
  eq(moveEvent(events, "enemy").move, "TACKLE", "an ordinary trainer has no Z-Ring")
end

do -- the warning goes onto the screen's intro queue, never names the move
  local ace = newMon("PIDGEOTTO", 22, { "WING_ATTACK" })
  local b = trainerBattle("FALKNER", { ace }, newMon("PIKACHU", 30, { "TACKLE" }), "FALKNER")
  local screen = screenFor(b, "intro")
  Runtime.emit("battle.started", { battle = screen, kind = "trainer" })
  eq(#screen.pushed, 1, "one warning line")
  eq(screen.pushed[1] and screen.pushed[1].text, "FALKNER wears\na Z-RING!", "the warning")
  Runtime.emit("battle.started", { battle = screen, kind = "trainer" })
  eq(#screen.pushed, 1, "never twice")
end

-- 8. faint and switch before the Z-Move fires
do
  local me = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  me.hp = 1
  local backup = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local fast = newMon("JOLTEON", 50, { "TACKLE" })
  local b = newBattle({ party = { me, backup }, wild = fast })
  pressStart(screenFor(b))
  b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(me.hp, 0, "the faster foe knocks it out first")
  eq(state(b).used, false, "fainted before moving: Z-Power not spent")
  eq(me.moves[1].id, "THUNDERBOLT", "slot restored")
  eq(me.moves[1].pp, 15, "no PP spent")

  local a = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local c = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local b2 = newBattle({ party = { a, c }, wild = foe })
  pressStart(screenFor(b2))
  local t1 = b2:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(state(b2).used, true, "spent by the first Pokemon")
  local sw = b2:takeTurn({ kind = "switch", index = 2 })
  eq(b2.player, c, "switched")
  pressStart(screenFor(b2))
  eq(state(b2).armed, false, "the next Pokemon cannot use another: once per battle")

  -- arming, then switching instead: nothing carries over
  local d = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local e2 = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local b3 = newBattle({ party = { d, e2 }, wild = newMon("RATTATA", 30, { "TACKLE" }) })
  pressStart(screenFor(b3))
  b3:takeTurn({ kind = "switch", index = 2 })
  eq(state(b3).armed, false, "a switch disarms")
  eq(state(b3).used, false, "and spends nothing")
end

-- 9. a save never carries a Z-Move id
do
  local me = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local b = newBattle({ party = { me }, wild = newMon("RATTATA", 5, { "TACKLE" }) })
  local st = nil
  -- reach into a turn: save.writing while the slot is borrowed
  local seen
  local off = Runtime.events and nil
  pressStart(screenFor(b))
  local unsub = run.loader.events:on("battle.move_used", function()
    Runtime.emit("save.writing", { save = game.save })
    seen = me.moves[1].id
  end, -100, "test")
  b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(seen, "THUNDERBOLT", "save.writing mid-turn puts the real move back")
  if type(unsub) == "function" then unsub() end
end

-- 10. options
do
  run.loader.modOptions.z_moves = run.loader.modOptions.z_moves or {}
  run.loader.modOptions.z_moves.trainers = false
  local ace = newMon("PIDGEOTTO", 22, { "WING_ATTACK" })
  local b = trainerBattle("FALKNER", { ace }, newMon("PIKACHU", 30, { "TACKLE" }))
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(moveEvent(events, "enemy").move, "WING_ATTACK", "TRAINER Z-MOVES off")
  run.loader.modOptions.z_moves.trainers = nil

  run.loader.modOptions.z_moves.animations = false
  local me = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local b2 = newBattle({ party = { me }, wild = foe })
  pressStart(screenFor(b2))
  events = b2:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(moveEvent(events, "player").move, "THUNDER", "animations off: THUNDER's animation")
  run.loader.modOptions.z_moves.animations = nil
end

-- 11. party menu
do
  local function rows(n)
    local out = {}
    for i = 1, n do out[i] = { id = "FIELD" .. i, label = "F" .. i } end
    out[#out + 1] = { id = "STATS", label = "STATS" }
    out[#out + 1] = { id = "SWITCH", label = "SWITCH" }
    out[#out + 1] = { id = "MOVE", label = "MOVE" }
    out[#out + 1] = { id = "ITEM", label = "ITEM" }
    out[#out + 1] = { id = "CANCEL", label = "CANCEL" }
    return out
  end
  local mon = newMon("PIKACHU", 30, { "THUNDERBOLT" })
  local list = Runtime.call("ui.party.submenu", function(_, items) return items end,
    game, rows(0), mon, { battle = false })
  eq(list[1].label, "Z-CRYSTAL", "Z-CRYSTAL row before STATS")
  check(type(list[1].onSelect) == "function", "it opens the crystal list")
  eq(#list, 6, "one row added")
  mon.zCrystal = "ELECTRIC"
  list = Runtime.call("ui.party.submenu", function(_, items) return items end,
    game, rows(0), mon, { battle = false })
  eq(list[1].label, "Z:ELECTRIC", "the row names the held crystal")
  mon.zCrystal = "PIKANIUM"
  list = Runtime.call("ui.party.submenu", function(_, items) return items end,
    game, rows(0), mon, { battle = false })
  eq(list[1].label, "Z:PIKANIUM", "exclusive crystal by its stem")
  local full = rows(4)
  table.remove(full) -- 4 field moves + 4 rows, no CANCEL: the box is full
  list = Runtime.call("ui.party.submenu", function(_, items) return items end,
    game, full, mon, { battle = false })
  eq(#list, 8, "a full box gets no row (Z-RING > PARTY handles it)")
  list = Runtime.call("ui.party.submenu", function(_, items) return items end,
    game, rows(0), mon, { battle = true })
  eq(#list, 5, "nothing in the battle submenu")
  for _, w in ipairs({ "Z-CRYSTAL", "Z:ELECTRIC", "Z:PIKANIUM", "Z:FIGHTING" }) do
    check(#w <= 11, w .. " fits the 11-column submenu")
  end
  mon.zCrystal = nil
  -- the crystal list
  game.stack.states = {}
  list = Runtime.call("ui.party.submenu", function(_, items) return items end,
    game, rows(0), mon, { battle = false })
  list[1].onSelect(mon, game)
  local menu = game.stack.states[#game.stack.states]
  eq(menu and menu.title, "Z-CRYSTALS", "opens the crystal list")
  local first = menu and menu.items[1]
  eq(first and first.label, "PIKANIUM Z", "its own species crystal first")
  local found
  for _, it in ipairs(menu.items) do if it.key == "ELECTRIC" then found = it end end
  eq(found and found.right, "OK", "Electrium marked OK for THUNDERBOLT")
  menu.opts.onChoose(found, menu)
  eq(mon.zCrystal, "ELECTRIC", "giving the crystal")
  check(mon.item == nil, "the held-item slot is untouched")
  game.stack.states = {}
end

-- 12. story rewards, the Z-RING and existing saves
do
  -- a fresh game: nothing yet
  local run2, game2 = loadMod()
  Runtime.emit("save.loaded", { save = game2.save })
  local function frame()
    for _ = 1, 25 do Runtime.call("input.step", function() end, game2, 1 / 60) end
  end
  frame()
  eq(#game2.world.shown, 0, "no ring before PROF.ELM's Pokemon")
  game2.world.events:set(FLAG.EVENT_GOT_A_POKEMON_FROM_ELM, true)
  game2.world.isBusy = true
  frame()
  eq(#game2.world.shown, 0, "nothing while a script or warp runs")
  game2.world.isBusy = false
  game2.stack.states = { { kind = "menu" } }
  frame()
  eq(#game2.world.shown, 0, "nothing while a menu is open")
  game2.stack.states = {}
  frame()
  eq(game2.world.shown[1], "GOLD got a\nZ-RING!", "the Z-RING, once the world is idle")
  eq(game2.save.inventory.Z_RING, 1, "into the KEY ITEMS pocket")
  eq(game2.world.sounds[1], "Sfx_Item", "with the item jingle")
  frame()
  eq(#game2.world.shown, 1, "only once")
  game2.world.events:set(FLAG.EVENT_BEAT_WHITNEY, true)
  game2.world.events:set(FLAG.EVENT_BEAT_FALKNER, true)
  frame()
  eq(game2.world.shown[2], "GOLD got\nNORMALIUM Z!", "Whitney: Normalium Z")
  eq(game2.world.shown[3], "GOLD got\nFLYINIUM Z!", "and Falkner's Flyinium Z (two in one go)")
  local normals = 0
  for _, t in ipairs(game2.world.shown) do if t:find("NORMALIUM") then normals = normals + 1 end end
  eq(normals, 1, "Normalium Z is awarded once")
  check(run2.exports.unlocked("NORMAL") and not run2.exports.unlocked("BUG"), "unlock state")
  -- Kimono Girls: all five
  for i = 1, 4 do game2.world.events:set(FLAG["EVENT_BEAT_KIMONO_GIRL_" .. ({ "NAOKO", "SAYO", "ZUKI", "KUNI" })[i]], true) end
  eq(run2.exports.unlocked("PSYCHIC"), false, "four Kimono Girls are not enough")
  game2.world.events:set(FLAG.EVENT_BEAT_KIMONO_GIRL_MIKI, true)
  eq(run2.exports.unlocked("PSYCHIC"), true, "all five: Psychium Z")
  run2.release()

  -- an existing save already past the milestones: no flood of messages
  local run3, game3 = loadMod()
  for _, name in ipairs({ "EVENT_GOT_A_POKEMON_FROM_ELM", "EVENT_BEAT_FALKNER",
      "EVENT_BEAT_BUGSY", "EVENT_BEAT_WHITNEY", "EVENT_BEAT_CLAIR" }) do
    game3.world.events:set(FLAG[name], true)
  end
  Runtime.emit("save.loaded", { save = game3.save })
  for _ = 1, 25 do Runtime.call("input.step", function() end, game3, 1 / 60) end
  eq(#game3.world.shown, 1, "a Champion-era save gets one line")
  eq(game3.world.shown[1], "GOLD put the\nZ-RING in the PACK.", "the ring into the PACK")
  eq(run3.exports.unlocked("DRAGON"), true, "and has its crystals at once")
  run3.release()

  -- the flags are read from the save's bytes when no world is running
  local run4, game4 = loadMod()
  game4.world = nil
  run4.loader.game = game4
  local n = FLAG.EVENT_BEAT_CLAIR
  game4.save.events[math.floor(n / 8)] = 2 ^ (n % 8)
  local n2 = FLAG.EVENT_GOT_A_POKEMON_FROM_ELM
  game4.save.events[math.floor(n2 / 8)] = (game4.save.events[math.floor(n2 / 8)] or 0) + 2 ^ (n2 % 8)
  eq(run4.exports.unlocked("DRAGON"), true, "save-byte fallback")
  run4.release()

  -- ALL mode
  local run5, game5 = loadMod({ options = { crystals = "all" } })
  eq(run5.exports.unlocked("STEEL"), true, "ALL: every crystal")
  for _ = 1, 25 do Runtime.call("input.step", function() end, game5, 1 / 60) end
  eq(game5.save.inventory.Z_RING, 1, "ALL still hands out the Z-RING item")
  run5.release()
end

-- 13. the Z-RING screen
do
  local mon = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  game.save.party = { mon }
  game.stack.states = {}
  Runtime.call("item.use", function() end, game, nil, "Z_RING", nil, {})
  local ring = game.stack.states[1]
  eq(ring and ring.title, "Z-RING", "USE opens the Z-RING")
  eq(ring and #ring.items, 3, "CRYSTALS, PARTY, RECORD")
  ring.opts.onChoose(ring.items[1])
  local coll = game.stack.states[2]
  local dark
  for _, it in ipairs(coll.items) do if it.key == "DARK" then dark = it end end
  eq(dark, nil, "Darkinium not shown before the Radio Tower")
  local elec
  for _, it in ipairs(coll.items) do if it.key == "ELECTRIC" then elec = it end end
  eq(elec and elec.right, "HELD", "Electrium shown as held")
  game.stack.states = { ring }
  ring.opts.onChoose(ring.items[2])
  local party = game.stack.states[2]
  eq(party and party.items[1].right, "ELECTRIUM", "PARTY lists the crystal")
  party.opts.onChoose(party.items[1])
  eq(game.stack.states[3] and game.stack.states[3].title, "Z-CRYSTALS",
    "PARTY gives or takes a crystal too")
  game.stack.states = { ring }
  ring.opts.onChoose(ring.items[3])
  local rec = game.stack.states[2]
  check(rec and rec.text and rec.text:find("Your Z-Moves:", 1, true), "RECORD")
  game.stack.states = {}
  local ran = false
  Runtime.call("item.use", function() ran = true end, game, {}, "Z_RING", nil)
  eq(ran, true, "in battle the game answers for the ring")
end

-- 14. saves: the crystal survives, a save without the mod still loads
do
  local Save = require("src.core.gen2.Save")
  local SaveSerializer = require("src.core.SaveSerializer")
  local mon = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  mon.item = "LEFTOVERS"
  local save = { version = "gold", player = { name = "GOLD" }, party = { mon },
    inventory = { Z_RING = 1, POTION = 3 }, events = {}, modData = { z_moves = { ringGiven = true } } }
  local text = SaveSerializer.encode(save)
  local back = SaveSerializer.decode(text)
  eq(back.party[1].zCrystal, "ELECTRIC", "crystal saved with the Pokemon")
  eq(back.party[1].item, "LEFTOVERS", "beside its held item")
  local ok = pcall(function()
    Save.normalize(back, nil)
    Save.validate(back)
  end)
  check(ok, "a save holding the Z-RING and a crystal validates with the mod off")
  eq(back.inventory.POTION, 3, "other items untouched")
  local hasZ = false
  for _, m in ipairs(back.party) do
    for _, move in ipairs(m.moves or {}) do
      if tostring(move.id):find("ZMOVE_") then hasZ = true end
    end
  end
  eq(hasZ, false, "no Z-Move id in a saved Pokemon")
end

-- 15. link and contest battles are left alone
do
  local me = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local b = Battle.new({ data = data, party = { me }, wild = newMon("RATTATA", 5, { "TACKLE" }),
    random = zeroRandom, battleType = Battle.BATTLETYPE_CONTEST })
  b:takeEvents()
  pressStart(screenFor(b))
  eq(state(b).armed, false, "no Z-Power in the Bug-Catching Contest")
  eq(rawget(b, "takeTurn"), nil, "and the battle is not wrapped")
end

-- 16. sharing the battle with other mods
do
  local original = Battle.takeTurn
  local calls = 0
  Battle.takeTurn = function(self, action) calls = calls + 1 return original(self, action) end
  local me = newMon("PIKACHU", 30, { "THUNDERBOLT" }, "ELECTRIC")
  local foe = newMon("RATTATA", 30, { "TACKLE" })
  tank(foe)
  local b = newBattle({ party = { me }, wild = foe })
  pressStart(screenFor(b))
  local events = b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(calls, 1, "another mod's wrap of the battle class still runs")
  check(find(events, "GIGAVOLT"), "and the Z-Move still fires through it")
  b:takeTurn({ kind = "move", move = "THUNDERBOLT" })
  eq(calls, 2, "every turn")
  Battle.takeTurn = original
  b:endBattle("run")
  eq(rawget(b, "takeTurn"), nil, "the battle is unwrapped when it ends")

  -- the overworld's own "can I open a menu" answer holds rewards back too
  local run6, game6 = loadMod()
  game6.world.events:set(FLAG.EVENT_GOT_A_POKEMON_FROM_ELM, true)
  game6.world.acceptsMenuInput = function() return false end
  for _ = 1, 25 do Runtime.call("input.step", function() end, game6, 1 / 60) end
  eq(#game6.world.shown, 0, "nothing while the world takes no menu input")
  game6.world.acceptsMenuInput = function() return true end
  game6.phase = "boot"
  for _ = 1, 25 do Runtime.call("input.step", function() end, game6, 1 / 60) end
  eq(#game6.world.shown, 0, "nothing outside play")
  game6.phase = "play"
  for _ = 1, 25 do Runtime.call("input.step", function() end, game6, 1 / 60) end
  eq(#game6.world.shown, 1, "shown once the world is free")
  run6.release()
end

run.release()
print(("%d/%d checks passed  (z_moves gen 2)"):format(checks - failures, checks))
if failures > 0 then os.exit(1) end
