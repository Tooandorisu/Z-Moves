-- Run from a Gen1Recomp source checkout with this mod at mods/z_moves:
--   luajit mods/z_moves/tests/z_moves_test.lua
-- ROM-free: loads the mod through the real loader and sandbox against the
-- fixture dataset, then walks the same event/hook sequence BattleState
-- raises for a turn, with the engine's own Damage.compute as vanilla.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Damage = require("src.battle.Damage")

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
T.check(type(api) == "table" and type(api.zPower) == "function", "exports are published")

-- ------- content

local z = data.moves.ZMOVE_ELECTRIC
T.check(z ~= nil, "the Electric Z-Move is registered")
T.eq(z.name, "GIGAVOLT\nHAVOC", "it carries its two-line battle name")
T.eq(z.effect, "NO_ADDITIONAL_EFFECT", "no secondary effect")
T.eq(z.type, "ELECTRIC", "it has the type of the move it borrows from")
T.eq(data.moves.ZMOVE_PSYCHIC.type, "PSYCHIC_TYPE", "pokered's PSYCHIC_TYPE id is kept")
T.check(data.moves.ZMOVE_FLYING == nil, "no record for a type whose sample move is missing")
T.eq(data.moves.THUNDERBOLT.power, 95, "vanilla Thunderbolt is untouched")

-- ------- the Sun/Moon power table

T.eq(api.zPower(data.moves.THUNDERBOLT), 175, "95 -> 175")
T.eq(api.zPower(data.moves.QUICK_ATTACK), 100, "40 -> 100")
T.eq(api.zPower(data.moves.THUNDER), 190, "120 -> 190")
T.eq(api.zPower(data.moves.HYPER_BEAM), 200, "150 -> 200")
T.eq(api.zPower(data.moves.FISSURE), 180, "OHKO moves -> 180")
T.eq(api.zPower(data.moves.NIGHT_SHADE), 100, "fixed-damage moves -> 100")
T.eq(api.zPower(data.moves.THUNDER_WAVE), nil, "status moves have no damaging Z-Move")
T.eq(api.zStatus(data.moves.THUNDER_WAVE)[1], "special", "they have a status Z-effect instead")
T.eq(api.zStatus(data.moves.THUNDERBOLT), nil, "damaging moves have none")

-- ------- a battle, shaped like src/battle/BattleState.lua

local ruleset = require("src.battle.rulesets.gen1_faithful")
local function stats() return { hp = 120, attack = 80, defense = 80, speed = 80, special = 80 } end
local function battler(isPlayer, types, moves)
  local mon = { species = "FIXMON_A", level = 50, hp = 120, stats = stats(), moves = moves }
  return { isPlayer = isPlayer, name = isPlayer and "PIKACHU" or "ONIX", mon = mon,
    curStats = mon.stats, curTypes = types, curMoves = mon.moves, stages = {},
    def = { baseStats = { speed = 1 } } }
end

local pressed = {}
local game = { data = data, stack = { states = {} },
  input = { wasPressed = function(_, b) return pressed[b] or false end } }
run.loader.game = game
-- the battle checks below use every crystal; story mode is tested at the end
run.loader.modOptions.z_moves = { crystals = "all" }

