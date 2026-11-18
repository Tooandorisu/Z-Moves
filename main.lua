-- Z-Moves for Gen1Recomp (Red / Blue / Yellow).
--
-- A standalone mod: everything here goes through the public mod API
-- (content registry, events, hooks, mod.ui).  No engine file is patched,
-- replaced or rebuilt.
--
-- How a Z-Move happens:
--   1. A Pokemon holds a Z-Crystal (party menu -> Z-CRYSTAL).  The crystal
--      is a data-only field on the saved Pokemon, so it travels with it.
--   2. In the move list, START toggles Z-Power.
--   3. Picking a damaging move of the crystal's type while Z-Power is on
--      turns that move into the type's Z-Move for this one turn: the move
--      slot's id is pointed at a registered Z-Move record when the turn
--      starts and pointed back the moment the move executes.  A status
--      move of that type keeps running as itself and gets its Sun/Moon
--      bonus (a stat boost, a stat reset or a full heal) first.
--   4. battle.damage gives the Z-Move the power the Sun/Moon table assigns
--      to the base move, battle.accuracy makes it bypass the accuracy roll.
--   5. One Z-Move per battle and side, spent only when it actually fires
--      (sleep, paralysis or a flinch leave it for later, as in Sun/Moon).
--      The spent mark is a data-only side token, so a battle checkpoint
--      keeps it.
--
-- Gold, Silver and Crystal run gen2.lua instead (same rules, Gen 2's battle
-- and screens); everything below this dispatch is the Red/Blue/Yellow half.

