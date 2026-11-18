-- Z-Moves test suite (Gen 1).  Run from a Gen1Recomp source checkout with
-- this mod at mods/z_moves:
--   luajit mods/z_moves/tests/z_moves_test.lua
--
-- ROM-free.  The mod loads through the real loader and sandbox against the
-- fixture dataset.  Battles walk the same event and hook order
-- src/battle/BattleState.lua raises (enemy_action -> turn_started ->
-- performMove: PP, "used X!" + animation row queued, move_used, accuracy,
-- damage -> turn_ended), damage comes from the engine's own Damage.compute,
-- the bag from src/inventory/Bag and save repair from SaveData.validate.
-- Only drawing (Font, ListMenu, TextBox) is stubbed, so what the mod draws
-- and opens can be read back.
package.path = "./?.lua;./?/init.lua;" .. package.path

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
local pushed = {}
package.loaded["src.ui.ListMenu"] = { new = function(_, title, items, opts)
  return { kind = "list", title = title, items = items, opts = opts,
           close = function() end } end }
package.loaded["src.render.TextBox"] = { new = function(_, text)
  return { kind = "text", text = text } end }

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Damage = require("src.battle.Damage")

-- ------- data

local data = T.fixtures.fresh()
local function add(id, type_, power, effect, name)
  data.moves[id] = { id = id, name = name or id:gsub("_", " "), type = type_,
    power = power, accuracy = 100, pp = 15,
    effect = effect or "NO_ADDITIONAL_EFFECT", anim = { sound = id } }
end
add("HYPER_BEAM", "NORMAL", 150, "HYPER_BEAM_EFFECT")
add("FIRE_BLAST", "FIRE", 120)
add("HYDRO_PUMP", "WATER", 120)
add("THUNDER", "ELECTRIC", 120)
add("THUNDERBOLT", "ELECTRIC", 95, "PARALYZE_SIDE_EFFECT1")
add("THUNDER_WAVE", "ELECTRIC", 0, "PARALYZE_EFFECT")
add("PSYCHIC_M", "PSYCHIC_TYPE", 90, nil, "PSYCHIC")
add("NIGHT_SHADE", "GHOST", 0, "SPECIAL_DAMAGE_EFFECT")
add("QUICK_ATTACK", "NORMAL", 40)
add("FISSURE", "GROUND", 1, "OHKO_EFFECT")
add("EARTHQUAKE", "GROUND", 100)
add("BLIZZARD", "ICE", 120)
add("TAKE_DOWN", "NORMAL", 90, "RECOIL_EFFECT")
add("PIN_MISSILE", "BUG", 14, "TWO_TO_FIVE_ATTACKS_EFFECT")
add("SWORDS_DANCE", "NORMAL", 0, "ATTACK_UP2_EFFECT")
add("SPLASH", "NORMAL", 0, "SPLASH_EFFECT")
add("RECOVER", "NORMAL", 0, "HEAL_EFFECT")
add("HAZE", "ICE", 0, "HAZE_EFFECT")
add("SOLARBEAM", "GRASS", 120, "CHARGE_EFFECT")