local function newBattle(crystal)
  local moves = { { id = "THUNDERBOLT", pp = 15 }, { id = "QUICK_ATTACK", pp = 30 },
                  { id = "THUNDER_WAVE", pp = 20 } }
  local battle = { isBattleState = true, kind = "trainer", phase = "menu", data = data,
    ruleset = ruleset, queue = {}, moveIndex = 1, turnCount = 0, game = game,
    player = battler(true, { "ELECTRIC" }, moves),
    enemy = battler(false, { "WATER" }, { { id = "QUICK_ATTACK", pp = 30 } }) }
  battle.player.mon.zCrystal = crystal
  function battle:sayAuto(text) self.queue[#self.queue + 1] = { text = text } end
  game.stack.states = { battle }
  Runtime.emit("battle.started", { battle = battle, kind = "trainer" })
  return battle
end

local function step(button)
  pressed = button and { [button] = true } or {}
  Runtime.call("input.step", function() end, game, 1 / 60)
  pressed = {}
end
-- START is read on the fixed step after the press
local function pressStart() step("start") step() end

-- BattleState:performMove, reduced to what a NO_ADDITIONAL_EFFECT hit does
local function performMove(battle, user, target, inst, hits)
  local move = data.moves[inst.id]
  inst.pp = inst.pp - 1
  local out = { announced = user.name .. "\nused " .. move.name .. "!" }
  battle.moveAnimRow = { anim = move.id, attackerIsPlayer = user.isPlayer }
  Runtime.emit("battle.move_used", { battle = battle, user = user, target = target,
    move = move, isCalled = false })
  out.anim = battle.moveAnimRow.anim
  user.lastMove = move.id
  out.hit = Runtime.call("battle.accuracy", function() return hits ~= false end,
    { battle = battle, ruleset = ruleset, move = move, user = user, target = target })
  if out.hit then
    out.damage, out.info = Runtime.call("battle.damage", function(c)
      return Damage.compute(c.ruleset, c.user, c.target, c.move, c.opts)
    end, { battle = battle, ruleset = ruleset, user = user, target = target, move = move,
           opts = { forceCrit = false, rng = function(_, hi) return hi end } })
  end
  return out
end

-- BattleState:chooseMove -> resolveTurn -> the player's action -> endOfTurn
local function chooseMove(battle, slot, opts)
  opts = opts or {}
  battle.moveIndex = slot
  local inst = battle.player.curMoves[slot]
  battle.turnCount = battle.turnCount + 1
  Runtime.emit("battle.turn_started", { battle = battle, turn = battle.turnCount,
    playerAction = inst, enemyAction = battle.enemy.curMoves[1] })
  battle.phase = "messages"
  local out = { idDuringTurn = inst.id }
  if not opts.asleep then
    out = performMove(battle, battle.player, battle.enemy, inst, opts.hits)
    out.idDuringTurn = nil
  end
  out.idAfterMove = inst.id
  Runtime.emit("battle.turn_ended", { battle = battle, turn = battle.turnCount })
  battle.phase = "menu"
  return out
end

local function openMoves(battle) battle.phase = "moveSelect" end

-- ------- an ordinary turn is vanilla

local battle = newBattle("ELECTRIC")
openMoves(battle)
local plain = chooseMove(battle, 1)
T.eq(plain.announced, "PIKACHU\nused THUNDERBOLT!", "without Z-Power the move is itself")
T.eq(#battle.queue, 0, "and nothing is said")
local plainDamage = plain.damage

-- ------- the Z-Move turn

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
T.check(api.state(battle).armed, "START in the move list arms Z-Power")
pressStart()
T.check(not api.state(battle).armed, "START again disarms it")
pressStart()
local zTurn = chooseMove(battle, 1, { hits = false })
T.eq(battle.queue[1] and battle.queue[1].text, "PIKACHU\nunleashes its\nfull-force Z-Move!",
  "the Z-Power line is queued ahead of the turn")
T.eq(zTurn.announced, "PIKACHU\nused GIGAVOLT\nHAVOC!", "the engine announces the Z-Move")
T.eq(zTurn.anim, "ZMOVE_ELECTRIC", "Gigavolt Havoc plays its own animation")
local seq = data.battle_anims.moveAnims.ZMOVE_ELECTRIC.seq
local effects = {}
for _, row in ipairs(seq) do effects[#effects + 1] = row.effect or ("sub" .. row.subanim) end
T.eq(table.concat(effects, " "), "SE_DARK_SCREEN_PALETTE SE_SPIRAL_BALLS_INWARD SE_DARK_SCREEN_FLASH"
  .. " sub93 sub95 SE_DARK_SCREEN_FLASH SE_DARK_SCREEN_FLASH SE_SHAKE_SCREEN SE_RESET_SCREEN_PALETTE",
  "charge-up, Thunderbolt, Thunder, then the finish, dark all the way")
T.eq(data.battle_anims.moveAnims.THUNDER.seq[3].effect, "SE_RESET_SCREEN_PALETTE",
  "Thunder's own animation is untouched")
T.check(data.battle_anims.moveAnims.ZMOVE_WATER == nil, "a type with no source animations keeps borrowing")
T.eq(zTurn.hit, true, "a Z-Move bypasses a failed accuracy roll")
T.eq(zTurn.idAfterMove, "THUNDERBOLT", "the slot is the real move again")
T.eq(battle.player.curMoves[1].pp, 14, "PP came off the real move")
T.eq(battle.player.lastMove, "THUNDERBOLT", "lastMove names the real move")
T.eq(data.moves.ZMOVE_ELECTRIC.power, 100, "the registry record was not written")
T.eq(data.moves.THUNDERBOLT.power, 95, "nor was Thunderbolt")

-- the engine's own formula, at 175 power with STAB and the same roll
local expect = Damage.compute(ruleset, battle.player, battle.enemy,
  { id = "X", type = "ELECTRIC", power = 175, accuracy = 100 },
  { forceCrit = false, rng = function(_, hi) return hi end })
T.eq(zTurn.damage, expect, "damage is the vanilla formula at Z power")
T.check(zTurn.damage > plainDamage, "and it out-hits plain Thunderbolt")
T.check(api.state(battle).used, "Z-Power is spent")

-- ------- the option brings the borrowed animation back

run.loader.modOptions.z_moves.animations = false
battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
T.eq(chooseMove(battle, 1).anim, "THUNDER", "with Z-MOVE ANIMATIONS off, Thunder's plays")
run.loader.modOptions.z_moves.animations = nil
battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
chooseMove(battle, 1)

-- ------- once per battle

openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "it cannot be armed twice in a battle")
local after = chooseMove(battle, 1)
T.eq(after.announced, "PIKACHU\nused THUNDERBOLT!", "the next turn is ordinary")
T.eq(after.damage, plainDamage, "at ordinary damage")

-- ------- wrong type / status move / no crystal

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
local off = chooseMove(battle, 2)
T.eq(off.announced, "PIKACHU\nused QUICK ATTACK!", "a move of another type stays itself")
T.check(not api.state(battle).used, "and does not spend Z-Power")

-- ------- status Z-Moves: the move runs as itself, with its bonus first

battle.player.stages.special = -2
function battle:sayNext(text) self.queue[#self.queue + 1] = { text = text } end
openMoves(battle)
pressStart()
local status = chooseMove(battle, 3)
T.eq(status.announced, "PIKACHU\nused THUNDER WAVE!", "a status Z-Move keeps its own name")
T.eq(battle.queue[1].text, "PIKACHU\nsurrounded itself\nwith its Z-Power!", "Z-Power is announced")
T.eq(battle.queue[2].text, "PIKACHU\nboosted SPECIAL\nwith its Z-Power!", "and the bonus is said")
T.eq(battle.player.stages.special, -1, "Z-Thunder Wave raises SPECIAL one stage")
T.eq(battle.player.curMoves[3].id, "THUNDER_WAVE", "the slot was never repointed")
T.check(api.state(battle).used, "it spends Z-Power")

battle = newBattle("NORMAL")
battle.player.curMoves[3] = { id = "SPLASH", pp = 40 }
battle.player.curMoves[4] = { id = "RECOVER", pp = 20 }
battle.player.stages = { attack = 5, defense = -3, speed = 2 }
function battle:sayNext() end
openMoves(battle)
pressStart()
chooseMove(battle, 3)
T.eq(battle.player.stages.attack, 6, "Z-Splash is +3 Attack, capped at +6")

battle = newBattle("NORMAL")
battle.player.curMoves[4] = { id = "RECOVER", pp = 20 }
battle.player.stages = { attack = 2, defense = -3, evasion = -1 }
function battle:sayNext() end
openMoves(battle)
pressStart()
chooseMove(battle, 4)
T.eq(battle.player.stages.defense, 0, "a reset lifts lowered stats")
T.eq(battle.player.stages.evasion, 0, "all of them")
T.eq(battle.player.stages.attack, 2, "and keeps raised ones")

battle = newBattle("ICE")
battle.player.curMoves[4] = { id = "HAZE", pp = 30 }
battle.player.mon.hp = 7
local drained = false
function battle:sayNext() end
function battle:drainNext() drained = true end
openMoves(battle)
pressStart()
chooseMove(battle, 4)
T.eq(battle.player.mon.hp, 120, "Z-Haze restores all HP")
T.check(drained, "and asks the engine to move the HP bar")

battle = newBattle(nil)
openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "no crystal, no Z-Power")

-- ------- species-exclusive Z-Moves

T.check(data.moves.ZMOVE_PIKANIUM ~= nil, "Catastropika is registered")
T.check(data.moves.ZMOVE_MEWNIUM ~= nil, "Genesis Supernova is registered")
T.eq(data.moves.ZMOVE_EEVIUM.effect, "ATTACK_UP2_EFFECT", "Extreme Evoboost carries a stat effect")
T.check(data.moves.ZMOVE_SNORLIUM == nil, "an exclusive move without its animation move is skipped")

battle = newBattle("PIKANIUM")
battle.player.mon.species = "PIKACHU"
battle.player.curMoves[2] = { id = "THUNDER", pp = 10 }
openMoves(battle)
pressStart()
local own = chooseMove(battle, 2)
T.eq(own.announced, "PIKACHU\nused CATASTROPIKA!", "Pikachu's Thunder becomes Catastropika")
local expect210 = Damage.compute(ruleset, battle.player, battle.enemy,
  { id = "X", type = "ELECTRIC", power = 210, accuracy = 100 },
  { forceCrit = false, rng = function(_, hi) return hi end })
T.eq(own.damage, expect210, "at 210 power")
T.eq(battle.player.curMoves[2].id, "THUNDER", "and the slot is Thunder again")

battle = newBattle("PIKANIUM")
battle.player.mon.species = "PIKACHU"
openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "Pikanium Z does not power ordinary Electric moves")

battle = newBattle("PIKANIUM")
battle.player.mon.species = "RAICHU"
battle.player.curMoves[2] = { id = "THUNDER", pp = 10 }
openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "another species cannot use it")

