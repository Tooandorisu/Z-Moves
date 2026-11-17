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
--   5. One Z-Move per battle.

return function(mod)
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

  -- what the preview box prints, and what the battle says
  local function statusLabel(effect)
    if effect == "reset" then return "RESET STATS", "reset its stats" end
    if effect == "heal" then return "RESTORE ALL HP", "restored its HP" end
    if effect == "all" then return "ALL STATS +1", "boosted its stats" end
    local stat = effect[1]:upper()
    return stat .. " +" .. effect[2], "boosted " .. stat
  end

  local function applyStatus(battle, effect)
    local player = battle.player
    player.stages = player.stages or {}
    local stages = player.stages
    local function raise(stat, by)
      stages[stat] = math.min(6, (stages[stat] or 0) + by)
    end
    if effect == "reset" then
      for _, stat in ipairs(STATS) do
        if (stages[stat] or 0) < 0 then stages[stat] = 0 end
      end
    elseif effect == "heal" then
      local mon = player.mon
      if mon and mon.stats and mon.stats.hp then mon.hp = mon.stats.hp end
    elseif effect == "all" then
      for i = 1, 4 do raise(STATS[i], 1) end
    else
      raise(effect[1], effect[2])
    end
    local _, said = statusLabel(effect)
    pcall(function()
      battle:sayNext(tostring(player.name) .. "\n" .. said
        .. "\nwith its Z-Power!")
      -- the HP bar only moves when a drain row runs
      if effect == "heal" then battle:drainNext() end
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

  mod.options:define({
    { key = "crystals", label = "Z-CRYSTALS", type = "choice", default = "story",
      choices = { { "STORY", "story" }, { "ALL", "all" } } },
    { key = "trainers", label = "TRAINER Z-MOVES", type = "toggle", default = true },
    { key = "animations", label = "Z-MOVE ANIMATIONS", type = "toggle", default = true },
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

  -- keyed by the live battle, so a battle rebuilt by a checkpoint restore
  -- simply starts clean instead of reading another battle's state
  local battles = setmetatable({}, { __mode = "k" })
  local tick = 0

  local function stateFor(battle)
    if type(battle) ~= "table" or not battle.isBattleState then return nil end
    if battle.kind ~= "wild" and battle.kind ~= "trainer" then return nil end
    if battle.safari or battle.ghost or battle.demo then return nil end
    local st = battles[battle]
    if not st then
      -- pending: the player's Z-Move this turn; foe/foeUsed: the trainer's
      st = { used = false, armed = false, pending = nil, notice = nil,
             foe = nil, foeUsed = false, foePlan = nil }
      battles[battle] = st
    end
    return st
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

  local function foeSlots(battle)
    if mod.options:get("trainers") == false then return nil end
    if battle.kind ~= "trainer" or battle.link then return nil end
    local own = LEADERS[battle.oppClass]
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
    -- the trainer's Z-Move, planned when its action was chosen
    if plan and ev.enemyAction == plan.inst and not st.foeUsed then
      local z = Z[plan.key]
      st.foe = { inst = plan.inst, baseId = plan.inst.id, zId = z.id,
                 power = plan.power, def = plan.def, anim = animFor(z),
                 executed = false }
      plan.inst.id = z.id
      pcall(function()
        battle:sayAuto(battle:romLine("EnemyText") .. tostring(battle.enemy.name)
          .. "\nunleashes its\nfull-force Z-Move!", 40)
      end)
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

    -- as in Sun/Moon, Z-Power is spent when the Z-Move is chosen, even if
    -- sleep or paralysis then stops the Pokemon from moving
    st.used = true
    if info.status then
      -- a status Z-Move stays the move it is; only its bonus is new
      st.pending = { inst = action, baseId = action.id, status = info.status,
                     executed = false }
      pcall(function()
        battle:sayAuto(tostring(battle.player.name)
          .. "\nsurrounded itself\nwith its Z-Power!", 40)
      end)
      return
    end
    st.pending = { inst = action, baseId = action.id, zId = info.z.id,
                   power = info.power, def = info.def, anim = animFor(info.z),
                   boost = info.boost, executed = false }
    action.id = info.z.id
    pcall(function()
      battle:sayAuto(tostring(battle.player.name)
        .. "\nunleashes its\nfull-force Z-Move!", 40)
    end)
  end)

  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local st = battle and battles[battle]
    local f = st and st.foe
    if f and not f.executed and not ev.isCalled and ev.user == battle.enemy
        and ev.move and ev.move.id == f.zId then
      f.executed = true
      st.foeUsed = true  -- spent only once it actually fires
      if f.inst.id == f.zId then f.inst.id = f.baseId end
      local row = battle.moveAnimRow
      if f.anim and type(row) == "table" and row.anim == f.zId then row.anim = f.anim end
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
        applyStatus(battle, p.status)
      end
      return
    end
    if ev.move.id ~= p.zId then return end
    p.executed = true
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
        battle:sayNext(tostring(player.name)
          .. "\nboosted its stats\nwith its Z-Power!")
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

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    finish(battle, battle and battles[battle])
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local st = ev and ev.battle and battles[ev.battle]
    if st then st.armed = false end
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

  -- hold the start, step one letter at a time, hold the end, repeat
  local HOLD, STEP = 50, 9
  local function window(text, width, since)
    if #text <= width then return text end
    local over = #text - width
    local cycle = HOLD + over * STEP + HOLD
    local t = (tick - since) % cycle
    local shift = t < HOLD and 0 or math.min(over, math.floor((t - HOLD) / STEP) + 1)
    return text:sub(shift + 1, shift + width)
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
    local room = COLS - 2 - (#right > 0 and #right + 1 or 0)
    -- restart the scroll whenever the text changes (another move highlighted)
    if st.barText ~= left then st.barText, st.barSince = left, tick end
    Font.draw("Z:" .. window(left, room, st.barSince), x, BAR_Y + 4)
    if #right > 0 then Font.draw(right, x + w - Font.width(right), BAR_Y + 4) end
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
    elseif phase == "moveSelect" and not wide and available(battle, st) then
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
    mod.ui.insertBefore(rows, "STATS", {
      label = "Z-CRYSTAL",
      onSelect = function(selected, g) openCrystals(selected or mon, g or game) end,
    })
    return rows
  end)

  -- ------- "got a crystal" messages
  -- Which crystals have been announced is kept with the save, so a message
  -- missed to a crash or a reset (Lance is followed straight by the
  -- Champion, the Hall of Fame and the credits) still shows later.  It is
  -- shown through the overworld's own script queue, which waits for warps,
  -- cutscenes and scripted walks to finish before it runs anything.

  local LABEL, ORDER = {}, {}
  for i, row in ipairs(TYPES) do LABEL[row.key], ORDER[row.key] = row.crystal, i end
  for i, row in ipairs(EXCLUSIVE) do
    LABEL[row.key], ORDER[row.key] = row.crystal, 100 + i
  end

  local RING_TEXT = "_ZMovesGotZRingText"
  local function gotText(key) return "_ZMovesGot" .. key .. "Text" end
  -- registered text, so a translation mod can override it
  pcall(function()
    mod.content.text:register(RING_TEXT, "{PLAYER} got a\nZ-RING!")
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
    if not storyMode() then return end
    local save = mod.game and mod.game.save
    if not save then return end
    local seen = announced(save)
    local rows, keys = {}, {}
    if hasRing(save) and not seen.RING then
      rows[#rows + 1] = { "show_text", RING_TEXT }
    end
    for key in pairs(UNLOCK) do
      if Z[key] and not seen[key] and unlocked(save, key) then
        keys[#keys + 1] = key
      end
    end
    table.sort(keys, function(a, b) return ORDER[a] < ORDER[b] end)
    for _, key in ipairs(keys) do
      rows[#rows + 1] = { "show_text", gotText(key) }
    end
    if #rows == 0 then return end
    local ow = overworld()
    if not (ow and ow.queueScript) then return end
    -- marked only once the message is actually on its way
    if hasRing(save) then seen.RING = true end
    for _, key in ipairs(keys) do seen[key] = true end
    mod.save:set("announced", seen)
    ow:queueScript(rows)
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
    local st = battle and battles[battle]
    return { armed = st and st.armed or false, used = st and st.used or false,
             foeUsed = st and st.foeUsed or false }
  end
end