-- immunities and super-effective pairs the checks below lean on
local chart = data.type_chart.matchups
chart[#chart + 1] = { attacker = "ELECTRIC", defender = "GROUND", multiplier = 0 }
chart[#chart + 1] = { attacker = "ELECTRIC", defender = "WATER", multiplier = 20 }
chart[#chart + 1] = { attacker = "NORMAL", defender = "GHOST", multiplier = 0 }
chart[#chart + 1] = { attacker = "GROUND", defender = "FLYING", multiplier = 0 }

-- a slice of the animation table, shaped like data/generated/battle_anims
data.battle_anims = { subanims = {}, tilesheets = {}, idEffects = {}, moveAnims = {
  THUNDERBOLT = { seq = { { subanim = 93, tileset = 1, delay = 2, sound = "THUNDERBOLT" } } },
  THUNDER = { seq = {
    { effect = "SE_DARK_SCREEN_PALETTE", sound = "THUNDER" },
    { subanim = 95, tileset = 1, delay = 6 },
    { effect = "SE_RESET_SCREEN_PALETTE" } } },
} }

local run = T.sdk.loadMod("mods/z_moves", { data = data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
require("src.battle.TypeChart").load(data)
local api = run.loader.exports.z_moves

local pressed = {}
local game = { data = data, stack = { states = {} },
  input = { wasPressed = function(_, b) return pressed[b] or false end } }
game.stack.push = function(_, st) pushed[#pushed + 1] = st end
run.loader.game = game
local options = { crystals = "all" }
run.loader.modOptions.z_moves = options
local function topPushed() return pushed[#pushed] end

-- ------- content

T.check(data.moves.ZMOVE_ELECTRIC ~= nil, "Gigavolt Havoc is registered")
T.eq(data.moves.ZMOVE_ELECTRIC.name, "GIGAVOLT\nHAVOC", "with its two-line battle name")
T.eq(data.moves.ZMOVE_PSYCHIC.type, "PSYCHIC_TYPE", "pokered's PSYCHIC_TYPE id is kept")
T.check(data.moves.ZMOVE_FLYING == nil, "no record for a type whose sample move is missing")
T.eq(data.moves.THUNDERBOLT.power, 95, "vanilla Thunderbolt is untouched")
T.check(data.items.Z_RING and data.items.Z_RING.keyItem == true, "the Z-RING is a key item")
T.eq(data.items.Z_RING.tossable, false, "that cannot be tossed")
T.eq(data.text._ZMovesUnleashText, "{USER}\nunleashes its\nfull-force Z-Move!",
  "battle lines are registered text")
T.eq(data.text._ZMovesGotELECTRICText, "{PLAYER} got\nELECTRIUM Z!", "so are the crystal messages")

-- ------- the Sun/Moon power table

T.eq(api.zPower(data.moves.THUNDERBOLT), 175, "95 -> 175")
T.eq(api.zPower(data.moves.QUICK_ATTACK), 100, "40 -> 100")
T.eq(api.zPower(data.moves.THUNDER), 190, "120 -> 190")
T.eq(api.zPower(data.moves.HYPER_BEAM), 200, "150 -> 200")
T.eq(api.zPower(data.moves.FISSURE), 180, "OHKO moves -> 180")
T.eq(api.zPower(data.moves.NIGHT_SHADE), 100, "fixed-damage moves -> 100")
T.eq(api.zPower(data.moves.THUNDER_WAVE), nil, "status moves have no damaging Z-Move")
T.eq(api.zStatus(data.moves.THUNDER_WAVE)[1], "special", "they have a status Z-effect instead")

-- ------- a battle, shaped like src/battle/BattleState.lua

local ruleset = require("src.battle.rulesets.gen1_faithful")
local function stats() return { hp = 120, attack = 80, defense = 80, speed = 80, special = 80 } end
local function battler(isPlayer, name, types, moves, level)
  local mon = { species = "FIXMON_A", level = level or 50, hp = 120, stats = stats(), moves = moves }
  return { isPlayer = isPlayer, name = name, mon = mon, curStats = mon.stats,
    curTypes = types, curMoves = mon.moves, stages = {}, def = { baseStats = { speed = 1 } } }
end

local Battle = {}
Battle.__index = Battle
Battle.isBattleState = true
function Battle:sayAuto(text, d) self.queue[#self.queue + 1] = { text = text, auto = true, autoDelay = d } end
function Battle:say(text) self.queue[#self.queue + 1] = { text = text } end
function Battle:sayNextAuto(text, d)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { text = text, auto = true, autoDelay = d or 0 })
end
function Battle:sayNext(text)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { text = text })
end
function Battle:drainNext(b, stopAt)
  self.nextInsert = (self.nextInsert or 0) + 1
  table.insert(self.queue, self.nextInsert, { drain = true, battler = b, stopAt = stopAt })
end
function Battle:romLine(id) return id == "EnemyText" and "Enemy " or "" end
function Battle:lockedAction() return self.locked end
function Battle:wideLayout() return self.wide == true end

local function newBattle(crystal, opts)
  opts = opts or {}
  local moves = opts.moves or { { id = "THUNDERBOLT", pp = 15 }, { id = "QUICK_ATTACK", pp = 30 },
    { id = "THUNDER_WAVE", pp = 20 } }
  local b = setmetatable({ kind = opts.kind or "trainer", phase = "menu", data = data,
    ruleset = ruleset, queue = {}, moveIndex = 1, turnCount = 0, game = game,
    player = battler(true, "PIKACHU", { "ELECTRIC" }, moves),
    enemy = battler(false, "ONIX", opts.enemyTypes or { "WATER" },
      opts.enemyMoves or { { id = "QUICK_ATTACK", pp = 30 } }),
    sides = { { index = 1, tokens = {} }, { index = 2, tokens = {} } } }, Battle)
  b.player.mon.zCrystal = crystal
  if opts.species then b.player.mon.species = opts.species end
  game.stack.states = { b }
  Runtime.emit("battle.started", { battle = b, kind = b.kind })
  return b
end

local function step(button)
  pressed = button and { [button] = true } or {}
  Runtime.call("input.step", function() end, game, 1 / 60)
  pressed = {}
end
-- START is read on the fixed step after the press
local function pressStart() step("start") step() end
local function openMoves(b) b.phase = "moveSelect" end

local function texts(b)
  local out = {}
  for _, row in ipairs(b.queue) do
    if row.text then out[#out + 1] = row.text
    elseif row.anim then out[#out + 1] = "<anim " .. row.anim .. ">"
    elseif row.drain then out[#out + 1] = "<drain " .. tostring(row.stopAt) .. ">" end
  end
  return table.concat(out, " | ")
end

-- BattleState:performMove, as far as Z-Power reaches into it
local function performMove(b, user, target, inst, hits)
  local move = data.moves[inst.id]
  inst.pp = inst.pp - 1
  b.moveAnimRow = nil
  b.nextInsert = #b.queue
  b:sayNextAuto(user.name .. "\nused " .. move.name .. "!")
  local out = { announced = b.queue[b.nextInsert].text }
  b.nextInsert = b.nextInsert + 1
  b.moveAnimRow = { anim = move.id, attackerIsPlayer = user.isPlayer }
  table.insert(b.queue, b.nextInsert, b.moveAnimRow)
  Runtime.emit("battle.move_used", { battle = b, user = user, target = target,
    move = move, isCalled = false })
  out.anim = b.moveAnimRow.anim
  user.lastMove = move.id
  if (move.power or 0) > 0 then
    out.hit = Runtime.call("battle.accuracy", function() return hits ~= false end,
      { battle = b, ruleset = ruleset, move = move, user = user, target = target })
    if out.hit then
      out.damage, out.info = Runtime.call("battle.damage", function(c)
        return Damage.compute(c.ruleset, c.user, c.target, c.move, c.opts)
      end, { battle = b, ruleset = ruleset, user = user, target = target, move = move,
             opts = { forceCrit = false, rng = function(_, hi) return hi end } })
    end
  end
  return out
end

-- resolveTurn: the AI picks, turn_started, both sides act, turn_ended.
-- opts.asleep / opts.enemyItem keep a side from moving; opts.enemyFirst
-- orders the turn.
local function turn(b, slot, opts)
  opts = opts or {}
  b.queue = {}
  b.moveIndex = slot
  local mine = slot and b.player.curMoves[slot]
  local theirs = Runtime.call("battle.enemy_action", function(bb)
    return bb.enemy.curMoves[opts.enemySlot or 1]
  end, b)
  b.turnCount = b.turnCount + 1
  Runtime.emit("battle.turn_started", { battle = b, turn = b.turnCount,
    playerAction = mine, enemyAction = theirs })
  b.phase = "messages"
  local result = { idDuringTurn = mine and mine.id, enemyAction = theirs }
  local function me()
    if mine and not opts.asleep then
      result.player = performMove(b, b.player, b.enemy, mine, opts.hits)
    end
  end
  local function them()
    if theirs and not opts.enemyItem then
      result.enemy = performMove(b, b.enemy, b.player, theirs, opts.enemyHits)
    end
  end
  if opts.enemyFirst then them() me() else me() them() end
  result.texts = texts(b)
  result.idAfterMove = mine and mine.id
  Runtime.emit("battle.turn_ended", { battle = b, turn = b.turnCount })
  b.phase = "menu"
  return result
end

local function hitFor(user, target, type_, power)
  return Damage.compute(ruleset, user, target, { id = "X", type = type_, power = power,
    accuracy = 100 }, { forceCrit = false, rng = function(_, hi) return hi end })
end

-- ------- an ordinary turn is vanilla

local battle = newBattle("ELECTRIC", { enemyTypes = { "ROCK" } })
openMoves(battle)
local plain = turn(battle, 1)
T.eq(plain.player.announced, "PIKACHU\nused THUNDERBOLT!", "without Z-Power the move is itself")
T.eq(plain.texts, "PIKACHU\nused THUNDERBOLT! | <anim THUNDERBOLT> | ONIX\nused QUICK ATTACK! | <anim QUICK_ATTACK>",
  "and nothing extra is said")
local plainDamage = plain.player.damage

-- ------- arming

battle = newBattle("ELECTRIC", { enemyTypes = { "ROCK" } })
openMoves(battle)
pressStart()
T.check(api.state(battle).armed, "START in the move list arms Z-Power")
pressStart()
T.check(not api.state(battle).armed, "START again disarms it")
battle.phase = "menu"
local claimed = Runtime.call("battle.menu_auxiliary", function() return false end, game, {})
T.eq(claimed, true, "START on the command menu is claimed for a crystal holder")
T.check(api.state(battle).armed, "and arms Z-Power")

-- ------- the Z-Move turn

openMoves(battle)
local z = turn(battle, 1, { hits = false })
T.eq(z.texts, "PIKACHU\nunleashes its\nfull-force Z-Move! | PIKACHU\nused GIGAVOLT\nHAVOC! | "
  .. "<anim ZMOVE_ELECTRIC> | ONIX\nused QUICK ATTACK! | <anim QUICK_ATTACK>",
  "the Z-Power line comes right before the move, then its own animation")
T.eq(z.player.hit, true, "a Z-Move bypasses a failed accuracy roll")
T.eq(z.player.damage, hitFor(battle.player, battle.enemy, "ELECTRIC", 175),
  "damage is the vanilla formula at Z power")
T.check(z.player.damage > plainDamage, "and it out-hits plain Thunderbolt")
T.eq(z.idAfterMove, "THUNDERBOLT", "the slot is the real move again")
T.eq(battle.player.curMoves[1].pp, 14, "1 PP came off the real move")
T.eq(battle.player.lastMove, "THUNDERBOLT", "Mirror Move would copy Thunderbolt")
T.eq(data.moves.ZMOVE_ELECTRIC.power, 100, "the registry record was not written")
T.check(api.state(battle).used, "Z-Power is spent")
T.check(battle.sides[1].tokens[1] and battle.sides[1].tokens[1].id == "z_moves.used",
  "the spent mark is a side token")

openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "once per battle")
T.eq(battle and api.state(battle).used, true, "still spent")
local after = turn(battle, 1)
T.eq(after.player.announced, "PIKACHU\nused THUNDERBOLT!", "the next turn is ordinary")
T.eq(after.player.damage, plainDamage, "at ordinary damage")

-- ------- type matchups stay the engine's

battle = newBattle("ELECTRIC", { enemyTypes = { "WATER" } })
openMoves(battle) pressStart()
local strong = turn(battle, 1)
T.eq(strong.player.damage, hitFor(battle.player, battle.enemy, "ELECTRIC", 175),
  "super effective against WATER, through the engine's chart")
T.check(strong.player.damage > z.player.damage, "and more than the neutral hit")

battle = newBattle("ELECTRIC", { enemyTypes = { "GROUND" } })
openMoves(battle) pressStart()
local immune = turn(battle, 1)
T.eq(immune.player.damage, 0, "a GROUND foe is still immune to Gigavolt Havoc")

battle = newBattle("NORMAL", { enemyTypes = { "GHOST" },
  moves = { { id = "QUICK_ATTACK", pp = 30 } } })
openMoves(battle) pressStart()
T.eq(turn(battle, 1).player.damage, 0, "a GHOST is immune to Breakneck Blitz")

-- ------- kept from moving: Z-Power is not spent (as in Sun/Moon)

battle = newBattle("ELECTRIC", { enemyTypes = { "ROCK" } })
openMoves(battle) pressStart()
local slept = turn(battle, 1, { asleep = true })
T.eq(slept.idDuringTurn, "ZMOVE_ELECTRIC", "the slot points at the Z-Move during the turn")
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "and is restored when the turn ends")
T.eq(battle.player.curMoves[1].pp, 15, "no PP was spent")
T.check(not slept.texts:find("unleashes"), "nothing is announced")
T.check(not api.state(battle).used, "Z-Power is kept")
T.check(not api.state(battle).armed, "and has to be armed again")
openMoves(battle) pressStart()
T.eq(turn(battle, 1).player.announced, "PIKACHU\nused GIGAVOLT\nHAVOC!", "the next turn it fires")

-- ------- wrong type, no crystal, link

battle = newBattle("ELECTRIC")
openMoves(battle) pressStart()
T.eq(turn(battle, 2).player.announced, "PIKACHU\nused QUICK ATTACK!", "a move of another type stays itself")
T.check(not api.state(battle).used, "and does not spend Z-Power")

battle = newBattle(nil)
openMoves(battle) pressStart()
T.check(not api.state(battle).armed, "no crystal, no Z-Power")

battle = newBattle("ELECTRIC", { kind = "link" })
openMoves(battle) pressStart()
T.check(not api.state(battle).armed, "link battles are untouched")

battle = newBattle("ELECTRIC", { kind = "wild" })
openMoves(battle) pressStart()
T.check(api.state(battle).armed, "wild battles allow it")
Runtime.emit("battle.battler_switched", { battle = battle })
T.check(not api.state(battle).armed, "switching disarms")

-- ------- status Z-Moves

battle = newBattle("ELECTRIC")
battle.player.stages.special = -2
openMoves(battle) pressStart()
local tw = turn(battle, 3)
T.eq(tw.texts, "PIKACHU\nsurrounded itself\nwith its Z-Power! | PIKACHU\nused THUNDER WAVE! | "
  .. "<anim THUNDER_WAVE> | PIKACHU\nboosted SPECIAL\nwith its Z-Power! | ONIX\nused QUICK ATTACK! | "
  .. "<anim QUICK_ATTACK>", "aura, the move under its own name, then the bonus")
T.eq(battle.player.stages.special, -1, "Z-Thunder Wave raises SPECIAL one stage")
T.eq(battle.player.curMoves[3].id, "THUNDER_WAVE", "the slot was never repointed")
T.check(api.state(battle).used, "it spends Z-Power")

battle = newBattle("NORMAL", { moves = { { id = "SPLASH", pp = 40 }, { id = "RECOVER", pp = 20 } } })
battle.player.stages = { attack = 5, defense = -3, evasion = -1 }
openMoves(battle) pressStart()
turn(battle, 1)
T.eq(battle.player.stages.attack, 6, "Z-Splash is +3 Attack, capped at +6")

battle = newBattle("NORMAL", { moves = { { id = "SPLASH", pp = 40 }, { id = "RECOVER", pp = 20 } } })
battle.player.stages = { attack = 2, defense = -3, evasion = -1 }
openMoves(battle) pressStart()
local rec = turn(battle, 2)
T.eq(battle.player.stages.defense, 0, "a reset lifts lowered stats")
T.eq(battle.player.stages.evasion, 0, "all of them")
T.eq(battle.player.stages.attack, 2, "and keeps raised ones")
T.check(rec.texts:find("reset its stats", 1, true), "and says so")

battle = newBattle("ICE", { moves = { { id = "HAZE", pp = 30 } } })
battle.player.mon.hp = 7
openMoves(battle) pressStart()
local haze = turn(battle, 1)
T.eq(battle.player.mon.hp, 120, "Z-Haze restores all HP")
T.check(haze.texts:find("restored its HP\nwith its Z-Power! | <drain 120>", 1, true),
  "and the HP bar slides up to full, like RECOVER's")

-- ------- species-exclusive Z-Moves

battle = newBattle("PIKANIUM", { species = "PIKACHU", enemyTypes = { "ROCK" },
  moves = { { id = "THUNDERBOLT", pp = 15 }, { id = "THUNDER", pp = 10 } } })
openMoves(battle) pressStart()
local cat = turn(battle, 2)
T.eq(cat.player.announced, "PIKACHU\nused CATASTROPIKA!", "Pikachu's Thunder becomes Catastropika")
T.eq(cat.player.damage, hitFor(battle.player, battle.enemy, "ELECTRIC", 210), "at 210 power")
T.eq(battle.player.curMoves[2].id, "THUNDER", "and the slot is Thunder again")

battle = newBattle("PIKANIUM", { species = "PIKACHU" })
openMoves(battle) pressStart()
T.check(not api.state(battle).armed, "Pikanium Z does not power ordinary Electric moves")

battle = newBattle("PIKANIUM", { species = "RAICHU",
  moves = { { id = "THUNDER", pp = 10 } } })
openMoves(battle) pressStart()
T.check(not api.state(battle).armed, "another species cannot use it")

battle = newBattle("EEVIUM", { species = "EEVEE", moves = { { id = "TAKE_DOWN", pp = 20 } } })
battle.player.stages = { speed = 5 }
openMoves(battle) pressStart()
local evo = turn(battle, 1)
T.eq(evo.player.announced, "PIKACHU\nused EXTREME\nEVOBOOST!", "Eevee's Take Down becomes Extreme Evoboost")
T.eq(battle.player.stages.defense, 2, "Defense +2")
T.eq(battle.player.stages.special, 2, "Special +2")
T.eq(battle.player.stages.speed, 6, "Speed capped at +6")
T.check(evo.texts:find("boosted its stats", 1, true), "and says so")

-- ------- animations

local seq = data.battle_anims.moveAnims.ZMOVE_ELECTRIC.seq
local parts = {}
for _, row in ipairs(seq) do parts[#parts + 1] = row.effect or ("sub" .. row.subanim) end
T.eq(table.concat(parts, " "), "SE_DARK_SCREEN_PALETTE SE_SPIRAL_BALLS_INWARD SE_DARK_SCREEN_FLASH"
  .. " sub93 sub95 SE_DARK_SCREEN_FLASH SE_DARK_SCREEN_FLASH SE_SHAKE_SCREEN SE_RESET_SCREEN_PALETTE",
  "charge-up, Thunderbolt, Thunder, the finish, and the palette back last")
T.eq(data.battle_anims.moveAnims.THUNDER.seq[3].effect, "SE_RESET_SCREEN_PALETTE",
  "Thunder's own animation is untouched")
T.check(data.battle_anims.moveAnims.ZMOVE_WATER == nil, "a type with no source animations keeps borrowing")

options.animations = false
battle = newBattle("ELECTRIC")
openMoves(battle) pressStart()
T.eq(turn(battle, 1).player.anim, "THUNDER", "Z-MOVE ANIMATIONS off: Thunder's animation")
options.animations = nil

-- ------- trainers

local function leaderBattle(oppClass, aceMoves, o)
  o = o or {}
  local b = newBattle(nil, { enemyTypes = o.enemyTypes or { "ROCK" } })
  b.oppClass = oppClass
  b.trainer = { name = o.trainerName or "MISTY" }
  local first = battler(false, "STARYU", { "ROCK" }, { { id = "QUICK_ATTACK", pp = 30 } })
  local ace = battler(false, "STARMIE", o.enemyTypes or { "ROCK" }, aceMoves, o.level)
  b.enemyParty = { first.mon, ace.mon }
  b.enemy = o.first and first or ace
  b.locked = o.locked
  b.queue = {}
  Runtime.emit("battle.started", { battle = b, kind = "trainer" })
  return b
end

battle = leaderBattle("OPP_MISTY", { { id = "QUICK_ATTACK", pp = 30 },
  { id = "HYDRO_PUMP", pp = 5 }, { id = "THUNDERBOLT", pp = 15 } })
T.eq(texts(battle), "MISTY wears\na Z-RING!", "a Z-Ring trainer is announced as the battle opens")
local zt = turn(battle, 2)
T.eq(zt.enemyAction.id, "HYDRO_PUMP", "Misty's ace switches to its Water move")
T.eq(zt.texts, "PIKACHU\nused QUICK ATTACK! | <anim QUICK_ATTACK> | Enemy STARMIE\nunleashes its\n"
  .. "full-force Z-Move! | STARMIE\nused HYDRO\nVORTEX! | <anim HYDRO_PUMP>",
  "the enemy's Z-Power line comes right before its move (the fixture has no Water "
  .. "animations to build from, so Hydro Vortex borrows Hydro Pump's)")
T.eq(zt.enemy.damage, hitFor(battle.enemy, battle.player, "WATER", 190), "Hydro Vortex at 190")
T.eq(battle.enemy.curMoves[2].id, "HYDRO_PUMP", "the slot is Hydro Pump again")
T.eq(battle.enemy.lastMove, "HYDRO_PUMP", "Mirror Move would copy Hydro Pump")
T.check(api.state(battle).foeUsed, "the trainer's Z-Power is spent")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused QUICK ATTACK!", "once per battle")

battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
local potion = turn(battle, 2, { enemyItem = true })
T.check(not potion.texts:find("unleashes"), "a turn the trainer spends on an item says nothing")
T.check(not api.state(battle).foeUsed, "and keeps its Z-Power")
T.eq(battle.enemy.curMoves[1].id, "HYDRO_PUMP", "with the slot restored")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO\nVORTEX!", "it fires the next turn")

battle = leaderBattle("OPP_MISTY", { { id = "QUICK_ATTACK", pp = 30 } }, { first = true })
T.eq(turn(battle, 2).enemy.announced, "STARYU\nused QUICK ATTACK!", "only the last Pokemon holds the crystal")

battle = leaderBattle("OPP_MISTY", { { id = "QUICK_ATTACK", pp = 30 }, { id = "THUNDERBOLT", pp = 15 } })
local fallback = turn(battle, 2)
T.eq(fallback.enemy.announced, "STARMIE\nused GIGAVOLT\nHAVOC!",
  "without a move of its type, the strongest type it has")
T.eq(fallback.enemy.anim, "ZMOVE_ELECTRIC", "a trainer's Z-Move plays its own Z animation")

battle = leaderBattle("OPP_YOUNGSTER", { { id = "HYDRO_PUMP", pp = 5 } })
T.eq(texts(battle), "", "an ordinary trainer is not announced")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO PUMP!", "and has no Z-Power")

battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } }, { locked = { id = "HYDRO_PUMP" } })
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO PUMP!", "a locked turn is left alone")

battle = leaderBattle("OPP_RIVAL2", { { id = "HYDRO_PUMP", pp = 5 } }, { level = 25, trainerName = "BLUE" })
T.eq(texts(battle), "", "the rival at the Pokemon Tower: no Z-Ring")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO PUMP!", "and no Z-Move")
battle = leaderBattle("OPP_RIVAL2", { { id = "HYDRO_PUMP", pp = 5 } }, { level = 40, trainerName = "BLUE" })
T.eq(texts(battle), "BLUE wears\na Z-RING!", "the rival at Silph Co.: a Z-Ring")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO\nVORTEX!", "and his Z-Move")
battle = leaderBattle("OPP_RIVAL3", { { id = "HYDRO_PUMP", pp = 5 } }, { trainerName = "BLUE" })
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO\nVORTEX!", "the Champion too")

options.warnings = false
battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
T.eq(texts(battle), "", "Z-RING WARNING off: no heads-up")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO\nVORTEX!", "the Z-Move still comes")
options.warnings = nil
options.trainers = false
battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
T.eq(texts(battle), "", "TRAINER Z-MOVES off: no heads-up either")
T.eq(turn(battle, 2).enemy.announced, "STARMIE\nused HYDRO PUMP!", "and no Z-Move")
options.trainers = nil

-- ------- both sides in one turn, either order

for _, enemyFirst in ipairs({ false, true }) do
  battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } }, { enemyTypes = { "ROCK" } })
  battle.player.mon.zCrystal = "ELECTRIC"
  openMoves(battle) pressStart()
  local both = turn(battle, 1, { enemyFirst = enemyFirst })
  local tag = enemyFirst and " (foe first)" or " (player first)"
  T.eq(both.player.announced, "PIKACHU\nused GIGAVOLT\nHAVOC!", "the player's Z-Move" .. tag)
  T.eq(both.enemy.announced, "STARMIE\nused HYDRO\nVORTEX!", "and the trainer's" .. tag)
  T.eq(both.player.damage, hitFor(battle.player, battle.enemy, "ELECTRIC", 175), "each at its own power" .. tag)
  T.eq(both.enemy.damage, hitFor(battle.enemy, battle.player, "WATER", 190), "both" .. tag)
  T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "both slots come back" .. tag)
  T.eq(battle.enemy.curMoves[1].id, "HYDRO_PUMP", "both slots come back" .. tag)
  T.check(api.state(battle).used and api.state(battle).foeUsed, "both spent" .. tag)
end

-- ------- a battle checkpoint keeps the spent marks

local function restoredCopy(b)
  local copy = setmetatable({}, Battle)
  for k, v in pairs(b) do copy[k] = v end
  copy.sides = { { index = 1, tokens = { table.unpack(b.sides[1].tokens) } },
                 { index = 2, tokens = { table.unpack(b.sides[2].tokens) } } }
  return copy
end
local restored = restoredCopy(battle)
T.check(api.state(restored).used, "a battle rebuilt from a checkpoint knows the player's Z is spent")
T.check(api.state(restored).foeUsed, "and the trainer's")

-- ------- a save mid-turn never carries a Z-Move id

battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
battle.player.mon.zCrystal = "ELECTRIC"
openMoves(battle) pressStart()
local act = Runtime.call("battle.enemy_action", function(bb) return bb.enemy.curMoves[1] end, battle)
Runtime.emit("battle.turn_started", { battle = battle, turn = 1,
  playerAction = battle.player.curMoves[1], enemyAction = act })
T.eq(battle.player.curMoves[1].id, "ZMOVE_ELECTRIC", "mid-turn the player's slot is borrowed")
T.eq(battle.enemy.curMoves[1].id, "ZMOVE_WATER", "and the trainer's")
Runtime.emit("save.writing", {})
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "save.writing hands the player's back")
T.eq(battle.enemy.curMoves[1].id, "HYDRO_PUMP", "and the trainer's")
Runtime.emit("battle.ended", { battle = battle })

-- ------- fainting or switching before the Z-Move fires

battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
battle.player.mon.zCrystal = "ELECTRIC"
openMoves(battle) pressStart()
act = Runtime.call("battle.enemy_action", function(bb) return bb.enemy.curMoves[1] end, battle)
Runtime.emit("battle.turn_started", { battle = battle, turn = 1,
  playerAction = battle.player.curMoves[1], enemyAction = act })
Runtime.emit("battle.fainted", { battle = battle, battler = battle.player })
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "a Pokemon that faints first gets its move back at once")
T.eq(battle.enemy.curMoves[1].id, "ZMOVE_WATER", "the other side's Z-Move still stands")
T.check(not api.state(battle).used, "the fainted side's Z-Power is not spent")
Runtime.emit("battle.battler_switched", { battle = battle })
T.eq(battle.enemy.curMoves[1].id, "HYDRO_PUMP", "a switch hands back what is left")
T.check(not api.state(battle).foeUsed, "and spends nothing")
Runtime.emit("battle.ended", { battle = battle })

-- ------- a translation can replace every line, slots it does not know stay put

data.text._ZMovesUnleashText = "{USER} bruker\nZ-kraft! {UKJENT}"
battle = newBattle("ELECTRIC", { enemyTypes = { "ROCK" } })
openMoves(battle) pressStart()
T.check(turn(battle, 1).texts:find("PIKACHU bruker\nZ-kraft! {UKJENT}", 1, true),
  "an overriding translation is used, an unknown slot is left as written")
data.text._ZMovesUnleashText = "{USER}\nunleashes its\nfull-force Z-Move!"

-- ------- the battle overlay: classic and widescreen

local function overlay(b)
  resetDrawn()
  Runtime.call("battle.overlay", function() end, b)
  local out = {}
  for _, t in ipairs(drawn.texts) do out[#out + 1] = ("%s@%d,%d"):format(t.t, t.x, t.y) end
  return table.concat(out, " ")
end

battle = newBattle("ELECTRIC")
openMoves(battle)
T.eq(overlay(battle), "Z@16,104 Z@16,120", "classic: a Z beside each move that can become one")
pressStart()
T.eq(overlay(battle), "Z:GIGAVOLT HAVOC@0,40 175@136,40", "armed: the slim bar")
battle.moveIndex = 3
T.eq(overlay(battle), "Z:THUNDER WAVE@0,40 SPC+1@120,40", "a status move shows its bonus")
battle.moveIndex = 2
T.eq(overlay(battle), "Z:NO Z-MOVE@0,40", "a move with no Z-Move says so")
battle.phase = "menu"
T.eq(overlay(battle), "Z:POWER READY@0,40", "on the command menu")
battle.phase = "messages"
T.eq(overlay(battle), "", "gone once the move is confirmed")

battle = newBattle("ELECTRIC")
battle.wide = true
openMoves(battle)
T.eq(overlay(battle), "Z@104,104 Z@104,136",
  "widescreen: Z tabs on the box border by each move (slots 1 and 3: the left column)")
pressStart()
T.eq(overlay(battle), "Z:GIGAVOLT HAVOC@72,40 175@208,40", "and the bar centred on the wider field")

battle = newBattle(nil)
openMoves(battle) pressStart()
T.eq(overlay(battle), "Z:NO CRYSTAL HELD@0,40", "a refusal shows on the bar")

battle = newBattle("GHOST", { moves = { { id = "NIGHT_SHADE", pp = 15 } } })
openMoves(battle) pressStart()
local frames = {}
for f = 0, 200, 25 do
  frames[#frames + 1] = overlay(battle):match("^(Z:[^@]*)")
  for _ = 1, 25 do step() end
end
T.eq(frames[1], "Z:NEVER-ENDING N", "a long name starts at its beginning")
T.check(frames[4] ~= frames[1], "then scrolls")
T.check(table.concat(frames, " "):find("NIGHTMARE", 1, true), "through to its end")
T.check(frames[9] == frames[1] or frames[8] == frames[1], "and starts over")
glyph = 5  -- a narrower font: more fits, still right-aligned power
battle.moveIndex = 1
T.eq(overlay(battle):match("^(Z:[^@]*)"), "Z:NEVER-ENDING NIGHTMARE",
  "measured by font width, a narrower font fits the whole name")
glyph = 8

-- ------- party menu

local function submenu(mon, ctx)
  return Runtime.call("ui.party.submenu", function(_, items) return items end, game,
    { { label = "STATS", action = "stats" }, { label = "SWITCH", action = "switch" } }, mon, ctx or {})
end
game.save = { flags = {}, party = {}, player = { name = "RED" }, inventory = {} }
local pika = { species = "PIKACHU", moves = { { id = "THUNDERBOLT", pp = 15 }, { id = "THUNDER", pp = 10 } } }
local rows = submenu(pika)
T.eq(rows[1].label, "Z-CRYSTAL", "a Z-CRYSTAL row above STATS")
T.eq(rows[1].move, "softboiled", "sized like SOFTBOILED so the label fits the box")
T.eq(#rows, 3, "and the vanilla rows stay")
pika.zCrystal = "ELECTRIC"
T.eq(submenu(pika)[1].label, "Z:ELECTRIC", "it names the held crystal")
pika.zCrystal = "PIKANIUM"
T.eq(submenu(pika)[1].label, "Z:PIKANIUM", "exclusive crystals too")
T.eq(#submenu(pika, { battle = true }), 2, "the in-battle party menu is left strict")
pika.zCrystal = nil

rows = submenu(pika)
pushed = {}
rows[1].onSelect(pika, game)
local list = topPushed()
T.eq(list.title, "Z-CRYSTALS", "choosing it opens the crystal list")
T.eq(list.items[1].label, "PIKANIUM Z", "its own exclusive crystal first")
T.eq(list.items[2].label, "ELECTRIUM Z", "then the types it can use")
list.opts.onChoose(list.items[2], list)
T.eq(pika.zCrystal, "ELECTRIC", "picking one gives it")
T.eq(topPushed().text, "PIKACHU holds\nELECTRIUM Z!", "and says so")

-- ------- the record (counted for every Z-Move above, with ALL crystals)

local r = api.record()
T.check(r.used >= 10, "your Z-Moves are counted (" .. r.used .. ")")
T.check(r.faced >= 8, "so are the trainers' (" .. r.faced .. ")")
T.check((r.byKey.ELECTRIC or 0) >= 5, "per crystal")

-- ------- story mode

options.crystals = "story"
local overworld = { isOverworld = true, queued = {} }
function overworld:queueScript(rows_)
  for _, row in ipairs(rows_) do self.queued[#self.queued + 1] = table.concat(
    { tostring(row[1]), tostring(row[2]), row[4] and tostring(row[4]) or nil }, ":") end
end
local function walk()
  game.stack.states = { overworld }
  Runtime.emit("world.stepped", {})
  local q = overworld.queued
  overworld.queued = {}
  return table.concat(q, " ")
end
local function freshSave(flags, inventory)
  run.loader.modSave.z_moves = {}
  game.save = { flags = flags or {}, party = { pika }, player = { name = "RED" },
                inventory = inventory or {}, pcItems = {} }
  Runtime.emit("save.loaded", { save = game.save })
  return game.save
end

-- a Champion save meeting the mod for the first time
local champion = {}
for _, f in ipairs({ "EVENT_GOT_POKEDEX", "EVENT_BEAT_BROCK", "EVENT_BEAT_MISTY",
    "EVENT_BEAT_LT_SURGE", "EVENT_BEAT_ERIKA", "EVENT_BEAT_KOGA", "EVENT_BEAT_SABRINA",
    "EVENT_BEAT_BLAINE", "EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI", "EVENT_BEAT_LANCE" }) do
  champion[f] = true
end
local save = freshSave(champion)
T.eq(walk(), "give_item:Z_RING:_ZMovesRingToBagText",
  "a Champion save: the Z-RING goes in the PACK, no burst of crystal messages")
save.inventory.Z_RING = 1
T.eq(walk(), "", "once")
T.check(api.unlocked("DRAGON") and api.unlocked("ELECTRIC"), "every crystal it earned is there")
T.check(not api.unlocked("ICE"), "not the ones it did not")

-- a new game
save = freshSave({})
T.eq(walk(), "", "nothing before the POKeDEX")
battle = newBattle("ELECTRIC")
openMoves(battle) pressStart()
T.check(not api.state(battle).armed, "no Z-Ring, no Z-Power")
T.eq(overlay(battle), "Z:NO Z-RING YET@0,40", "and the bar says why")
T.eq(#submenu({ species = "FIXMON_A", moves = {} }), 2, "no Z-CRYSTAL row before the Z-Ring")
save.flags.EVENT_GOT_POKEDEX = true
T.eq(walk(), "give_item:Z_RING:_ZMovesGotZRingText text_sound:Get_Key_Item show_text:_ZMovesGotNORMALText",
  "the POKeDEX brings the Z-RING into the PACK and Normalium Z with its fanfare")
save.inventory.Z_RING = 1
T.eq(walk(), "", "once")
battle = newBattle("ELECTRIC")
openMoves(battle) pressStart()
T.check(not api.state(battle).armed, "a crystal not yet earned does nothing")
save.flags.EVENT_BEAT_LT_SURGE = true
T.eq(walk(), "text_sound:Get_Key_Item show_text:_ZMovesGotELECTRICText "
  .. "text_sound:Get_Key_Item show_text:_ZMovesGotPIKANIUMText",
  "Lt. Surge gives Electrium Z and Pikanium Z, each with the fanfare")
battle = newBattle("ELECTRIC")
openMoves(battle) pressStart()
T.check(api.state(battle).armed, "and Electrium Z now works")
save.flags.EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1 = true
walk()
save.flags.EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0 = true
T.eq(walk(), "", "Buginium Z is announced once")
save.flags.EVENT_BEAT_ERIKA = true
game.stack.states = { battle }
local saved = run.loader.modSave.z_moves
T.check(not saved.announced.EEVIUM, "not announced before a walk")
T.eq(walk(), "text_sound:Get_Key_Item show_text:_ZMovesGotGRASSText "
  .. "text_sound:Get_Key_Item show_text:_ZMovesGotEEVIUMText", "Erika's two show on the next walk")

-- a full PACK: the ring is announced, the item waits for room
local full = {}
for i = 1, 20 do
  data.items["FILL_" .. i] = { id = "FILL_" .. i, name = "FILL", price = 1 }
  full["FILL_" .. i] = 1
end
save = freshSave({}, full)
save.flags.EVENT_GOT_POKEDEX = true
T.eq(walk(), "text_sound:Get_Key_Item show_text:_ZMovesGotZRingText "
  .. "text_sound:Get_Key_Item show_text:_ZMovesGotNORMALText",
  "a full PACK: the Z-RING is still announced with its fanfare")
T.eq(walk(), "", "and nothing is forced into the PACK")
save.inventory.FILL_1 = nil
T.eq(walk(), "give_item:Z_RING:_ZMovesRingToBagText", "it is put in once there is room")

-- ALL mode still hands out the ring item
options.crystals = "all"
save = freshSave({})
T.eq(walk(), "give_item:Z_RING:_ZMovesRingToBagText", "ALL: the Z-RING goes in the PACK too")
options.crystals = "story"

-- ------- the Z-RING screen

save = freshSave({ EVENT_GOT_POKEDEX = true, EVENT_BEAT_LT_SURGE = true })
pika.zCrystal = "ELECTRIC"
pushed = {}
local claimedUse = Runtime.call("item.use", function() return "vanilla" end, game, nil, "Z_RING")
T.check(claimedUse ~= "vanilla", "USE on the Z-RING is the mod's")
local ring = topPushed()
T.eq(ring.title, "Z-RING", "it opens the Z-RING screen")
T.eq(ring.items[1].label .. "," .. ring.items[2].label .. "," .. ring.items[3].label,
  "CRYSTALS,PARTY,RECORD", "with crystals, party and record")
T.eq(Runtime.call("item.use", function() return "vanilla" end, game, nil, "FIX_POTION"),
  "vanilla", "other items are untouched")
ring.opts.onChoose(ring.items[1])
local coll = topPushed()
local shown = {}
for _, it in ipairs(coll.items) do shown[#shown + 1] = it.label .. (it.right and ("=" .. it.right) or "") end
T.check(table.concat(shown, ","):find("NORMALIUM Z,", 1, true), "earned crystals are listed")
T.check(table.concat(shown, ","):find("ELECTRIUM Z=HELD", 1, true), "with the ones held marked")
T.check(table.concat(shown, ","):find("-----------", 1, true), "unearned ones are blank")
local elec
for _, it in ipairs(coll.items) do if it.key == "ELECTRIC" then elec = it end end
coll.opts.onChoose(elec)
T.eq(topPushed().text, "Turns ELECTRIC\nmoves into\fGIGAVOLT\nHAVOC!", "a crystal explains itself")
local pik
for _, it in ipairs(coll.items) do if it.key == "PIKANIUM" then pik = it end end
coll.opts.onChoose(pik)
T.eq(topPushed().text, "Only for PIKACHU.\nTHUNDER becomes\fCATASTROPIKA!", "exclusives too")
ring.opts.onChoose(ring.items[2])
T.eq(topPushed().items[1].right, "ELECTRIUM", "PARTY lists what each Pokemon holds")
run.loader.modSave.z_moves.record = { used = 3, faced = 1, byKey = { NORMAL = 1, GHOST = 2 } }
ring.opts.onChoose(ring.items[3])
T.eq(topPushed().text, "Your Z-Moves: 3\nFoes' Z-Moves: 1\fMost used (x2):\nNEVER-ENDING\fNIGHTMARE",
  "RECORD: counts and the favourite, split where it would not fit")

-- ------- Gen1 Modern UI extension (data only)

local ext = api.gen1ModernUi.extensions.zMovesCrystals
T.check(ext.match(nil, "party") and ext.match(nil, "summary") and not ext.match(nil, "bag"),
  "it extends the party list and summary only")
local partyModel = ext.model(game, { party = { { species = "A" }, pika } }, "party")
T.eq(partyModel.rows[1], nil, "no badge without a crystal")
T.eq(partyModel.rows[2].badge.text, "Z", "a Z badge on a crystal holder")
local page = ext.model(game, { mon = pika }, "summary").pages[1]
T.eq(page.title .. ":" .. page.rows[1].value .. ":" .. page.rows[2].value,
  "Z-CRYSTAL:ELECTRIUM Z:GIGAVOLT HAVOC", "a Z-CRYSTAL summary page")
local function noFunctions(v)
  if type(v) == "function" then return false end
  if type(v) == "table" then for _, x in pairs(v) do if not noFunctions(x) then return false end end end
  return true
end
T.check(noFunctions(partyModel) and noFunctions(page), "its models carry no functions, as Modern UI requires")

-- ------- the mod turned off: the save survives, and comes back whole

local SaveData = require("src.core.SaveData")
local vanilla = T.fixtures.fresh()
local monOff = { species = "FIXMON_A", level = 20, hp = 30, zCrystal = "ELECTRIC",
  moves = { { id = "FIX_TACKLE", pp = 30 } } }
local offSave = { version = "red", party = { monOff }, boxes = {}, flags = {},
  inventory = { Z_RING = 1, FIX_POTION = 2 }, player = { name = "RED" },
  modData = { z_moves = { announced = { RING = true } } } }
SaveData.validate(offSave, vanilla)
T.eq(offSave.inventory.Z_RING, nil, "without the mod the Z-RING is set aside")
T.eq(offSave.orphaned.items[1].id, "Z_RING", "into the engine's quarantine, not deleted")
T.eq(offSave.inventory.FIX_POTION, 2, "everything else stays")
T.eq(monOff.zCrystal, "ELECTRIC", "the held crystal is a plain field and stays")
T.eq(monOff.moves[1].id, "FIX_TACKLE", "the moves stay")
T.eq(offSave.modData.z_moves.announced.RING, true, "the mod's own save data stays")
SaveData.validate(offSave, data)
T.eq(offSave.inventory.Z_RING, 1, "with the mod back the Z-RING returns to the PACK")

run.release()
T.finish("z_moves")