battle = newBattle("EEVIUM")
battle.player.mon.species = "EEVEE"
battle.player.curMoves[2] = { id = "TAKE_DOWN", pp = 20 }
battle.player.stages = { speed = 5 }
function battle:sayNext(text) self.queue[#self.queue + 1] = { text = text } end
openMoves(battle)
pressStart()
local evo = chooseMove(battle, 2)
T.eq(evo.announced, "PIKACHU\nused EXTREME\nEVOBOOST!", "Eevee's Take Down becomes Extreme Evoboost")
T.eq(battle.player.stages.defense, 2, "Defense +2")
T.eq(battle.player.stages.special, 2, "Special +2")
T.eq(battle.player.stages.speed, 6, "Speed capped at +6")
T.eq(battle.player.stages.attack, nil, "Attack is left to the engine's own effect")

-- ------- prevented from moving: spent, and the slot still comes back

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
local slept = chooseMove(battle, 1, { asleep = true })
T.eq(slept.idDuringTurn, "ZMOVE_ELECTRIC", "the slot points at the Z-Move during the turn")
T.eq(slept.idAfterMove, "ZMOVE_ELECTRIC", "until the turn ends")
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "then it is restored")
T.eq(battle.player.curMoves[1].pp, 15, "no PP was spent")
T.check(api.state(battle).used, "Z-Power is spent all the same")