return function(mod)
  if mod.generation == 2 then
    local source = assert(mod:read("gen2.lua"), "z_moves: gen2.lua is missing")
    local chunk = assert(load(source, "@gen2.lua"))
    return chunk()(mod)
  end

  local FIELD = "zCrystal"       -- field on the saved Pokemon
  local PREFIX = "ZMOVE_"        -- registered move ids: ZMOVE_<TYPE>

  -- key: type id without pokered's "_TYPE" suffix (PSYCHIC_TYPE -> PSYCHIC)
  -- anim: the vanilla move whose animation and sound the Z-Move borrows
  local TYPES = {
    { key = "NORMAL",   crystal = "NORMALIUM Z",  name = { "BREAKNECK", "BLITZ" },        anim = "HYPER_BEAM" },
    { key = "FIRE",     crystal = "FIRIUM Z",     name = { "INFERNO", "OVERDRIVE" },      anim = "FIRE_BLAST" },
    { key = "WATER",    crystal = "WATERIUM Z",   name = { "HYDRO", "VORTEX" },           anim = "HYDRO_PUMP" },
    { key = "ELECTRIC", crystal = "ELECTRIUM Z",  name = { "GIGAVOLT", "HAVOC" },         anim = "THUNDER" },
    { key = "GRASS",    crystal = "GRASSIUM Z",   name = { "BLOOM", "DOOM" },             anim = "SOLARBEAM" },
    { key = "ICE",      crystal = "ICIUM Z",      name = { "SUBZERO", "SLAMMER" },        anim = "BLIZZARD" },
    { key = "FIGHTING", crystal = "FIGHTINIUM Z", name = { "ALL-OUT", "PUMMELING" },      anim = "HI_JUMP_KICK" },
    { key = "POISON",   crystal = "POISONIUM Z",  name = { "ACID", "DOWNPOUR" },          anim = "SLUDGE" },
    { key = "GROUND",   crystal = "GROUNDIUM Z",  name = { "TECTONIC", "RAGE" },          anim = "EARTHQUAKE" },
    { key = "FLYING",   crystal = "FLYINIUM Z",   name = { "SUPERSONIC", "SKYSTRIKE" },   anim = "SKY_ATTACK" },
    { key = "PSYCHIC",  crystal = "PSYCHIUM Z",   name = { "SHATTERED", "PSYCHE" },       anim = "PSYCHIC_M" },
    { key = "BUG",      crystal = "BUGINIUM Z",   name = { "SAVAGE", "SPIN-OUT" },        anim = "PIN_MISSILE" },
    { key = "ROCK",     crystal = "ROCKIUM Z",    name = { "CONTINENTAL", "CRUSH" },      anim = "ROCK_SLIDE" },
    { key = "GHOST",    crystal = "GHOSTIUM Z",   name = { "NEVER-ENDING", "NIGHTMARE" }, anim = "NIGHT_SHADE" },
    { key = "DRAGON",   crystal = "DRAGONIUM Z",  name = { "DEVASTATING", "DRAKE" },      anim = "DRAGON_RAGE" },
  }

  local function typeKey(typeId)
    return (tostring(typeId or ""):gsub("_TYPE$", ""))
  end

  -- ------- battle and field text
  -- Registered game text, so a translation mod can override every line the
  -- mod prints.  The mod fills its own slots ({USER}, {STAT}, {TRAINER},
  -- {MON}), never the engine's ROM-text formatter, so a translation with a
  -- different slot set shows the slot name instead of stopping the game.

  local TEXT = {
    _ZMovesUnleashText = "{USER}\nunleashes its\nfull-force Z-Move!",
    _ZMovesAuraText = "{USER}\nsurrounded itself\nwith its Z-Power!",
    _ZMovesBoostText = "{USER}\nboosted {STAT}\nwith its Z-Power!",
    _ZMovesBoostAllText = "{USER}\nboosted its stats\nwith its Z-Power!",
    _ZMovesResetText = "{USER}\nreset its stats\nwith its Z-Power!",
    _ZMovesHealText = "{USER}\nrestored its HP\nwith its Z-Power!",
    _ZMovesWarningText = "{TRAINER} wears\na Z-RING!",
  }
  pcall(function()
    for id, text in pairs(TEXT) do mod.content.text:register(id, text) end
  end)

  local function line(data, id, slots)
    local text = data and data.text and data.text[id]
    if type(text) ~= "string" then text = TEXT[id] or id end
    return (text:gsub("{(%u+)}", function(slot)
      local value = slots and slots[slot]
      if value ~= nil then return tostring(value) end
    end))
  end

  -- "Enemy STARMIE" / "PIKACHU", the way the battle names each side
  local function actorName(battle, battler)
    local name = tostring(battler and battler.name or "")
    if battler and battler == battle.enemy then
      local ok, prefix = pcall(function() return battle:romLine("EnemyText") end)
      if ok and type(prefix) == "string" then return prefix .. name end
    end
    return name
  end

  -- a line the battle box shows just before "X used Y!", which the engine
  -- has already queued with its animation when battle.move_used fires
  local function sayBeforeUse(battle, text)
    local queue, row = battle.queue, battle.moveAnimRow
    local at
    for i = 1, #(queue or {}) do
      if queue[i] == row then at = i - 1 break end
    end
    if not at or at < 1 then
      battle:sayNextAuto(text, 40)
      return
    end
    table.insert(queue, at, { text = text, auto = true, autoDelay = 40 })
    battle.nextInsert = (battle.nextInsert or 0) + 1
  end

  -- ------- Z-Move power (Sun/Moon table, read off the base move)

  local BRACKETS = {
    { 55, 100 }, { 65, 120 }, { 75, 140 }, { 85, 160 }, { 95, 175 },
    { 100, 180 }, { 110, 185 }, { 125, 190 }, { 130, 195 },
  }
  -- moves whose printed power is not what they hit with
  local EFFECT_POWER = {
    OHKO_EFFECT = 180,            -- Fissure, Guillotine, Horn Drill
    SPECIAL_DAMAGE_EFFECT = 100,  -- Seismic Toss, Night Shade, Sonicboom...
    SUPER_FANG_EFFECT = 100,
    BIDE_EFFECT = 100,
  }
  local ID_POWER = { COUNTER = 100, MEGA_DRAIN = 120 }

  -- nil for status moves: they have no damaging Z-Move
  local function zPower(def)
    if type(def) ~= "table" or def.category == "status" then return nil end
    local fixed = ID_POWER[def.id] or EFFECT_POWER[def.effect]
    if fixed then return fixed end
    local power = tonumber(def.power) or 0
    if power <= 0 then return nil end
    for _, row in ipairs(BRACKETS) do
      if power <= row[1] then return row[2] end
    end
    return 200
  end

  -- ------- status Z-Moves: the bonus Sun/Moon gives before the move runs
  -- { stat, stages }, "reset" (lowered stats back to 0), "heal" (full HP)
  -- or "all" (every battle stat +1).  Sp. Atk and Sp. Def are SPECIAL here.

  local Z_STATUS = {
    SWORDS_DANCE = "reset", WHIRLWIND = { "special", 1 },
    SAND_ATTACK = { "evasion", 1 }, TAIL_WHIP = { "attack", 1 },
    LEER = { "attack", 1 }, GROWL = { "defense", 1 }, ROAR = { "defense", 1 },
    SING = { "speed", 1 }, SUPERSONIC = { "speed", 1 }, DISABLE = "reset",
    MIST = "heal", LEECH_SEED = "reset", GROWTH = { "special", 1 },
    POISONPOWDER = { "defense", 1 }, STUN_SPORE = { "special", 1 },
    SLEEP_POWDER = { "speed", 1 }, STRING_SHOT = { "speed", 1 },
    THUNDER_WAVE = { "special", 1 }, TOXIC = { "defense", 1 },
    HYPNOSIS = { "speed", 1 }, MEDITATE = { "attack", 1 }, AGILITY = "reset",
    TELEPORT = "heal", MIMIC = { "accuracy", 1 }, SCREECH = { "attack", 1 },
    DOUBLE_TEAM = "reset", RECOVER = "reset", HARDEN = { "defense", 1 },
    MINIMIZE = "reset", SMOKESCREEN = { "evasion", 1 },
    CONFUSE_RAY = { "special", 1 }, WITHDRAW = { "defense", 1 },
    DEFENSE_CURL = { "accuracy", 1 }, BARRIER = "reset",
    LIGHT_SCREEN = { "special", 1 }, HAZE = "heal", REFLECT = { "defense", 1 },
    FOCUS_ENERGY = { "accuracy", 1 }, MIRROR_MOVE = { "attack", 2 },
    AMNESIA = "reset", KINESIS = { "evasion", 1 }, SOFTBOILED = "reset",
    GLARE = { "special", 1 }, POISON_GAS = { "defense", 1 },
    LOVELY_KISS = { "speed", 1 }, TRANSFORM = "heal", SPORE = "reset",
    FLASH = { "evasion", 1 }, SPLASH = { "attack", 3 }, ACID_ARMOR = "reset",
    REST = "reset", SHARPEN = { "attack", 1 }, CONVERSION = "all",
    SUBSTITUTE = "reset",
  }
  local STATS = { "attack", "defense", "speed", "special", "accuracy", "evasion" }

  local function zStatus(def)
    if type(def) ~= "table" or zPower(def) then return nil end
    return Z_STATUS[def.id]
  end

  local function applyStatus(battle, effect)
    local player = battle.player
    player.stages = player.stages or {}
    local stages = player.stages
    local function raise(stat, by)
      stages[stat] = math.min(6, (stages[stat] or 0) + by)
    end
    local id, stat = "_ZMovesBoostText", nil
    if effect == "reset" then
      for _, s in ipairs(STATS) do
        if (stages[s] or 0) < 0 then stages[s] = 0 end
      end
      id = "_ZMovesResetText"
    elseif effect == "heal" then
      local mon = player.mon
      if mon and mon.stats and mon.stats.hp then mon.hp = mon.stats.hp end
      id = "_ZMovesHealText"
    elseif effect == "all" then
      for i = 1, 4 do raise(STATS[i], 1) end
      id = "_ZMovesBoostAllText"
    else
      raise(effect[1], effect[2])
      stat = effect[1]:upper()
    end
    pcall(function()
      battle:sayNext(line(battle.data, id,
        { USER = actorName(battle, player), STAT = stat }))
      -- the bar slides up the way RECOVER's does (MoveEffects HEAL_EFFECT)
      if effect == "heal" then battle:drainNext(player, player.mon.hp) end
    end)
  end

  -- ------- content: one Z-Move record per type the game has

  local Z = {}  -- type key -> { id, crystal, name = { .. }, anim }
  for _, row in ipairs(TYPES) do
    local sample = mod.content.moves:get(row.anim)
    if sample and typeKey(sample.type) == row.key then
      local id = PREFIX .. row.key
      local ok, err = pcall(function()
        mod.content.moves:register(id, {
          id = id,
          -- the battle box breaks on "\n" only, and "used X!" has 13
          -- columns left on its line, so the name carries its own break
          name = row.name[1] .. "\n" .. row.name[2],
          type = sample.type,
          power = 100,        -- placeholder; battle.damage sets the real one
          accuracy = 100,
          pp = 1,
          effect = "NO_ADDITIONAL_EFFECT",
          anim = sample.anim,
          counterable = false,
        })
      end)
      if ok then
        Z[row.key] = { id = id, key = row.key, crystal = row.crystal,
                       name = row.name, anim = row.anim }
      else
        mod.log:warn("could not register %s: %s", id, tostring(err))
      end
    end
  end

  -- ------- species-exclusive Z-Moves
  -- The crystal only works for its species and only on its base move; it
  -- does not power ordinary Z-Moves.  Three of the Sun/Moon base moves do
  -- not exist in Gen 1, so each has a stand-in (the real one is listed
  -- first and wins if another mod adds it).

  local EXCLUSIVE = {
    { key = "PIKANIUM", crystal = "PIKANIUM Z", species = "PIKACHU",
      bases = { "VOLT_TACKLE", "THUNDER" }, name = { "CATASTROPIKA" },
      power = 210, anim = "THUNDER" },
    { key = "SNORLIUM", crystal = "SNORLIUM Z", species = "SNORLAX",
      bases = { "GIGA_IMPACT", "HYPER_BEAM" }, name = { "PULVERIZING", "PANCAKE" },
      power = 210, anim = "BODY_SLAM" },
    { key = "MEWNIUM", crystal = "MEWNIUM Z", species = "MEW",
      bases = { "PSYCHIC_M" }, name = { "GENESIS", "SUPERNOVA" },
      power = 185, anim = "PSYCHIC_M" },
    -- Extreme Evoboost is +2 to every stat and no attack.  The record
    -- carries Swords Dance's effect, so the engine raises ATTACK itself and
    -- says so; the other three stats are raised here.
    { key = "EEVIUM", crystal = "EEVIUM Z", species = "EEVEE",
      bases = { "LAST_RESORT", "TAKE_DOWN" }, name = { "EXTREME", "EVOBOOST" },
      boost = { "defense", "speed", "special" }, anim = "SWORDS_DANCE" },
  }

  for _, row in ipairs(EXCLUSIVE) do
    local sample = mod.content.moves:get(row.anim)
    local base
    for _, id in ipairs(row.bases) do
      if mod.content.moves:get(id) then base = id break end
    end
    if sample and base then
      local id = PREFIX .. row.key
      local ok, err = pcall(function()
        mod.content.moves:register(id, {
          id = id,
          name = table.concat(row.name, "\n"),
          type = sample.type,
          power = row.boost and 0 or 100,
          accuracy = 100,
          pp = 1,
          effect = row.boost and "ATTACK_UP2_EFFECT" or "NO_ADDITIONAL_EFFECT",
          anim = sample.anim,
          counterable = false,
        })
      end)
      if ok then
        Z[row.key] = { id = id, key = row.key, crystal = row.crystal,
                       name = row.name, anim = row.anim, species = row.species,
                       base = base, power = row.power, boost = row.boost }
      else
        mod.log:warn("could not register %s: %s", id, tostring(err))
      end
    end
  end

  -- ------- Z-Move animations
  -- Built at load from the game's own animation rows (nothing from the ROM
  -- ships with the mod): a Z-Power charge-up, two signature animations of
  -- the type back to back on a dark screen, then a flash-and-shake finish.
  -- A Z-Move whose pieces are all missing keeps its borrowed animation.

  local SIGNATURE = {
    NORMAL   = { "HYPER_BEAM", "DOUBLE_EDGE" },
    FIRE     = { "FLAMETHROWER", "FIRE_BLAST" },
    WATER    = { "SURF", "HYDRO_PUMP" },
    ELECTRIC = { "THUNDERBOLT", "THUNDER" },
    GRASS    = { "PETAL_DANCE", "SOLARBEAM" },
    ICE      = { "ICE_BEAM", "BLIZZARD" },
    FIGHTING = { "MEGA_PUNCH", "MEGA_KICK", "HI_JUMP_KICK" },
    POISON   = { "ACID", "SLUDGE" },
    GROUND   = { "FISSURE", "EARTHQUAKE" },
    FLYING   = { "WING_ATTACK", "SKY_ATTACK" },
    PSYCHIC  = { "PSYBEAM", "PSYCHIC_M" },
    BUG      = { "PIN_MISSILE", "LEECH_LIFE" },
    ROCK     = { "ROCK_THROW", "ROCK_SLIDE" },
    GHOST    = { "LICK", "NIGHT_SHADE" },
    DRAGON   = { "DRAGON_RAGE", "HYPER_BEAM" },
    PIKANIUM = { "BODY_SLAM", "THUNDERBOLT", "THUNDER" },
    SNORLIUM = { "BODY_SLAM", "EARTHQUAKE" },
    MEWNIUM  = { "PSYCHIC_M", "HYPER_BEAM" },
    EEVIUM   = { "GROWTH", "SWORDS_DANCE", "AGILITY" },
  }
  -- the screen stays dark from the charge-up to the finish
  local PALETTE_ROWS = {
    SE_DARK_SCREEN_PALETTE = true, SE_LIGHT_SCREEN_PALETTE = true,
    SE_RESET_SCREEN_PALETTE = true,
  }

  local function animRows(id)
    local ok, anim = pcall(function() return mod.content.battle_anims:get(id) end)
    return ok and type(anim) == "table" and type(anim.seq) == "table"
      and anim.seq or nil
  end

  local function copyRow(row, extra)
    local out = {}
    for k, v in pairs(row) do out[k] = v end
    for k, v in pairs(extra or {}) do out[k] = v end
    return out
  end

  local function buildAnim(key)
    local z = Z[key]
    if not z then return end
    local body = {}
    for _, part in ipairs(SIGNATURE[key] or {}) do
      for _, row in ipairs(animRows(part) or {}) do
        if not (row.effect and PALETTE_ROWS[row.effect]) then
          body[#body + 1] = copyRow(row)
        end
      end
    end
    if #body == 0 then return end
    local rows = {
      { effect = "SE_DARK_SCREEN_PALETTE", sound = "LEECH_SEED" },
      { effect = "SE_SPIRAL_BALLS_INWARD" },
      { effect = "SE_DARK_SCREEN_FLASH" },
    }
    for _, row in ipairs(body) do rows[#rows + 1] = row end
    if z.boost then
      -- Extreme Evoboost powers itself up; nothing to hit
      rows[#rows + 1] = { effect = "SE_DARK_SCREEN_FLASH" }
    else
      rows[#rows + 1] = { effect = "SE_DARK_SCREEN_FLASH", sound = "EXPLOSION" }
      rows[#rows + 1] = { effect = "SE_DARK_SCREEN_FLASH" }
      rows[#rows + 1] = { effect = "SE_SHAKE_SCREEN" }
    end
    rows[#rows + 1] = { effect = "SE_RESET_SCREEN_PALETTE" }
    local ok = pcall(function()
      mod.content.battle_anims:register(z.id, { seq = rows, source = "z_moves" })
    end)
    if ok then z.ownAnim = true end
  end

  for key in pairs(Z) do buildAnim(key) end

  local function animFor(z)
    if z.ownAnim and mod.options:get("animations") ~= false then return nil end
    return z.anim
  end

  -- ------- earning the crystals
  -- STORY: the Z-Ring and Normalium Z come with the POKeDEX, each other
  -- crystal with a story milestone.  ALL: every crystal from the start.
  -- Read straight from the save's event flags, so a save already past a
  -- milestone has its crystal at once.

  -- The mod manager shows label and value only; `description` is there for
  -- managers that show more, and the README explains each one.
  mod.options:define({
    { key = "crystals", label = "Z-CRYSTALS", type = "choice", default = "story",
      choices = { { "STORY", "story" }, { "ALL", "all" } },
      description = "STORY: earn the Z-RING and each crystal as you play. "
        .. "ALL: every crystal from the start." },
    { key = "trainers", label = "TRAINER Z-MOVES", type = "toggle", default = true,
      description = "Gym Leaders, Giovanni, the Elite Four, the Champion and "
        .. "the rival from Silph Co. on use one Z-Move per battle." },
    { key = "warnings", label = "Z-RING WARNING", type = "toggle", default = true,
      description = "Says when a trainer with a Z-RING starts a battle. "
        .. "Never says which POKeMON or move." },
    { key = "animations", label = "Z-MOVE ANIMATIONS", type = "toggle", default = true,
      description = "ON: every Z-Move plays its own full animation. "
        .. "OFF: one vanilla animation of its type." },
  })

  local RING = "EVENT_GOT_POKEDEX"
  local UNLOCK = {
    NORMAL   = { RING },
    BUG      = { "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0",
                 "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1",
                 "EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_2" },
    ROCK     = { "EVENT_BEAT_BROCK" },
    WATER    = { "EVENT_BEAT_MISTY" },
    ELECTRIC = { "EVENT_BEAT_LT_SURGE" },
    PIKANIUM = { "EVENT_BEAT_LT_SURGE" },
    GRASS    = { "EVENT_BEAT_ERIKA" },
    EEVIUM   = { "EVENT_BEAT_ERIKA" },
    FIGHTING = { "EVENT_BEAT_KARATE_MASTER" },
    GHOST    = { "EVENT_BEAT_GHOST_MAROWAK" },
    FLYING   = { "EVENT_GOT_HM02" },
    SNORLIUM = { "EVENT_BEAT_ROUTE12_SNORLAX", "EVENT_BEAT_ROUTE16_SNORLAX" },
    POISON   = { "EVENT_BEAT_KOGA" },
    PSYCHIC  = { "EVENT_BEAT_SABRINA" },
    FIRE     = { "EVENT_BEAT_BLAINE" },
    GROUND   = { "EVENT_BEAT_VIRIDIAN_GYM_GIOVANNI" },
    ICE      = { "EVENT_BEAT_ARTICUNO" },
    DRAGON   = { "EVENT_BEAT_LANCE" },
    MEWNIUM  = { "EVENT_BEAT_MEWTWO" },
  }

  local function storyMode()
    return mod.options:get("crystals") ~= "all"
  end

  local function flagSet(save, name)
    local flags = type(save) == "table" and save.flags
    return type(flags) == "table" and flags[name] == true
  end

  local function hasRing(save)
    return not storyMode() or flagSet(save, RING)
  end

  local function unlocked(save, key)
    if not storyMode() then return true end
    for _, name in ipairs(UNLOCK[key] or {}) do
      if flagSet(save, name) then return true end
    end
    return false
  end

  local function saveOf(battle)
    local game = battle and battle.game or mod.game
    return game and game.save
  end

  -- per-battle state

  -- Runtime state is keyed by the live battle.  What must outlive it -- the
  -- "Z-Power spent" mark of each side -- is a data-only token on the
  -- battle's side table, which battle checkpoints capture and restore, so a
  -- restored checkpoint cannot hand out a second Z-Move.
  local battles = setmetatable({}, { __mode = "k" })
  local tick = 0
  local USED_TOKEN = "z_moves.used"

  local function sideTokens(battle, index)
    local side = type(battle.sides) == "table" and battle.sides[index]
    if type(side) ~= "table" then return nil end
    side.tokens = side.tokens or {}
    return side.tokens
  end

  local function tokenSet(battle, index)
    for _, token in ipairs(sideTokens(battle, index) or {}) do
      if type(token) == "table" and token.id == USED_TOKEN then return true end
    end
    return false
  end

  local function markSpent(battle, st, index)
    if index == 1 then st.used = true else st.foeUsed = true end
    local tokens = sideTokens(battle, index)
    if tokens and not tokenSet(battle, index) then
      tokens[#tokens + 1] = { id = USED_TOKEN }
    end
  end

  local function stateFor(battle)
    if type(battle) ~= "table" or not battle.isBattleState then return nil end
    if battle.kind ~= "wild" and battle.kind ~= "trainer" then return nil end
    if battle.safari or battle.ghost or battle.demo then return nil end
    local st = battles[battle]
    if not st then
      -- pending: the player's Z-Move this turn; foe/foeUsed: the trainer's
      st = { used = tokenSet(battle, 1), armed = false, pending = nil,
             notice = nil, foe = nil, foeUsed = tokenSet(battle, 2),
             foePlan = nil }
      battles[battle] = st
    end
    return st
  end

  -- ------- the record (Z-RING > RECORD), kept with the save

  local function record()
    local r = mod.save:get("record")
    if type(r) ~= "table" then r = {} end
    r.used = tonumber(r.used) or 0
    r.faced = tonumber(r.faced) or 0
    r.byKey = type(r.byKey) == "table" and r.byKey or {}
    return r
  end

  local function count(field, key)
    pcall(function()
      local r = record()
      r[field] = r[field] + 1
      if key then r.byKey[key] = (tonumber(r.byKey[key]) or 0) + 1 end
      mod.save:set("record", r)
    end)
  end

  -- point the borrowed move slot back at its real move
  local function restore(st)
    for _, p in ipairs({ st and st.pending or false, st and st.foe or false }) do
      if p and p.zId and p.inst.id == p.zId then p.inst.id = p.baseId end
    end
  end

  local function finish(battle, st)
    if not st then return end
    restore(st)
    -- Mirror Move reads lastMove; it should see the real move
    for side, key in pairs({ player = "pending", enemy = "foe" }) do
      local p, b = st[key], battle and battle[side]
      if p and p.zId and b and b.lastMove == p.zId then b.lastMove = p.baseId end
      st[key] = nil
    end
    st.foePlan = nil
  end

  -- the Z-Move a move slot would become, or nil plus why not
  local function zInfo(battle, inst)
    local player = battle.player
    local mon = player and player.mon
    local crystal = mon and mon[FIELD]
    local z = crystal and Z[crystal]
    if not z then return nil, "crystal" end
    local save = saveOf(battle)
    if not hasRing(save) or not unlocked(save, crystal) then
      return nil, "crystal"
    end
    local def = type(inst) == "table" and battle.data and battle.data.moves
      and battle.data.moves[inst.id]
    if z.species then
      if not def or mon.species ~= z.species or def.id ~= z.base then
        return nil, "type"
      end
      return { z = z, power = z.power, boost = z.boost, def = def }
    end
    if not def or typeKey(def.type) ~= crystal then return nil, "type" end
    local power = zPower(def)
    if power then return { z = z, power = power, def = def } end
    local effect = zStatus(def)
    if effect then return { z = z, status = effect, def = def } end
    return nil, "type"
  end

  local function usable(battle, slot)
    local player = battle.player
    local inst = player and player.curMoves and player.curMoves[slot]
    if not inst or (inst.pp or 0) <= 0 or player.disabledSlot == slot then
      return nil
    end
    return zInfo(battle, inst)
  end

  -- true, or false plus the line to show the player
  local function available(battle, st)
    if st.used then return false, "ALREADY USED" end
    if not hasRing(saveOf(battle)) then return false, "NO Z-RING YET" end
    local mon = battle.player and battle.player.mon
    if not (mon and Z[mon[FIELD] or ""]) then
      return false, "NO CRYSTAL HELD"
    end
    for slot = 1, 4 do
      if usable(battle, slot) then return true end
    end
    return false, "NO MATCHING MOVE"
  end

  local function toggle(battle, st)
    if st.armed then
      st.armed = false
      return
    end
    local ok, why = available(battle, st)
    if ok then
      st.armed, st.notice = true, nil
    else
      st.notice = { text = why, untilTick = tick + 90 }
    end
  end

  local function topBattle(game)
    local stack = game and game.stack
    local states = stack and stack.states
    local top = states and states[#states]
    if top and top.isBattleState then return top end
  end

  -- ------- trainers with Z-Power
  -- Gym Leaders, Giovanni, the Elite Four and the Champion hold a crystal
  -- on their last Pokemon, like a Kahuna.  The crystal is their own type
  -- when that Pokemon knows a damaging move of it, else the type of its
  -- strongest damaging move.  It fires the first turn it can, once.

  local LEADERS = {
    OPP_BROCK = "ROCK", OPP_MISTY = "WATER", OPP_LT_SURGE = "ELECTRIC",
    OPP_ERIKA = "GRASS", OPP_KOGA = "POISON", OPP_SABRINA = "PSYCHIC",
    OPP_BLAINE = "FIRE", OPP_GIOVANNI = "GROUND", OPP_LORELEI = "ICE",
    OPP_BRUNO = "FIGHTING", OPP_AGATHA = "GHOST", OPP_LANCE = "DRAGON",
    OPP_RIVAL3 = true,
  }
  -- The rival joins in from Silph Co. on.  His party numbers differ between
  -- Red/Blue and Yellow, his levels do not: his last Pokemon is 40 at Silph
  -- Co. and 53 on Route 22, and 25 at most in every earlier fight.
  local RIVAL_FROM_LEVEL = 35

  -- does this trainer battle come with a Z-Ring at all?
  local function zTrainer(battle)
    if mod.options:get("trainers") == false then return nil end
    if battle.kind ~= "trainer" or battle.link then return nil end
    local own = LEADERS[battle.oppClass]
    if own then return own end
    local party = battle.enemyParty
    local ace = type(party) == "table" and party[#party]
    if battle.oppClass == "OPP_RIVAL2" and type(ace) == "table"
        and (tonumber(ace.level) or 0) >= RIVAL_FROM_LEVEL then
      return true
    end
    return nil
  end

  local function foeSlots(battle)
    local own = zTrainer(battle)
    local party, enemy = battle.enemyParty, battle.enemy
    if not own or type(party) ~= "table" or not enemy
        or enemy.mon ~= party[#party] then
      return nil
    end
    local unlimited = battle.ruleset and battle.ruleset.enemyUnlimitedPP
    local best = {}  -- type key -> { inst, power }
    for i, inst in ipairs(enemy.curMoves or {}) do
      local def = battle.data and battle.data.moves[inst.id]
      local power = zPower(def)
      local key = def and typeKey(def.type)
      if power and Z[key] and enemy.disabledSlot ~= i
          and (unlimited or (inst.pp or 0) > 0) then
        if not best[key] or power > best[key].power then
          best[key] = { inst = inst, power = power, def = def }
        end
      end
    end
    if own ~= true and best[own] then return best[own], own end
    local pick, pickKey
    for key, row in pairs(best) do
      if not pick or row.power > pick.power then pick, pickKey = row, key end
    end
    return pick, pickKey
  end

  mod.hooks:wrap("battle.enemy_action", function(next, battle)
    local action = next(battle)
    local st = stateFor(battle)
    if not st or st.foeUsed or type(action) ~= "table" then return action end
    -- recharging, thrashing, charging: the move is not the trainer's choice
    local ok, locked = pcall(function()
      return battle:lockedAction(battle.enemy)
    end)
    if not ok or locked then return action end
    local row, key = foeSlots(battle)
    if not row then return action end
    st.foePlan = { inst = row.inst, key = key, power = row.power, def = row.def }
    return row.inst
  end)

  -- ------- turn flow

  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    local st = stateFor(battle)
    if not st then return end
    local plan = st.foePlan
    finish(battle, st)
    -- the trainer's Z-Move, planned when its action was chosen.  Its line
    -- is said when the move fires, so a turn the trainer spends on an item
    -- or a switch announces nothing.
    if plan and ev.enemyAction == plan.inst and not st.foeUsed then
      local z = Z[plan.key]
      st.foe = { inst = plan.inst, baseId = plan.inst.id, zId = z.id,
                 key = plan.key, power = plan.power, def = plan.def,
                 anim = animFor(z), executed = false }
      plan.inst.id = z.id
    end
    local armed = st.armed
    st.armed = false
    -- the move menu is the only place a Z-Move is chosen: locked turns
    -- (recharge, Thrash, Rage...) resolve from the command menu instead
    if not armed or st.used or battle.phase ~= "moveSelect" then return end
    local action = ev.playerAction
    local info = zInfo(battle, action)
    if not info then return end
    local owned = false
    for _, inst in ipairs(battle.player.curMoves or {}) do
      if inst == action then owned = true break end
    end
    if not owned then return end

    -- spent only when the move fires (battle.move_used): as in Sun/Moon, a
    -- Pokemon kept from moving by sleep, paralysis, a flinch or confusion
    -- keeps its Z-Power for a later turn
    if info.status then
      -- a status Z-Move stays the move it is; only its bonus is new
      st.pending = { inst = action, baseId = action.id, status = info.status,
                     key = info.z.key, executed = false }
      return
    end
    st.pending = { inst = action, baseId = action.id, zId = info.z.id,
                   key = info.z.key, power = info.power, def = info.def,
                   anim = animFor(info.z), boost = info.boost, executed = false }
    action.id = info.z.id
  end)

  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local st = battle and battles[battle]
    local f = st and st.foe
    if f and not f.executed and not ev.isCalled and ev.user == battle.enemy
        and ev.move and ev.move.id == f.zId then
      f.executed = true
      markSpent(battle, st, 2)
      count("faced")
      if f.inst.id == f.zId then f.inst.id = f.baseId end
      local row = battle.moveAnimRow
      if f.anim and type(row) == "table" and row.anim == f.zId then row.anim = f.anim end
      pcall(sayBeforeUse, battle, line(battle.data, "_ZMovesUnleashText",
        { USER = actorName(battle, battle.enemy) }))
      return
    end
    local p = st and st.pending
    if not p or p.executed or ev.isCalled or ev.user ~= battle.player
        or not ev.move then
      return
    end
    if p.status then
      if ev.move.id == p.baseId then
        p.executed = true
        markSpent(battle, st, 1)
        count("used", p.key)
        pcall(sayBeforeUse, battle, line(battle.data, "_ZMovesAuraText",
          { USER = actorName(battle, battle.player) }))
        applyStatus(battle, p.status)
      end
      return
    end
    if ev.move.id ~= p.zId then return end
    p.executed = true
    markSpent(battle, st, 1)
    count("used", p.key)
    pcall(sayBeforeUse, battle, line(battle.data, "_ZMovesUnleashText",
      { USER = actorName(battle, battle.player) }))
    -- PP has already come off the real move slot; the trainer's slot is
    -- left alone, it may not have moved yet
    if p.inst.id == p.zId then p.inst.id = p.baseId end
    -- play the borrowed animation instead of looking one up under our id
    local row = battle.moveAnimRow
    if p.anim and type(row) == "table" and row.anim == p.zId then row.anim = p.anim end
    if p.boost then
      local player = battle.player
      player.stages = player.stages or {}
      for _, stat in ipairs(p.boost) do
        player.stages[stat] = math.min(6, (player.stages[stat] or 0) + 2)
      end
      pcall(function()
        battle:sayNext(line(battle.data, "_ZMovesBoostAllText",
          { USER = actorName(battle, player) }))
      end)
    end
  end)

  local function zActive(ctx)
    local battle = ctx and ctx.battle
    local st = battle and battles[battle]
    if not st or not ctx.move then return nil end
    local p = ctx.user == battle.player and st.pending
      or ctx.user == battle.enemy and st.foe
    if p and p.zId and p.power and p.executed and ctx.move.id == p.zId then
      return p
    end
  end

  -- Z-Moves bypass the accuracy roll (a foe mid-Fly/Dig still avoids them:
  -- the engine checks that before it rolls)
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    local p = zActive(ctx)
    if not p then return next(ctx) end
    if ctx.user.lastMove == p.zId then ctx.user.lastMove = p.baseId end
    return true
  end)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local p = zActive(ctx)
    if not p then return next(ctx) end
    if ctx.user.lastMove == p.zId then ctx.user.lastMove = p.baseId end
    -- copies: the registry record and the engine's ctx are never written
    local move, call = {}, {}
    for k, v in pairs(ctx.move) do move[k] = v end
    for k, v in pairs(ctx) do call[k] = v end
    move.power = p.power
    move.type = p.def.type or move.type
    if p.def.category ~= nil then move.category = p.def.category end
    call.move = move
    return next(call)
  end)

  -- optional heads-up when a Z-Ring trainer's battle opens.  It names the
  -- trainer only, never the Pokemon or the move, so the Z-Move itself stays
  -- a surprise.  battle.started fires after the whole intro is queued, so
  -- the line lands just before the first menu.
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    local st = stateFor(battle)
    if not st or st.foeUsed or mod.options:get("warnings") == false then return end
    if not zTrainer(battle) then return end
    local name = battle.trainer and battle.trainer.name or "The trainer"
    pcall(function()
      battle:sayAuto(line(battle.data, "_ZMovesWarningText", { TRAINER = name }), 40)
    end)
  end)

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    finish(battle, battle and battles[battle])
  end)

  -- A Pokemon that faints or leaves before its Z-Move fires hands the slot
  -- back at once: the faint and switch flows can skip the rest of the turn,
  -- and its move list may be shown (party menu, summary) before the next
  -- turn_ended would have done it.  The Z-Power was not spent.
  local function dropPending(battle, st, battler)
    for key, side in pairs({ pending = battle.player, foe = battle.enemy }) do
      local p = st[key]
      if p and not p.executed and (battler == nil or battler == side) then
        if p.zId and p.inst.id == p.zId then p.inst.id = p.baseId end
        st[key] = nil
      end
    end
  end

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local st = battle and battles[battle]
    if not st then return end
    st.armed = false
    dropPending(battle, st, nil)
  end)

  mod.events:on("battle.fainted", function(ev)
    local battle = ev and ev.battle
    local st = battle and battles[battle]
    if st then dropPending(battle, st, ev.battler) end
  end)

  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    finish(battle, battle and battles[battle])
    if battle then battles[battle] = nil end
  end)

  -- a save can never carry a Z-Move id in a move slot
  mod.events:on("save.writing", function()
    for _, st in pairs(battles) do restore(st) end
  end)

  -- ------- input: START toggles Z-Power

  -- The move list has no hook of its own, and START does nothing there, so
  -- read the press on the fixed step after it happened.
  mod.hooks:wrap("input.step", function(next, game, dt)
    tick = tick + 1
    pcall(function()
      local input = game and game.input
      if not (input and input.wasPressed and input:wasPressed("start")) then
        return
      end
      local battle = topBattle(game)
      local st = stateFor(battle)
      if st and battle.phase == "moveSelect" and not battle.moveSwapIndex then
        toggle(battle, st)
      end
    end)
    return next(game, dt)
  end)

  -- the command menu's START is a shared hook; only claim it for a
  -- Pokemon that actually holds a crystal
  mod.hooks:wrap("battle.menu_auxiliary", function(next, game, info)
    local battle = topBattle(game)
    local st = stateFor(battle)
    local mon = st and battle.phase == "menu" and battle.player
      and battle.player.mon
    if mon and Z[mon[FIELD] or ""] then
      toggle(battle, st)
      return true
    end
    return next(game, info)
  end)

  -- ------- battle overlay
  -- One slim bar between the two Pokemon, 20 characters wide:
  --   Z:GIGAVOLT HAVOC 175     Z:THUNDER WAVE SPC+1
  -- Both HUDs, the TYPE/PP panel and the move list stay visible; only the
  -- top of your Pokemon and the foot of the foe are covered.  A name too
  -- long for its space scrolls through instead of being cut.

  local BAR_Y = 36       -- pixels; rows 4-6, clear of both HUDs
  local BAR_H = 16
  local COLS = 20

  local SHORT_STAT = { attack = "ATK", defense = "DEF", speed = "SPD",
                       special = "SPC", accuracy = "ACC", evasion = "EVA" }
  local function shortEffect(effect)
    if effect == "reset" then return "RESET" end
    if effect == "heal" then return "HEAL" end
    if effect == "all" then return "ALL+1" end
    return (SHORT_STAT[effect[1]] or "?") .. "+" .. effect[2]
  end

  -- hold the start, step one letter at a time, hold the end, repeat.
  -- Widths are measured with the font, not counted, so a font or UI mod
  -- with wider or narrower letters still never runs past the bar.
  local HOLD, STEP = 50, 9
  local function fits(Font, text, pixels) return Font.width(text) <= pixels end

  local function window(Font, text, pixels, since)
    if fits(Font, text, pixels) then return text end
    -- the longest tail that fits decides how far the scroll goes
    local over = 0
    while over < #text and not fits(Font, text:sub(over + 1), pixels) do
      over = over + 1
    end
    local cycle = HOLD + over * STEP + HOLD
    local t = (tick - since) % cycle
    local shift = t < HOLD and 0 or math.min(over, math.floor((t - HOLD) / STEP) + 1)
    local shown = text:sub(shift + 1)
    while #shown > 0 and not fits(Font, shown, pixels) do
      shown = shown:sub(1, -2)
    end
    return shown
  end

  local function drawBar(Font, ox, left, right, st)
    local g = love.graphics
    local x, w = ox * 8, COLS * 8
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", x, BAR_Y, w, BAR_H)
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", x, BAR_Y, w, 1)
    g.rectangle("fill", x, BAR_Y + BAR_H - 1, w, 1)
    right = right or ""
    local prefix = "Z:"
    local rightW = #right > 0 and Font.width(right) or 0
    local gap = #right > 0 and Font.width(" ") or 0
    local room = w - Font.width(prefix) - gap - rightW
    -- restart the scroll whenever the text changes (another move highlighted)
    if st.barText ~= left then st.barText, st.barSince = left, tick end
    Font.draw(prefix .. window(Font, left, room, st.barSince), x, BAR_Y + 4)
    if #right > 0 then Font.draw(right, x + w - rightW, BAR_Y + 4) end
  end

  -- Widescreen lays the moves out 2x2 with no free panel beside them, and a
  -- twelve-letter name runs right up to the next column.  The one place
  -- next to each move that is always free is the box border: the top
  -- border above the first row, the bottom border below the second.  A
  -- small Z tab sits there, under the last letters of the name field.
  local function drawWideMarkers(battle, Font, g)
    for slot = 1, 4 do
      if usable(battle, slot) then
        local col = (slot - 1) % 2
        local row = math.floor((slot - 1) / 2)
        local x = (col == 0 and 16 or 120) + 88
        local y = row == 0 and 104 or 136
        g.setColor(1, 1, 1, 1)
        g.rectangle("fill", x - 1, y, 10, 8)
        g.setColor(0, 0, 0, 1)
        Font.draw("Z", x, y)
      end
    end
  end

  local function drawOverlay(battle)
    local st = stateFor(battle)
    if not st then return end
    local phase = battle.phase
    local choosing = phase == "menu" or phase == "moveSelect"
    if choosing and st.pending then finish(battle, st) end
    if st.armed and (not choosing or not available(battle, st)) then
      st.armed = false
    end
    if not choosing then return end

    local Font = mod.ui.Font
    local g = love.graphics
    -- the widescreen battle surface is 38 tiles wide; centre on it
    local wide = battle.wideLayout and battle:wideLayout()
    local ox = wide and 9 or 0

    if st.notice then
      if tick < st.notice.untilTick then
        drawBar(Font, ox, st.notice.text, nil, st)
      else
        st.notice = nil
      end
    elseif st.armed and phase == "moveSelect" then
      local info = usable(battle, battle.moveIndex or 1)
      if info and info.status then
        drawBar(Font, ox, tostring(info.def.name or info.def.id),
          shortEffect(info.status), st)
      elseif info and info.boost then
        drawBar(Font, ox, table.concat(info.z.name, " "), "ALL+2", st)
      elseif info then
        drawBar(Font, ox, table.concat(info.z.name, " "), tostring(info.power), st)
      else
        drawBar(Font, ox, "NO Z-MOVE", nil, st)
      end
    elseif st.armed then
      drawBar(Font, ox, "POWER READY", nil, st)
    elseif phase == "moveSelect" and wide and available(battle, st) then
      drawWideMarkers(battle, Font, g)
    elseif phase == "moveSelect" and available(battle, st) then
      -- a Z in the empty panel left of the move list, on the row of each
      -- move that can become one (a 12-letter name fills the list's own
      -- columns, so a marker inside the list reads as part of the name)
      g.setColor(0, 0, 0, 1)
      for slot = 1, 4 do
        if usable(battle, slot) then Font.draw("Z", 16, 96 + slot * 8) end
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    pcall(drawOverlay, battle)
  end)

  -- ------- party menu: give / take a Z-Crystal

  local function monName(game, mon)
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end

  local function openCrystals(mon, game)
    local held = mon[FIELD]
    local fits = {}
    for _, inst in ipairs(mon.moves or {}) do
      local def = game.data.moves[inst.id]
      if zPower(def) or zStatus(def) then fits[typeKey(def.type)] = true end
    end
    -- its own species crystal first, then the type crystals it can use,
    -- then the rest in type order
    local items = {}
    local save = game.save
    local function offered(key) return unlocked(save, key) or held == key end
    for _, row in ipairs(EXCLUSIVE) do
      local z = Z[row.key]
      if z and mon.species == z.species and offered(row.key) then
        local knows = false
        for _, inst in ipairs(mon.moves or {}) do
          if inst.id == z.base then knows = true end
        end
        items[#items + 1] = { label = row.crystal, key = row.key,
          right = held == row.key and "HELD" or knows and "OK" or nil }
      end
    end
    for pass = 1, 2 do
      for _, row in ipairs(TYPES) do
        if Z[row.key] and offered(row.key)
            and (fits[row.key] == true) == (pass == 1) then
          items[#items + 1] = { label = row.crystal, key = row.key,
            right = held == row.key and "HELD" or fits[row.key] and "OK" or nil }
        end
      end
    end
    if held then
      table.insert(items, 1, { label = "TAKE CRYSTAL", take = true })
    end
    if #items == 0 then
      game.stack:push(mod.ui.TextBox.new(game, "No Z-CRYSTALS\nyet."))
      return
    end
    game.stack:push(mod.ui.ListMenu.new(game, "Z-CRYSTALS", items, {
      onChoose = function(item, list)
        local name = monName(game, mon)
        local text
        if item.take then
          mon[FIELD] = nil
          text = name .. " gave\nback its crystal."
        else
          mon[FIELD] = item.key
          text = name .. " holds\n" .. item.label .. "!"
        end
        list:close()
        game.stack:push(mod.ui.TextBox.new(game, text))
      end,
    }))
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local rows = next(game, items, mon, ctx)
    if type(rows) ~= "table" or type(mon) ~= "table" or (ctx and ctx.battle) then
      return rows
    end
    -- no Z-Ring yet: no row, unless a crystal is held and needs taking back
    if not hasRing(game and game.save) and not mon[FIELD] then return rows end
    -- the row names what is held (Z:ELECTRIC, Z:PIKANIUM), so the party
    -- menu shows each Pokemon's crystal without opening anything
    local held = mon[FIELD] and Z[mon[FIELD]]
    local label = held and ("Z:" .. (held.species
      and (held.crystal:gsub(" Z$", "")) or held.key)) or "Z-CRYSTAL"
    mod.ui.insertBefore(rows, "STATS", {
      label = label,
      -- The submenu box is sized from its widest field move and is only six
      -- columns wide without one.  SOFTBOILED's width (ten columns) fits
      -- every label above; the row still runs onSelect, never the move.
      move = "softboiled",
      onSelect = function(selected, g) openCrystals(selected or mon, g or game) end,
    })
    return rows
  end)

  -- ------- the Z-RING key item
  -- A real key item, so it sits in the BAG and the PC like any other.  The
  -- engine quarantines bag items whose content disappears (the mod turned
  -- off) and hands them back when it returns, so the item cannot damage a
  -- save.  Owning the ring is still read from the story flags; the item is
  -- how the player reaches the Z-RING screen.

  local RING_ITEM = "Z_RING"
  local ringItem = pcall(function()
    mod.content.items:register(RING_ITEM, {
      id = RING_ITEM, name = "Z-RING", price = 0,
      keyItem = true, tossable = false,
    })
  end)

  local function holdsRingItem(save)
    if type(save) ~= "table" then return false end
    for _, store in ipairs({ save.inventory, save.pcItems }) do
      if type(store) == "table" and (tonumber(store[RING_ITEM]) or 0) > 0 then
        return true
      end
    end
    for _, entry in ipairs(type(save.orphaned) == "table"
        and save.orphaned.items or {}) do
      if type(entry) == "table" and entry.id == RING_ITEM then return true end
    end
    return false
  end

  -- give_item stops the whole script with "no more room" when the BAG is
  -- full, so the ring only goes out when there is a free slot.  Counted the
  -- way Gen 1's single bag counts (src/inventory/Bag.lua): one slot per
  -- item, one more per 99 beyond the first stack, badges free, capacity
  -- data.constants.bagSize or 20.  Read from public data only.
  local function bagHasRoom(game)
    local save, data = game and game.save, game and game.data
    if type(save) ~= "table" then return false end
    local used = 0
    for id, n in pairs(save.inventory or {}) do
      n = tonumber(n) or 0
      if n > 0 and not tostring(id):find("BADGE", 1, true) then
        used = used + math.max(1, math.ceil(n / 99))
      end
    end
    local cap = data and data.constants and tonumber(data.constants.bagSize)
    cap = (cap and cap >= 1) and math.floor(cap) or 20
    return used < cap
  end

  -- ------- "got a crystal" messages
  -- Which crystals have been announced is kept with the save, so a message
  -- missed to a crash or a reset (Lance is followed straight by the
  -- Champion, the Hall of Fame and the credits) still shows later.  It is
  -- shown through the overworld's own script queue, which waits for warps,
  -- cutscenes and scripted walks to finish before it runs anything.  Each
  -- one plays the key-item fanfare.

  local LABEL, ORDER = {}, {}
  for i, row in ipairs(TYPES) do LABEL[row.key], ORDER[row.key] = row.crystal, i end
  for i, row in ipairs(EXCLUSIVE) do
    LABEL[row.key], ORDER[row.key] = row.crystal, 100 + i
  end

  local FANFARE = "Get_Key_Item"
  local RING_TEXT = "_ZMovesGotZRingText"
  local RING_BAG_TEXT = "_ZMovesRingToBagText"
  local function gotText(key) return "_ZMovesGot" .. key .. "Text" end
  -- registered text, so a translation mod can override it
  pcall(function()
    mod.content.text:register(RING_TEXT, "{PLAYER} got a\nZ-RING!")
    mod.content.text:register(RING_BAG_TEXT, "{PLAYER} put the\nZ-RING in the PACK.")
    for key, label in pairs(LABEL) do
      if Z[key] then
        mod.content.text:register(gotText(key), "{PLAYER} got\n" .. label .. "!")
      end
    end
  end)

  -- every milestone already passed, without a message: a save from before
  -- this version, or one first loaded with the mod, starts here
  local function baseline(save)
    local seen = { RING = hasRing(save) or nil }
    for key in pairs(UNLOCK) do
      if Z[key] and unlocked(save, key) then seen[key] = true end
    end
    return seen
  end

  local function announced(save)
    local seen = mod.save:get("announced")
    if type(seen) ~= "table" then
      seen = baseline(save)
      mod.save:set("announced", seen)
    end
    return seen
  end

  mod.events:on("save.loaded", function(ev)
    if storyMode() then announced(ev and ev.save) end
  end)

  local function overworld()
    local ok, ow = pcall(function() return mod.world:overworld() end)
    if ok and ow then return ow end
    local states = mod.game and mod.game.stack and mod.game.stack.states
    for i = #(states or {}), 1, -1 do
      if states[i].isOverworld then return states[i] end
    end
  end

  -- world.stepped only fires for steps the player took, never scripted ones
  mod.events:on("world.stepped", function()
    local game = mod.game
    local save = game and game.save
    if not save then return end
    local story = storyMode()
    local seen = story and announced(save) or {}
    local rows, keys = {}, {}
    local giveRing = ringItem and hasRing(save) and not holdsRingItem(save)
      and mod.save:get("ringGiven") ~= true and bagHasRoom(game)
    if story and hasRing(save) and not seen.RING then
      -- the first Z-RING: into the BAG with its own fanfare when it fits
      if giveRing then
        rows[#rows + 1] = { "give_item", RING_ITEM, 1, RING_TEXT }
        giveRing = false
      else
        rows[#rows + 1] = { "text_sound", FANFARE }
        rows[#rows + 1] = { "show_text", RING_TEXT }
      end
    end
    if giveRing then
      -- a save that had the ring before the item existed, or a BAG that was
      -- full when it was earned
      rows[#rows + 1] = { "give_item", RING_ITEM, 1, RING_BAG_TEXT }
    end
    if story then
      for key in pairs(UNLOCK) do
        if Z[key] and not seen[key] and unlocked(save, key) then
          keys[#keys + 1] = key
        end
      end
      table.sort(keys, function(a, b) return ORDER[a] < ORDER[b] end)
      for _, key in ipairs(keys) do
        rows[#rows + 1] = { "text_sound", FANFARE }
        rows[#rows + 1] = { "show_text", gotText(key) }
      end
    end
    if #rows == 0 then return end
    local ow = overworld()
    if not (ow and ow.queueScript) then return end
    -- marked only once the message is actually on its way
    if story then
      if hasRing(save) then seen.RING = true end
      for _, key in ipairs(keys) do seen[key] = true end
      mod.save:set("announced", seen)
    end
    for _, row in ipairs(rows) do
      if row[1] == "give_item" then mod.save:set("ringGiven", true) end
    end
    ow:queueScript(rows)
  end)

  -- ------- the Z-RING screen: crystals, party, record

  local function crystalStem(key)
    local label = LABEL[key] or key
    return (label:gsub(" Z$", ""))
  end

  local function zMoveName(key)
    local z = Z[key]
    return z and table.concat(z.name, " ") or key
  end

  -- the type's display name from the merged type chart (a translation or
  -- a type mod may rename it), else its id without pokered's _TYPE
  local function typeName(game, key)
    for _, row in ipairs(TYPES) do
      if row.key == key then
        local sample = game.data.moves[row.anim]
        local types = game.data.type_chart and game.data.type_chart.types
        local record = sample and type(types) == "table" and types[sample.type]
        if type(record) == "table" and type(record.name) == "string" then
          return record.name
        end
      end
    end
    return key
  end

  local function describe(game, key)
    local z = Z[key]
    if not z then return "" end
    local zname = z.name[2] and (z.name[1] .. "\n" .. z.name[2]) or z.name[1]
    if z.species then
      local mon = game.data.pokemon[z.species]
      local base = game.data.moves[z.base]
      return ("Only for %s.\n%s becomes\f%s!"):format(
        mon and mon.name or z.species, base and base.name or z.base, zname)
    end
    return ("Turns %s\nmoves into\f%s!"):format(typeName(game, key), zname)
  end

  local function showText(game, text, onDone)
    game.stack:push(mod.ui.TextBox.new(game, text, onDone))
  end

  local function openCollection(game)
    local save = game.save
    local items = {}
    local held = {}
    for _, mon in ipairs(save.party or {}) do
      if mon[FIELD] then held[mon[FIELD]] = true end
    end
    local function add(key)
      if not Z[key] then return end
      if unlocked(save, key) then
        items[#items + 1] = { label = LABEL[key], key = key,
                              right = held[key] and "HELD" or nil }
      else
        items[#items + 1] = { label = "-----------", locked = true }
      end
    end
    for _, row in ipairs(TYPES) do add(row.key) end
    for _, row in ipairs(EXCLUSIVE) do add(row.key) end
    game.stack:push(mod.ui.ListMenu.new(game, "Z-CRYSTALS", items, {
      onChoose = function(item)
        if item.locked then
          showText(game, "Not found yet.")
        else
          showText(game, describe(game, item.key))
        end
      end,
    }))
  end

  local function monLabel(game, mon)
    local def = game.data.pokemon and game.data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end

  local function openParty(game)
    local items = {}
    for _, mon in ipairs(game.save.party or {}) do
      local key = mon[FIELD]
      items[#items + 1] = { label = monLabel(game, mon), key = key,
        right = key and Z[key] and crystalStem(key) or "-----" }
    end
    if #items == 0 then return showText(game, "No POKéMON.") end
    game.stack:push(mod.ui.ListMenu.new(game, "PARTY", items, {
      onChoose = function(item)
        if item.key and Z[item.key] then
          showText(game, ("%s holds\n%s."):format(item.label, LABEL[item.key]))
        else
          showText(game, item.label .. "\nholds no crystal.")
        end
      end,
    }))
  end

  local function openRecord(game)
    local r = record()
    local best, bestN
    for key, n in pairs(r.byKey) do
      n = tonumber(n) or 0
      if Z[key] and (not bestN or n > bestN
          or (n == bestN and (ORDER[key] or 0) < (ORDER[best] or 0))) then
        best, bestN = key, n
      end
    end
    local text = ("Your Z-Moves: %d\nFoes' Z-Moves: %d"):format(r.used, r.faced)
    if best then
      -- one line when the name fits the 18-column box, else its two words
      -- on two pages
      local z = Z[best]
      local joined = table.concat(z.name, " ")
      text = text .. ("\fMost used (x%d):\n"):format(bestN)
        .. (#joined <= 18 and joined or (z.name[1] .. "\f" .. z.name[2]))
    end
    showText(game, text)
  end

  local function openRing(game)
    local items = {
      { label = "CRYSTALS", open = openCollection },
      { label = "PARTY", open = openParty },
      { label = "RECORD", open = openRecord },
    }
    game.stack:push(mod.ui.ListMenu.new(game, "Z-RING", items, {
      onChoose = function(item) item.open(game) end,
    }))
  end

  -- USE from the BAG opens the screen; the ring is never spent.  In battle
  -- the bag answers with its own "not the time" before this runs.
  mod.hooks:wrap("item.use", function(next, game, battle, id, ...)
    if id ~= RING_ITEM then return next(game, battle, id, ...) end
    if battle then return next(game, battle, id, ...) end
    pcall(openRing, game)
  end)

  -- ------- Gen1 Modern UI
  -- When Modern UI is installed its party and summary screens replace the
  -- vanilla ones.  Its documented additive extensions let Z-Moves add a Z
  -- badge to crystal holders on the party list and a Z-CRYSTAL page to the
  -- summary, as data only: Modern UI draws them, Z-Moves draws nothing on
  -- its screens.  Without Modern UI none of this runs.

  local function summaryRows(game, mon)
    local key = type(mon) == "table" and mon[FIELD]
    local z = key and Z[key]
    if not z then
      return { { label = "CRYSTAL", value = "NONE" } }
    end
    local rows = {
      { label = "CRYSTAL", value = z.crystal },
      { label = "Z-MOVE", value = table.concat(z.name, " ") },
    }
    if z.species then
      local base = game and game.data.moves[z.base]
      rows[#rows + 1] = { label = "FROM", value = base and base.name or z.base }
    end
    return rows
  end

  mod.exports.gen1ModernUi = {
    apiVersion = 1,
    extensions = {
      zMovesCrystals = {
        match = function(state, kind)
          return kind == "party" or kind == "summary"
        end,
        model = function(game, state, kind)
          if kind == "party" then
            local rows = {}
            local party = type(state) == "table" and state.party
              or (game and game.save and game.save.party) or {}
            for index, mon in ipairs(party) do
              if type(mon) == "table" and Z[mon[FIELD] or ""] then
                rows[index] = { badge = { text = "Z", color = "accent" } }
              end
            end
            return { rows = rows }
          end
          local mon = type(state) == "table"
            and (state.mon or state.pokemon) or nil
          return { pages = { { id = "z-crystal", title = "Z-CRYSTAL",
                               rows = summaryRows(game, mon) } } }
        end,
        priority = 20,
      },
    },
  }

  mod.events:on("mods.loaded", function()
    pcall(function()
      local ui = mod.find and mod.find("gen1_modern_ui") or nil
      if ui and ui.exports and ui.exports.registerAdapter then
        ui.exports.registerAdapter({ owner = mod.id,
                                     contract = mod.exports.gen1ModernUi })
      end
    end)
  end)

  -- ------- for other mods (a custom battle UI can draw its own Z button)

  mod.exports.field = FIELD
  mod.exports.zPower = zPower
  mod.exports.zStatus = zStatus
  mod.exports.unlocked = function(key) return unlocked(mod.game and mod.game.save, key) end
  mod.exports.crystalOf = function(mon)
    local z = type(mon) == "table" and Z[mon[FIELD] or ""]
    return z and z.crystal or nil
  end
  mod.exports.state = function(battle)
    local st = battle and stateFor(battle)
    return { armed = st and st.armed or false, used = st and st.used or false,
             foeUsed = st and st.foeUsed or false }
  end
  -- the Z-Move a move slot would become right now, for a custom battle UI:
  -- { name, power } or { name, effect } for a status move, or nil
  mod.exports.preview = function(battle, slot)
    local st = battle and stateFor(battle)
    if not st or st.used then return nil end
    local info = usable(battle, slot)
    if not info then return nil end
    if info.status then
      return { name = info.def and info.def.name, effect = shortEffect(info.status) }
    end
    return { name = table.concat(info.z.name, " "), power = info.power,
             effect = info.boost and "ALL+2" or nil }
  end
  mod.exports.record = function() return record() end
end