-- ------- a save taken mid-turn never carries the Z-Move id

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
Runtime.emit("battle.turn_started", { battle = battle, turn = 1,
  playerAction = battle.player.curMoves[1] })
T.eq(battle.player.curMoves[1].id, "ZMOVE_ELECTRIC", "mid-turn the slot is borrowed")
Runtime.emit("save.writing", {})
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "save.writing hands it back first")

-- ------- locked turns and other battle kinds

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
battle.phase = "menu"  -- a locked action resolves from the command menu
Runtime.emit("battle.turn_started", { battle = battle, turn = 1,
  playerAction = battle.player.curMoves[1] })
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "a turn not chosen in the move list is left alone")

battle = newBattle("ELECTRIC")
battle.kind = "link"
openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "link battles are untouched")

-- ------- the command menu's START hook

battle = newBattle("ELECTRIC")
local claimed = Runtime.call("battle.menu_auxiliary", function() return false end,
  game, { kind = "trainer" })
T.eq(claimed, true, "START on the command menu is claimed for a crystal holder")
T.check(api.state(battle).armed, "and arms Z-Power")
battle = newBattle(nil)
claimed = Runtime.call("battle.menu_auxiliary", function() return false end,
  game, { kind = "trainer" })
T.eq(claimed, false, "without a crystal the hook passes through")

-- ------- the party submenu row

local mon = { species = "FIXMON_A", moves = { { id = "THUNDERBOLT", pp = 15 } } }
local vanillaRows = { { label = "STATS", action = "stats" }, { label = "SWITCH", action = "switch" } }
local rows = Runtime.call("ui.party.submenu", function(_, items) return items end,
  game, vanillaRows, mon, { battle = nil })
T.eq(rows[1].label, "Z-CRYSTAL", "the field party menu gets a Z-CRYSTAL row above STATS")
T.eq(#rows, 3, "and keeps the vanilla rows")
local battleRows = Runtime.call("ui.party.submenu", function(_, items) return items end,
  game, { { label = "STATS", action = "stats" } }, mon, { battle = battle })
T.eq(#battleRows, 1, "the in-battle party menu is left strict")

-- ------- trainers with Z-Power

local function leaderBattle(oppClass, aceMoves, opts)
  opts = opts or {}
  local b = newBattle(nil)
  b.oppClass = oppClass
  local first = battler(false, { "ROCK" }, { { id = "QUICK_ATTACK", pp = 30 } })
  local ace = battler(false, { "WATER" }, aceMoves)
  b.enemyParty = { first.mon, ace.mon }
  b.enemy = opts.first and first or ace
  b.enemy.name = "STARMIE"
  function b:lockedAction() return opts.locked end
  function b:romLine(id) return id == "EnemyText" and "Enemy " or "" end
  return b
end

-- BattleState:resolveTurn with the enemy moving, as far as Z-Power cares
local function enemyTurn(b, vanillaSlot)
  b.queue = {}
  local action = Runtime.call("battle.enemy_action", function(bb)
    return bb.enemy.curMoves[vanillaSlot or 1]
  end, b)
  b.turnCount = b.turnCount + 1
  Runtime.emit("battle.turn_started", { battle = b, turn = b.turnCount,
    playerAction = b.player.curMoves[2], enemyAction = action })
  local out = performMove(b, b.enemy, b.player, action, false)
  out.slotAfter = action.id
  Runtime.emit("battle.turn_ended", { battle = b, turn = b.turnCount })
  return out, action
end

battle = leaderBattle("OPP_MISTY", { { id = "QUICK_ATTACK", pp = 30 },
  { id = "HYDRO_PUMP", pp = 5 }, { id = "THUNDERBOLT", pp = 15 } })
local zt, chosen = enemyTurn(battle, 1)
T.eq(chosen.id, "HYDRO_PUMP", "Misty's ace switches to its Water move for the Z-Move")
T.eq(zt.announced, "STARMIE\nused HYDRO\nVORTEX!", "and uses Hydro Vortex")
T.eq(battle.queue[1] and battle.queue[1].text, "Enemy STARMIE\nunleashes its\nfull-force Z-Move!",
  "announced as the enemy's")
T.eq(zt.hit, true, "it cannot miss")
local hydroZ = Damage.compute(ruleset, battle.enemy, battle.player,
  { id = "X", type = "WATER", power = 190, accuracy = 100 },
  { forceCrit = false, rng = function(_, hi) return hi end })
T.eq(zt.damage, hydroZ, "at 190 power")
T.eq(zt.slotAfter, "HYDRO_PUMP", "the slot is Hydro Pump again")
T.eq(battle.enemy.lastMove, "HYDRO_PUMP", "Mirror Move would copy Hydro Pump")
T.check(api.state(battle).foeUsed, "the trainer's Z-Power is spent")

local again = enemyTurn(battle, 1)
T.eq(again.announced, "STARMIE\nused QUICK ATTACK!", "once per battle")

battle = leaderBattle("OPP_MISTY", { { id = "QUICK_ATTACK", pp = 30 } }, { first = true })
local early = enemyTurn(battle, 1)
T.eq(early.announced, "STARMIE\nused QUICK ATTACK!", "only the last Pokemon holds the crystal")

battle = leaderBattle("OPP_MISTY", { { id = "QUICK_ATTACK", pp = 30 },
  { id = "THUNDERBOLT", pp = 15 } })
local off = enemyTurn(battle, 1)
T.eq(off.announced, "STARMIE\nused GIGAVOLT\nHAVOC!", "without a move of its type, the strongest type it has")

battle = leaderBattle("OPP_YOUNGSTER", { { id = "HYDRO_PUMP", pp = 5 } })
T.eq(enemyTurn(battle, 1).announced, "STARMIE\nused HYDRO PUMP!", "ordinary trainers have no Z-Power")

battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } }, { locked = { id = "HYDRO_PUMP" } })
T.eq(enemyTurn(battle, 1).announced, "STARMIE\nused HYDRO PUMP!", "a locked turn is left alone")

run.loader.modOptions.z_moves.trainers = false
battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
T.eq(enemyTurn(battle, 1).announced, "STARMIE\nused HYDRO PUMP!", "the option turns it off")
run.loader.modOptions.z_moves.trainers = nil

-- both sides in one battle
battle = leaderBattle("OPP_MISTY", { { id = "HYDRO_PUMP", pp = 5 } })
battle.player.mon.zCrystal = "ELECTRIC"
openMoves(battle)
pressStart()
local action = Runtime.call("battle.enemy_action", function(bb) return bb.enemy.curMoves[1] end, battle)
battle.turnCount = battle.turnCount + 1
Runtime.emit("battle.turn_started", { battle = battle, turn = battle.turnCount,
  playerAction = battle.player.curMoves[1], enemyAction = action })
local mine = performMove(battle, battle.player, battle.enemy, battle.player.curMoves[1])
local theirs = performMove(battle, battle.enemy, battle.player, action)
T.eq(mine.announced, "PIKACHU\nused GIGAVOLT\nHAVOC!", "the player's Z-Move")
T.eq(theirs.announced, "STARMIE\nused HYDRO\nVORTEX!", "and the trainer's in the same turn")
T.eq(mine.damage, Damage.compute(ruleset, battle.player, battle.enemy,
  { id = "X", type = "ELECTRIC", power = 175, accuracy = 100 },
  { forceCrit = false, rng = function(_, hi) return hi end }), "each at its own power")
Runtime.emit("battle.turn_ended", { battle = battle, turn = battle.turnCount })
T.eq(battle.player.curMoves[1].id, "THUNDERBOLT", "both slots come back")
T.eq(battle.enemy.curMoves[1].id, "HYDRO_PUMP", "both slots come back")

-- ------- story mode: crystals are earned

run.loader.modOptions.z_moves = { crystals = "story" }
-- the mod hands its messages to the overworld's script queue
local overworld = { isOverworld = true, queued = {} }
function overworld:queueScript(rows)
  for _, row in ipairs(rows) do self.queued[#self.queued + 1] = row[2] end
end
local function step()
  game.stack.states = { overworld }  -- the map is on top whenever the player walks
  Runtime.emit("world.stepped", {})
end
local function shown() local q = overworld.queued; overworld.queued = {}; return table.concat(q, " ") end
T.check(data.text._ZMovesGotELECTRICText == "{PLAYER} got\nELECTRIUM Z!", "the message is registered text")

-- a save already past Misty when it first meets the mod: no burst of messages
game.save = { flags = { EVENT_GOT_POKEDEX = true, EVENT_BEAT_BROCK = true,
  EVENT_BEAT_MISTY = true }, player = { name = "RED" } }
Runtime.emit("save.loaded", { save = game.save })
step()
T.eq(shown(), "", "crystals earned before the mod was installed arrive silently")
T.check(api.unlocked("WATER"), "but they are there")

-- a fresh run
run.loader.modSave.z_moves = {}
game.save = { flags = {}, player = { name = "RED" } }
step()

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "no Z-Ring, no Z-Power")
rows = Runtime.call("ui.party.submenu", function(_, items) return items end,
  game, { { label = "STATS" } }, { species = "FIXMON_A", moves = {} }, {})
T.eq(#rows, 1, "no Z-CRYSTAL row before the Z-Ring")

game.save.flags.EVENT_GOT_POKEDEX = true
step()
T.eq(shown(), "_ZMovesGotZRingText _ZMovesGotNORMALText",
  "the POKeDEX brings the Z-Ring and Normalium Z")
step()
T.eq(shown(), "", "once")
T.check(not api.unlocked("ELECTRIC"), "Electrium Z is not earned yet")

battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
T.check(not api.state(battle).armed, "a crystal not yet earned does nothing")

game.save.flags.EVENT_BEAT_LT_SURGE = true
step()
T.eq(shown(), "_ZMovesGotELECTRICText _ZMovesGotPIKANIUMText",
  "Lt. Surge gives Electrium Z and Pikanium Z")
battle = newBattle("ELECTRIC")
openMoves(battle)
pressStart()
T.check(api.state(battle).armed, "and Electrium Z now works")

game.save.flags.EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1 = true
step()
game.save.flags.EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0 = true
step()
T.eq(shown(), "_ZMovesGotBUGText", "Buginium Z is announced once")

-- Lance, then straight into the Champion, Hall of Fame and a reset: the
-- message is still owed on the next walk
game.save.flags.EVENT_BEAT_LANCE = true
local kept = run.loader.modSave.z_moves.announced
T.check(not kept.DRAGON, "not shown before a step")

-- no map to queue on: nothing is lost
game.save.flags.EVENT_BEAT_ERIKA = true
game.stack.states = { battle }
Runtime.emit("world.stepped", {})
T.check(not run.loader.modSave.z_moves.announced.EEVIUM, "Erika's Eevium Z stays owed without a map")
step()
T.eq(shown(), "_ZMovesGotEEVIUMText", "and shows on the next walk")

run.release()
T.finish("z_moves")
