-- Z-Moves for Gen1Recomp: Gold, Silver and Crystal.
--
-- Loaded by main.lua when the running game is Gen 2.  Same rules, same
-- crystals-on-the-Pokemon design and the same public mod API as the Gen 1
-- half; only what Gen 2 does differently is done differently here:
--
--   * A Gen 2 turn is resolved in one call (battle:takeTurn) that returns the
--     whole turn as a list of events the battle screen then plays.  So the
--     player's Z-Move is set up at the start of that call -- the chosen move
--     slot is pointed at the Z-Move record for the length of the turn and
--     pointed back when it returns -- instead of at battle.turn_started.
--     The wrapper is an instance field on that one battle, removed with it.
--   * Trainers answer battle.enemy_action with the Z-Move's id directly.
--   * Lines are message events slotted in front of "X used Y!", and the
--     Z-Move animations are chains of the game's own Gen 2 animation scripts.
--   * Crystals are still a data-only field on the saved Pokemon, separate
--     from its held item, so a Pokemon can hold both.

local FIELD = "zCrystal"
local PREFIX = "ZMOVE_"

return function(mod)
  -- ------- types: the 17 Gen 2 types, Dark and Steel included

  -- key: type id without the disassembly's "_TYPE" suffix (PSYCHIC_TYPE)
  -- anim: a vanilla move of the type; its animation is the fallback one
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
    { key = "GHOST",    crystal = "GHOSTIUM Z",   name = { "NEVER-ENDING", "NIGHTMARE" }, anim = "SHADOW_BALL" },
    { key = "DRAGON",   crystal = "DRAGONIUM Z",  name = { "DEVASTATING", "DRAKE" },      anim = "OUTRAGE" },
    { key = "DARK",     crystal = "DARKINIUM Z",  name = { "BLACK HOLE", "ECLIPSE" },     anim = "CRUNCH" },
    { key = "STEEL",    crystal = "STEELIUM Z",   name = { "CORKSCREW", "CRASH" },        anim = "IRON_TAIL" },
  }

  local function typeKey(typeId)
    return (tostring(typeId or ""):gsub("_TYPE$", ""))
  end

  -- ------- battle and field text
  -- Registered as ROM text (Gen 2's label-keyed text bank), so a translation
  -- mod can override every line.  {USER} is filled by the battle's own
  -- formatter, the same way it fills the game's own lines.

  local TEXT = {
    _ZMovesUnleashText = "{USER}\nunleashes its\vfull-force Z-Move!{PROMPT}",
    _ZMovesAuraText = "{USER}\nsurrounded itself\vwith its Z-Power!{PROMPT}",
    _ZMovesBoostText = "{USER}\nboosted {STAT}\vwith its Z-Power!{PROMPT}",
    _ZMovesBoostAllText = "{USER}\nboosted its stats\vwith its Z-Power!{PROMPT}",
    _ZMovesResetText = "{USER}\nreset its stats\vwith its Z-Power!{PROMPT}",
    _ZMovesHealText = "{USER}\nrestored its HP\vwith its Z-Power!{PROMPT}",
    _ZMovesCritText = "{USER}\nis getting pumped\vby its Z-Power!{PROMPT}",
    _ZMovesWarningText = "{TRAINER} wears\na Z-RING!{PROMPT}",
  }
  pcall(function()
    for id, text in pairs(TEXT) do mod.content.rom_text:register(id, text) end
  end)

  local function strip(text)
    return (tostring(text):gsub("{PROMPT}", ""):gsub("{DONE}", ""))
  end

  -- the line with our own slots filled; any slot a translation added that we
  -- do not know stays visible instead of stopping the game
  local function line(data, id, slots)
    local text = data and data.text and data.text[id]
    if type(text) ~= "string" then text = TEXT[id] or id end
    return strip(text:gsub("{(%u+)}", function(slot)
      local value = slots and slots[slot]
      if value ~= nil then return tostring(value) end
    end))
  end

  -- "Enemy STARMIE" / "TOTODILE", the way the battle names each side
  local function actorName(battle, mon)
    local ok, name = pcall(function() return battle:battlerName(mon) end)
    if ok and type(name) == "string" then return name end
    return tostring(mon and (mon.nickname or mon.species) or "")
  end

  local function battleLine(battle, id, mon, slots)
    slots = slots or {}
    slots.USER = slots.USER or actorName(battle, mon)
    return line(battle.data, id, slots)
  end

  -- a message the battle box shows just before "X used Y!": that event is
  -- the last one queued when battle.move_used fires
  local function sayBeforeUse(battle, text)
    local events, moveEvent = battle.events, battle.moveEvent
    local at
    for i = #(events or {}), 1, -1 do
      if events[i] == moveEvent then at = i break end
    end
    local event = { kind = "message", text = text }
    if at then table.insert(events, at, event) else battle:emit(event) end
  end

  local function say(battle, text)
    battle:emit({ kind = "message", text = text })
  end

  -- ------- Z-Move power (Sun/Moon table, read off the base move)

  local BRACKETS = {
    { 55, 100 }, { 65, 120 }, { 75, 140 }, { 85, 160 }, { 95, 175 },
    { 100, 180 }, { 110, 185 }, { 125, 190 }, { 130, 195 },
  }
  -- moves whose printed power is not what they hit with
  local EFFECT_POWER = {
    EFFECT_OHKO = 180,            -- Fissure, Guillotine, Horn Drill
    EFFECT_LEVEL_DAMAGE = 100,    -- Seismic Toss, Night Shade
    EFFECT_STATIC_DAMAGE = 100,   -- Sonicboom, Dragon Rage
    EFFECT_PSYWAVE = 100,
    EFFECT_SUPER_FANG = 100,
    EFFECT_COUNTER = 100,
    EFFECT_MIRROR_COAT = 100,
    EFFECT_BIDE = 100,
    EFFECT_MAGNITUDE = 140,
    EFFECT_RETURN = 160,
    EFFECT_FRUSTRATION = 160,
    EFFECT_REVERSAL = 160,        -- Flail, Reversal
    EFFECT_PRESENT = 100,
    EFFECT_HIDDEN_POWER = 120,
    EFFECT_ROLLOUT = 100,
    EFFECT_FURY_CUTTER = 100,
    EFFECT_TRIPLE_KICK = 120,
    EFFECT_BEAT_UP = 100,
  }
  local ID_POWER = { MEGA_DRAIN = 120 }
  -- status moves of a damaging-looking shape that have no Z-Move at all
  local NO_Z = { STRUGGLE = true }

  -- nil for status moves: they have no damaging Z-Move
  local function zPower(def)
    if type(def) ~= "table" or NO_Z[def.id] then return nil end
    local fixed = ID_POWER[def.id] or EFFECT_POWER[def.effect]
    if fixed then return fixed end
    local power = tonumber(def.power) or 0
    if power <= 1 then return nil end
    for _, row in ipairs(BRACKETS) do
      if power <= row[1] then return row[2] end
    end
    return 200
  end

  -- ------- status Z-Moves: the bonus Sun/Moon gives before the move runs
  -- { stat, stages }, "reset" (lowered stats back to 0), "heal" (full HP),
  -- "all" (every battle stat +1) or "crit" (critical-hit ratio up).
  -- Gen 2 splits SPECIAL, so the Sun/Moon Sp. Atk / Sp. Def values apply.

  local Z_STATUS = {
    -- moves from Red/Blue/Yellow
    SWORDS_DANCE = "reset", WHIRLWIND = { "specialDefense", 1 },
    SAND_ATTACK = { "evasion", 1 }, TAIL_WHIP = { "attack", 1 },
    LEER = { "attack", 1 }, GROWL = { "defense", 1 }, ROAR = { "defense", 1 },
    SING = { "speed", 1 }, SUPERSONIC = { "speed", 1 }, DISABLE = "reset",
    MIST = "heal", LEECH_SEED = "reset", GROWTH = { "specialAttack", 1 },
    POISONPOWDER = { "defense", 1 }, STUN_SPORE = { "specialDefense", 1 },
    SLEEP_POWDER = { "speed", 1 }, STRING_SHOT = { "speed", 1 },
    THUNDER_WAVE = { "specialDefense", 1 }, TOXIC = { "defense", 1 },
    HYPNOSIS = { "speed", 1 }, MEDITATE = { "attack", 1 }, AGILITY = "reset",
    TELEPORT = "heal", MIMIC = { "accuracy", 1 }, SCREECH = { "attack", 1 },
    DOUBLE_TEAM = "reset", RECOVER = "reset", HARDEN = { "defense", 1 },
    MINIMIZE = "reset", SMOKESCREEN = { "evasion", 1 },
    CONFUSE_RAY = { "specialAttack", 1 }, WITHDRAW = { "defense", 1 },
    DEFENSE_CURL = { "accuracy", 1 }, BARRIER = "reset",
    LIGHT_SCREEN = { "specialDefense", 1 }, HAZE = "heal",
    REFLECT = { "defense", 1 }, FOCUS_ENERGY = { "accuracy", 1 },
    MIRROR_MOVE = { "attack", 2 }, AMNESIA = "reset", KINESIS = { "evasion", 1 },
    SOFTBOILED = "reset", GLARE = { "specialDefense", 1 },
    POISON_GAS = { "defense", 1 }, LOVELY_KISS = { "speed", 1 },
    TRANSFORM = "heal", SPORE = "reset", FLASH = { "evasion", 1 },
    SPLASH = { "attack", 3 }, ACID_ARMOR = "reset", REST = "reset",
    SHARPEN = { "attack", 1 }, CONVERSION = "all", SUBSTITUTE = "reset",
    -- moves new in Gold, Silver and Crystal
    SKETCH = "all", SPIDER_WEB = { "defense", 1 },
    MIND_READER = { "specialAttack", 1 }, NIGHTMARE = { "specialAttack", 1 },
    CONVERSION2 = "heal", COTTON_SPORE = "reset", SPITE = "heal",
    PROTECT = "reset", SCARY_FACE = { "speed", 1 }, BELLY_DRUM = "heal",
    SWEET_KISS = { "specialAttack", 1 }, SPIKES = { "defense", 1 },
    FORESIGHT = "crit", PERISH_SONG = "reset", SANDSTORM = { "speed", 1 },
    ENDURE = "reset", CHARM = { "defense", 1 }, SWAGGER = "reset",
    MILK_DRINK = "reset", MEAN_LOOK = { "specialDefense", 1 },
    ATTRACT = "reset", SLEEP_TALK = "crit", HEAL_BELL = "heal",
    SAFEGUARD = { "speed", 1 }, PAIN_SPLIT = { "defense", 1 },
    BATON_PASS = "reset", ENCORE = { "speed", 1 }, SWEET_SCENT = { "evasion", 1 },
    MORNING_SUN = "reset", SYNTHESIS = "reset", MOONLIGHT = "reset",
    RAIN_DANCE = { "speed", 1 }, SUNNY_DAY = { "speed", 1 },
    PSYCH_UP = "heal", LOCK_ON = { "speed", 1 }, DETECT = { "evasion", 1 },
  }
  local STATS = { "attack", "defense", "speed", "specialAttack",
                  "specialDefense", "accuracy", "evasion" }

  local function zStatus(def)
    if type(def) ~= "table" or zPower(def) then return nil end
    return Z_STATUS[def.id]
  end

  local function statLabel(battle, stat)
    -- the game's own stat names (StatNames), else ours
    local labels = { attack = "StatNames#1", defense = "StatNames#2",
      speed = "StatNames#3", specialAttack = "StatNames#4",
      specialDefense = "StatNames#5", accuracy = "StatNames#6",
      evasion = "StatNames#7" }
    local text = battle.data and battle.data.text and battle.data.text[labels[stat]]
    if type(text) == "string" and text ~= "" then return strip(text) end
    local fallback = { attack = "ATTACK", defense = "DEFENSE", speed = "SPEED",
      specialAttack = "SPCL.ATK", specialDefense = "SPCL.DEF",
      accuracy = "ACCURACY", evasion = "EVASION" }
    return fallback[stat] or stat:upper()
  end

  local function stagesOf(battle, mon)
    local side = battle:sideOf(mon)
    battle.stages = battle.stages or {}
    battle.stages[side] = battle.stages[side] or {}
    return battle.stages[side]
  end

  local function raise(stages, stat, by)
    stages[stat] = math.min(6, (stages[stat] or 0) + by)
  end

  local function applyStatus(battle, mon, effect)
    local stages = stagesOf(battle, mon)
    if effect == "reset" then
      for _, s in ipairs(STATS) do
        if (stages[s] or 0) < 0 then stages[s] = 0 end
      end
      say(battle, battleLine(battle, "_ZMovesResetText", mon))
    elseif effect == "heal" then
      say(battle, battleLine(battle, "_ZMovesHealText", mon))
      local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp
      -- the heal event slides the bar up the way RECOVER's does
      battle:heal(mon, (maxHp or 0) - (mon.hp or 0))
    elseif effect == "all" then
      for i = 1, 5 do raise(stages, STATS[i], 1) end
      say(battle, battleLine(battle, "_ZMovesBoostAllText", mon))
    elseif effect == "crit" then
      local state = battle:volatile(mon)
      state.focusEnergy = true
      say(battle, battleLine(battle, "_ZMovesCritText", mon))
    else
      raise(stages, effect[1], effect[2])
      say(battle, battleLine(battle, "_ZMovesBoostText", mon,
        { STAT = statLabel(battle, effect[1]) }))
    end
  end

  -- ------- content: one Z-Move record per type the game has

  local Z = {}  -- key -> { id, crystal, name = { .. }, anim, ... }
  for _, row in ipairs(TYPES) do
    local sample = mod.content.moves:get(row.anim)
    if sample and typeKey(sample.type) == row.key then
      local id = PREFIX .. row.key
      local ok, err = pcall(function()
        mod.content.moves:register(id, {
          id = id,
          -- "used " leaves 13 columns on its line, so the name carries its
          -- own break, as on Red and Blue
          name = row.name[1] .. "\n" .. row.name[2],
          type = sample.type,
          power = 100,        -- placeholder; battle.damage sets the real one
          accuracy = 100,
          pp = 1,
          effect = "EFFECT_NORMAL_HIT",
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

  -- ------- species-exclusive Z-Moves (the four Sun/Moon has for Pokemon of
  -- the first two generations).  Missing base moves have a stand-in; the real
  -- one wins if another mod adds it.

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
    -- Extreme Evoboost is +2 to every stat and no attack.  The record carries
    -- Swords Dance's effect, so the engine raises ATTACK itself and says so;
    -- the other four stats are raised here.
    { key = "EEVIUM", crystal = "EEVIUM Z", species = "EEVEE",
      bases = { "LAST_RESORT", "TAKE_DOWN" }, name = { "EXTREME", "EVOBOOST" },
      boost = { "defense", "speed", "specialAttack", "specialDefense" },
      anim = "SWORDS_DANCE" },
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
          effect = row.boost and "EFFECT_ATTACK_UP_2" or "EFFECT_NORMAL_HIT",
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
  -- Gen 2's animations are the cart's own scripts (rows of anim commands,
  -- keyed by ROM address).  Each Z-Move gets a chain built at load from the
  -- scripts the imported game already has, nothing from the ROM ships with
  -- the mod: FOCUS ENERGY's Z-Power charge-up on the user, two signature
  -- moves of the type, then a screen-shake-and-flash finish.  Every script
  -- in a chain is copied with its end turned into a jump to the next one,
  -- so sub-scripts it calls are still shared and nothing in the pool is
  -- changed.  A Z-Move whose pieces are all missing borrows one animation.

  local SIGNATURE = {
    NORMAL   = { "EXTREMESPEED", "HYPER_BEAM" },
    FIRE     = { "FLAMETHROWER", "FIRE_BLAST" },
    WATER    = { "WHIRLPOOL", "HYDRO_PUMP" },
    ELECTRIC = { "THUNDERBOLT", "ZAP_CANNON" },
    GRASS    = { "PETAL_DANCE", "SOLARBEAM" },
    ICE      = { "ICY_WIND", "BLIZZARD" },
    FIGHTING = { "DYNAMICPUNCH", "CROSS_CHOP" },
    POISON   = { "ACID", "SLUDGE_BOMB" },
    GROUND   = { "MAGNITUDE", "EARTHQUAKE" },
    FLYING   = { "WING_ATTACK", "SKY_ATTACK" },
    PSYCHIC  = { "PSYBEAM", "PSYCHIC_M" },
    BUG      = { "FURY_CUTTER", "MEGAHORN" },
    ROCK     = { "ANCIENTPOWER", "ROCK_SLIDE" },
    GHOST    = { "SHADOW_BALL", "NIGHT_SHADE" },
    DRAGON   = { "TWISTER", "OUTRAGE" },
    DARK     = { "FAINT_ATTACK", "CRUNCH" },
    STEEL    = { "METAL_CLAW", "IRON_TAIL" },
    PIKANIUM = { "QUICK_ATTACK", "THUNDERBOLT", "THUNDER" },
    SNORLIUM = { "BODY_SLAM", "EARTHQUAKE" },
    MEWNIUM  = { "PSYCHIC_M", "HYPER_BEAM" },
    EEVIUM   = { "GROWTH", "SWORDS_DANCE", "AGILITY" },
  }
  local INTRO, FINISH = "FOCUS_ENERGY", "EXPLOSION"
  -- the commands whose target is another script, and where it sits
  local BRANCH_AT = {
    jumpuntil = 2, if_param_and = 3, if_param_equal = 3, if_var_equal = 3,
    jump = 2, loop = 3,
  }
  local KEY_PREFIX = "zmoves:"

  local function animTable(name)
    local ok, t = pcall(function() return mod.content.battle_anims:get(name) end)
    return ok and type(t) == "table" and t or nil
  end

  local function copyRow(row)
    local out = {}
    for i, v in ipairs(row) do out[i] = v end
    return out
  end

  local function buildChains()
    local scripts, moves = animTable("scripts"), animTable("moves")
    if not (scripts and moves) then return {}, {} end
    local newScripts, entries = {}, {}

    -- copy one script and everything it jumps or loops to; its end becomes
    -- a jump to `nextKey`.  Calls stay calls into the shared pool.
    local function clone(entry, prefix, nextKey)
      local map, queue = {}, {}
      local function keyFor(k)
        if not map[k] then
          map[k] = prefix .. k
          queue[#queue + 1] = k
        end
        return map[k]
      end
      local first = keyFor(entry)
      local i = 1
      while queue[i] do
        local k = queue[i]
        i = i + 1
        local out = {}
        local ended = false
        for _, row in ipairs(scripts[k] or {}) do
          local cmd = row[1]
          if cmd == "ret" then
            out[#out + 1] = { "jump", nextKey }
            ended = true
            break
          end
          local copied = copyRow(row)
          local at = BRANCH_AT[cmd]
          if at and type(copied[at]) == "string" then
            copied[at] = keyFor(copied[at])
          end
          out[#out + 1] = copied
          if cmd == "jump" then ended = true break end
        end
        if not ended then out[#out + 1] = { "jump", nextKey } end
        newScripts[map[k]] = out
      end
      return first
    end

    -- the finish: the shake and the flash EXPLOSION opens with, and its
    -- sound (the first one it reaches, sub-scripts included)
    local function finisherRows()
      local entry = moves[FINISH]
      local rows = {}
      local seen, sound = {}, nil
      local function find(k, depth)
        if seen[k] or depth > 4 or sound then return end
        seen[k] = true
        for _, row in ipairs(scripts[k] or {}) do
          if row[1] == "sound" and not sound then sound = copyRow(row) end
          if row[1] == "call" or BRANCH_AT[row[1]] then
            find(row[BRANCH_AT[row[1]] or 2], depth + 1)
          end
        end
      end
      if entry and scripts[entry] then
        for _, row in ipairs(scripts[entry]) do
          if row[1] == "bgeffect" and #rows < 2 then rows[#rows + 1] = copyRow(row) end
          if row[1] == "call" or row[1] == "ret" then break end
        end
        find(entry, 0)
      end
      if sound then table.insert(rows, 1, sound) end
      rows[#rows + 1] = { "wait", 40 }
      rows[#rows + 1] = { "ret" }
      return rows
    end

    for key, z in pairs(Z) do
      local parts = {}
      for _, id in ipairs(SIGNATURE[key] or {}) do
        if moves[id] and scripts[moves[id]] then parts[#parts + 1] = moves[id] end
      end
      if #parts > 0 then
        local base = KEY_PREFIX .. key .. ":"
        local endKey = base .. "end"
        newScripts[endKey] = z.boost and { { "wait", 16 }, { "ret" } }
          or finisherRows()
        -- built back to front, so each piece knows where it goes next
        local nextKey = endKey
        for i = #parts, 1, -1 do
          local glue = base .. "glue" .. i
          newScripts[glue] = { { "clearobjs" }, { "wait", 4 },
                               { "jump", nextKey } }
          nextKey = clone(parts[i], base .. i .. ":", glue)
        end
        local intro = moves[INTRO]
        if intro and scripts[intro] then
          local glue = base .. "glue0"
          newScripts[glue] = { { "clearobjs" }, { "wait", 4 }, { "jump", nextKey } }
          nextKey = clone(intro, base .. "0:", glue)
        end
        entries[z.id] = nextKey
      elseif moves[z.anim] then
        entries[z.id] = moves[z.anim]
      end
    end
    return newScripts, entries
  end

  do
    local ok, err = pcall(function()
      local newScripts, entries = buildChains()
      if next(newScripts) then mod.content.battle_anims:patch("scripts", newScripts) end
      if next(entries) then mod.content.battle_anims:patch("moves", entries) end
      for key, z in pairs(Z) do
        if entries[z.id] and tostring(entries[z.id]):sub(1, #KEY_PREFIX) == KEY_PREFIX then
          z.ownAnim = true
        end
      end
    end)
    if not ok then mod.log:warn("Z-Move animations not built: %s", tostring(err)) end
  end

  -- the move id whose animation plays: our own chain, or the type's sample
  local function animFor(z)
    if z.ownAnim and mod.options:get("animations") ~= false then return z.id end
    return z.anim
  end

  -- ------- options

  mod.options:define({
    { key = "crystals", label = "Z-CRYSTALS", type = "choice", default = "story",
      choices = { { "STORY", "story" }, { "ALL", "all" } },
      description = "STORY: earn the Z-RING and each crystal as you play. "
        .. "ALL: every crystal from the start." },
    { key = "trainers", label = "TRAINER Z-MOVES", type = "toggle", default = true,
      description = "Gym Leaders, the Elite Four, the Champion, RED and your "
        .. "rival (from the Goldenrod Underground on) use one Z-Move per battle." },
    { key = "warnings", label = "Z-RING WARNING", type = "toggle", default = true,
      description = "Says when a trainer with a Z-RING starts a battle. "
        .. "Never says which POKeMON or move." },
    { key = "animations", label = "Z-MOVE ANIMATIONS", type = "toggle", default = true,
      description = "ON: every Z-Move plays its own full animation. "
        .. "OFF: one vanilla animation of its type." },
  })

  -- ------- earning the crystals
  -- STORY: the Z-Ring comes with your first Pokemon from PROF.ELM, each
  -- crystal with a story milestone.  ALL: every crystal from the start.
  -- Read from the game's own event flags, so a save already past a
  -- milestone has its crystal at once.

  local RING = { "EVENT_GOT_A_POKEMON_FROM_ELM" }
  local UNLOCK = {
    FLYING   = { "EVENT_BEAT_FALKNER" },
    BUG      = { "EVENT_BEAT_BUGSY" },
    NORMAL   = { "EVENT_BEAT_WHITNEY" },
    EEVIUM   = { "EVENT_GOT_EEVEE" },
    ROCK     = { "EVENT_FOUGHT_SUDOWOODO" },
    GRASS    = { "EVENT_HERDED_FARFETCHD" },
    GHOST    = { "EVENT_BEAT_MORTY" },
    PSYCHIC  = { all = { "EVENT_BEAT_KIMONO_GIRL_NAOKO", "EVENT_BEAT_KIMONO_GIRL_SAYO",
                         "EVENT_BEAT_KIMONO_GIRL_ZUKI", "EVENT_BEAT_KIMONO_GIRL_KUNI",
                         "EVENT_BEAT_KIMONO_GIRL_MIKI" } },
    FIRE     = { "EVENT_RELEASED_THE_BEASTS" },
    FIGHTING = { "EVENT_BEAT_CHUCK" },
    ELECTRIC = { "EVENT_JASMINE_RETURNED_TO_GYM" },
    STEEL    = { "EVENT_BEAT_JASMINE" },
    WATER    = { "EVENT_LAKE_OF_RAGE_RED_GYARADOS" },
    POISON   = { "EVENT_CLEARED_ROCKET_HIDEOUT" },
    ICE      = { "EVENT_BEAT_PRYCE" },
    DARK     = { "EVENT_CLEARED_RADIO_TOWER" },
    DRAGON   = { "EVENT_BEAT_CLAIR" },
    GROUND   = { "EVENT_SOLVED_KABUTO_PUZZLE" },
    PIKANIUM = { "EVENT_BEAT_LTSURGE" },
    SNORLIUM = { "EVENT_FOUGHT_SNORLAX" },
    -- no event flag stays set for beating RED, so the mod keeps its own
    MEWNIUM  = { won = "RED" },
  }

  local function storyMode()
    return mod.options:get("crystals") ~= "all"
  end

  local flagIndexMemo = setmetatable({}, { __mode = "k" })
  local function flagIndex(data, name)
    local constants = data and data.gen2Constants
    local order = constants and constants.eventFlagOrder
    if type(order) ~= "table" then return nil end
    local map = flagIndexMemo[order]
    if not map then
      map = {}
      for i, flag in pairs(order) do
        if type(i) == "number" and type(flag) == "string" then map[flag] = i - 1 end
      end
      flagIndexMemo[order] = map
    end
    return map[name]
  end

  -- the live world's flags while a game is running (they reach the save only
  -- when it is written), else the save's own bytes
  local function flagSet(game, name)
    local data = game and game.data
    local n = flagIndex(data, name)
    if not n then return false end
    local ok, live = pcall(function() return mod.world:getFlag(n) end)
    if ok and type(live) == "boolean" then return live end
    local save = game and game.save
    local bytes = type(save) == "table" and save.events
    if type(bytes) ~= "table" then return false end
    local row = tonumber(bytes[math.floor(n / 8)] or bytes[tostring(math.floor(n / 8))]) or 0
    return math.floor(row / (2 ^ (n % 8))) % 2 == 1
  end

  local function wins()
    local w = mod.save:get("wins")
    return type(w) == "table" and w or {}
  end

  local function met(game, rule)
    if type(rule) ~= "table" then return false end
    if rule.won then return wins()[rule.won] == true end
    if rule.all then
      for _, name in ipairs(rule.all) do
        if not flagSet(game, name) then return false end
      end
      return #rule.all > 0
    end
    for _, name in ipairs(rule) do
      if flagSet(game, name) then return true end
    end
    return false
  end

  local function hasRing(game)
    return not storyMode() or met(game, RING)
  end

  local function unlocked(game, key)
    if not storyMode() then return true end
    return met(game, UNLOCK[key])
  end

  -- ------- which battle objects are ours
  -- Gen 2 has two: the battle itself (events and battle hooks carry it) and
  -- the battle screen (battle.overlay, the menus).  State is keyed by the
  -- battle; the screen is only ever read.

  local function isBattle(b)
    return type(b) == "table" and type(b.takeTurn) == "function"
      and type(b.party) == "table" and b.sides ~= nil
  end

  local function screenOf(state)
    if type(state) == "table" and type(state.battle) == "table"
        and (state.isGen2BattleState or state.screenId == "Gen2BattleState") then
      return state
    end
  end

  local function topScreen(game)
    local stack = game and game.stack
    local states = stack and stack.states
    return screenOf(states and states[#states])
  end

  local function plainBattle(battle)
    if battle.linkBattle or battle.inBattleTowerBattle then return false end
    local bt = battle.battleType
    if bt ~= nil and (bt == battle.BATTLETYPE_TUTORIAL or bt == battle.BATTLETYPE_CONTEST) then
      return false
    end
    return true
  end

  -- per-battle state

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

  local installTurn  -- below

  local function stateFor(battle)
    if not isBattle(battle) or not plainBattle(battle) then return nil end
    local st = battles[battle]
    if not st then
      st = { used = tokenSet(battle, 1), armed = false, pending = nil,
             notice = nil, foe = nil, foeUsed = tokenSet(battle, 2),
             foePlan = nil }
      battles[battle] = st
      installTurn(battle)
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

  -- point a borrowed move slot back at its real move, and make sure nothing
  -- remembers the Z-Move's id as the last move used (Mirror Move, Encore,
  -- Disable and the AI's move memory read those)
  local function forget(battle, mon, zId, baseId)
    if type(mon) ~= "table" then return end
    local state = mon.volatile
    if type(state) ~= "table" then return end
    if state.lastMove == zId then state.lastMove = baseId end
    if state.lastMoveKept == zId then state.lastMoveKept = baseId end
    if state.encore == zId then state.encore = baseId end
    if type(state.usedMoves) == "table" then
      for i, id in ipairs(state.usedMoves) do
        if id == zId then state.usedMoves[i] = baseId end
      end
    end
  end

  local function restore(battle, st)
    for _, key in ipairs({ "pending", "foe" }) do
      local p = st and st[key]
      if p and p.zId then
        if p.inst and p.inst.id == p.zId then p.inst.id = p.baseId end
        forget(battle, p.mon, p.zId, p.baseId)
      end
    end
  end

  local function finish(battle, st)
    if not st then return end
    restore(battle, st)
    st.pending, st.foe, st.foePlan = nil, nil, nil
  end

  -- ------- what a move slot would become

  local function moveDef(battle, id)
    local moves = battle and battle.data and battle.data.moves
    return moves and moves[id]
  end

  local function zInfo(battle, inst)
    local mon = battle.player
    local crystal = mon and mon[FIELD]
    local z = crystal and Z[crystal]
    if not z then return nil, "crystal" end
    local game = mod.game
    if not hasRing(game) or not unlocked(game, crystal) then
      return nil, "crystal"
    end
    local def = type(inst) == "table" and moveDef(battle, inst.id)
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

  local function disabled(battle, mon, id)
    local ok, yes = pcall(function() return battle:moveDisabled(mon, id) end)
    return ok and yes == true
  end

  local function usable(battle, slot)
    local mon = battle.player
    local inst = mon and mon.moves and mon.moves[slot]
    if not inst or (inst.pp or 0) <= 0 or disabled(battle, mon, inst.id) then
      return nil
    end
    return zInfo(battle, inst)
  end

  -- true, or false plus the line to show the player
  local function available(battle, st)
    if st.used then return false, "ALREADY USED" end
    if not hasRing(mod.game) then return false, "NO Z-RING YET" end
    local mon = battle.player
    if not (mon and Z[mon[FIELD] or ""]) then
      return false, "NO CRYSTAL HELD"
    end
    for slot = 1, #(mon.moves or {}) do
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

  -- ------- the player's Z-Move: set up for the length of one turn

  installTurn = function(battle)
    if rawget(battle, "takeTurn") ~= nil then return end
    local wrapper
    -- the battle's own takeTurn, looked up on every call so a mod that wraps
    -- the class later is still run
    local function classTakeTurn(self, action)
      rawset(self, "takeTurn", nil)
      local ok, events = pcall(self.takeTurn, self, action)
      if battles[self] and rawget(self, "takeTurn") == nil then
        rawset(self, "takeTurn", wrapper)
      end
      if not ok then error(events, 0) end
      return events
    end
    wrapper = function(self, action)
      local st = battles[self]
      local armed = st and st.armed
      if st then st.armed = false end
      local swapped
      if armed and not st.used and type(action) == "table"
          and action.kind == "move" then
        local mon = self.player
        local inst
        for _, m in ipairs((mon and mon.moves) or {}) do
          if m.id == action.move then inst = m break end
        end
        local info = inst and zInfo(self, inst)
        if info and info.status then
          -- a status Z-Move stays the move it is; only its bonus is new
          st.pending = { inst = inst, mon = mon, baseId = inst.id,
                         status = info.status, key = info.z.key, executed = false }
        elseif info then
          st.pending = { inst = inst, mon = mon, baseId = inst.id, zId = info.z.id,
                         key = info.z.key, power = info.power, def = info.def,
                         anim = animFor(info.z), boost = info.boost,
                         executed = false }
          -- the menu's own slot: the turn's PP comes off the real move
          inst.id = info.z.id
          swapped = st.pending
          local copy = {}
          for k, v in pairs(action) do copy[k] = v end
          copy.move = info.z.id
          action = copy
        end
      end
      local ok, events = pcall(classTakeTurn, self, action)
      if swapped and swapped.inst.id == swapped.zId then
        swapped.inst.id = swapped.baseId
      end
      if st then finish(self, st) end
      if not ok then error(events, 0) end
      return events
    end
    rawset(battle, "takeTurn", wrapper)
  end

  -- ------- trainers with Z-Power
  -- Gym Leaders, the Elite Four, the Champion, RED and the rival hold a
  -- crystal on their last Pokemon.  The crystal is their own type when that
  -- Pokemon knows a damaging move of it, else the type of its strongest
  -- damaging move.  It fires the first turn it can, once.

  local LEADERS = {
    FALKNER = "FLYING", BUGSY = "BUG", WHITNEY = "NORMAL", MORTY = "GHOST",
    CHUCK = "FIGHTING", JASMINE = "STEEL", PRYCE = "ICE", CLAIR = "DRAGON",
    WILL = "PSYCHIC", KOGA = "POISON", BRUNO = "FIGHTING", KAREN = "DARK",
    CHAMPION = "DRAGON",
    BROCK = "ROCK", MISTY = "WATER", LT_SURGE = "ELECTRIC", ERIKA = "GRASS",
    JANINE = "POISON", SABRINA = "PSYCHIC", BLAINE = "FIRE",
    BLUE = true, RED = true, RIVAL2 = true,
  }
  -- the Johto rival joins in from the Goldenrod Underground on: his last
  -- Pokemon is 32 there and 22 at most in every earlier fight
  local RIVAL_FROM_LEVEL = 30

  local function trainerClass(battle)
    local t = battle.trainer
    return t and (t.classId or t.class) or nil
  end

  local function zTrainer(battle)
    if mod.options:get("trainers") == false then return nil end
    if battle.wild or not battle.trainer or not plainBattle(battle) then return nil end
    local class = trainerClass(battle)
    local own = LEADERS[class]
    if own then return own end
    local party = battle.enemyParty
    local ace = type(party) == "table" and party[#party]
    if class == "RIVAL1" and type(ace) == "table"
        and (tonumber(ace.level) or 0) >= RIVAL_FROM_LEVEL then
      return true
    end
    return nil
  end

  local function locked(battle, mon)
    local state = type(mon) == "table" and mon.volatile or {}
    if state.recharge or state.chargeMove or state.rampageMove
        or state.rolloutLock or state.bideTurns or state.encore then
      return true
    end
    local ok, forced = pcall(function() return battle:forcedMove(mon) end)
    return ok and forced ~= nil and forced ~= false
  end

  local function foeSlots(battle)
    local own = zTrainer(battle)
    local party, enemy = battle.enemyParty, battle.enemy
    if not own or type(party) ~= "table" or not enemy
        or enemy ~= party[#party] then
      return nil
    end
    local best = {}  -- type key -> { inst, power, def }
    for _, inst in ipairs(enemy.moves or {}) do
      local def = moveDef(battle, inst.id)
      local power = zPower(def)
      local key = def and typeKey(def.type)
      if power and Z[key] and not Z[key].species and (inst.pp or 0) > 0
          and not disabled(battle, enemy, inst.id) then
        if not best[key] or power > best[key].power then
          best[key] = { inst = inst, power = power, def = def }
        end
      end
    end
    if own ~= true and best[own] then return best[own], own end
    local pick, pickKey
    for key, row in pairs(best) do
      if not pick or row.power > pick.power
          or (row.power == pick.power and key < pickKey) then
        pick, pickKey = row, key
      end
    end
    return pick, pickKey
  end

  mod.hooks:wrap("battle.enemy_action", function(next, battle)
    local chosen = next(battle)
    local st = stateFor(battle)
    if not st or st.foeUsed then return chosen end
    local id = type(chosen) == "table" and (chosen.id or chosen.move) or chosen
    if type(id) ~= "string" or id == "STRUGGLE" then return chosen end
    if locked(battle, battle.enemy) then return chosen end
    local row, key = foeSlots(battle)
    if not row then return chosen end
    local z = Z[key]
    st.foePlan = { inst = row.inst, mon = battle.enemy, key = key,
                   power = row.power, def = row.def, zId = z.id }
    return z.id
  end)

  -- ------- turn flow

  mod.events:on("battle.turn_started", function(ev)
    local battle = ev and ev.battle
    local st = battles[battle]
    if not st then return end
    local plan = st.foePlan
    st.foePlan = nil
    local action = ev.enemyAction
    if plan and action and (action.move == plan.zId or action.id == plan.zId)
        and not st.foeUsed then
      local z = Z[plan.key]
      st.foe = { inst = plan.inst, mon = plan.mon, baseId = plan.inst.id,
                 zId = z.id, key = plan.key, power = plan.power, def = plan.def,
                 anim = animFor(z), executed = false }
    end
  end)

  mod.events:on("battle.move_used", function(ev)
    local battle = ev and ev.battle
    local st = battles[battle]
    if not st or ev.isCalled then return end
    local moveId = ev.moveId or (ev.move and ev.move.id)
    local f = st.foe
    if f and not f.executed and ev.user == battle.enemy and moveId == f.zId then
      f.executed = true
      markSpent(battle, st, 2)
      count("faced")
      -- the trainer's PP comes off the move it turned into a Z-Move
      if (f.inst.pp or 0) > 0 then f.inst.pp = f.inst.pp - 1 end
      local event = battle.moveEvent
      if event and event.move == f.zId and f.anim ~= f.zId then event.move = f.anim end
      pcall(sayBeforeUse, battle, battleLine(battle, "_ZMovesUnleashText", battle.enemy))
      return
    end
    local p = st.pending
    if not p or p.executed or ev.user ~= battle.player then return end
    if p.status then
      if moveId == p.baseId then
        p.executed = true
        markSpent(battle, st, 1)
        count("used", p.key)
        pcall(sayBeforeUse, battle, battleLine(battle, "_ZMovesAuraText", battle.player))
        pcall(applyStatus, battle, battle.player, p.status)
      end
      return
    end
    if moveId ~= p.zId then return end
    p.executed = true
    markSpent(battle, st, 1)
    count("used", p.key)
    pcall(sayBeforeUse, battle, battleLine(battle, "_ZMovesUnleashText", battle.player))
    local event = battle.moveEvent
    if event and event.move == p.zId and p.anim ~= p.zId then event.move = p.anim end
    if p.boost then
      pcall(function()
        local stages = stagesOf(battle, battle.player)
        for _, stat in ipairs(p.boost) do raise(stages, stat, 2) end
        say(battle, battleLine(battle, "_ZMovesBoostAllText", battle.player))
      end)
    end
  end)

  local function zActive(ctx)
    local battle = ctx and ctx.battle
    local st = battles[battle]
    if not st then return nil end
    local id = ctx.moveId or (ctx.move and ctx.move.id)
    local p = ctx.user == battle.player and st.pending
      or ctx.user == battle.enemy and st.foe
    if p and p.zId and p.power and p.executed and id == p.zId then
      forget(battle, ctx.user, p.zId, p.baseId)
      return p
    end
  end

  -- Z-Moves bypass the accuracy roll (a foe mid-Fly/Dig still avoids them:
  -- the engine checks that before it rolls)
  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    if zActive(ctx) then return true end
    return next(ctx)
  end)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local p = zActive(ctx)
    if p and type(ctx.opts) == "table" then ctx.opts.power = p.power end
    return next(ctx)
  end)

  -- battle.started comes twice on Gen 2: from the battle (state starts) and
  -- from the battle screen once its intro is queued (the warning goes there,
  -- so it shows just before the first menu)
  mod.events:on("battle.started", function(ev)
    local b = ev and ev.battle
    if isBattle(b) then
      stateFor(b)
      return
    end
    local screen = type(b) == "table" and b.battle and b or nil
    local battle = screen and screen.battle
    local st = battle and stateFor(battle)
    if not st or st.foeUsed or st.warned or mod.options:get("warnings") == false then
      return
    end
    if not zTrainer(battle) then return end
    st.warned = true
    local name = battle.trainer and battle.trainer.name or "The trainer"
    pcall(function()
      screen:push({ kind = "message",
        text = line(battle.data, "_ZMovesWarningText", { TRAINER = name }) })
    end)
  end)

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    finish(battle, battles[battle])
  end)

  -- a Pokemon that faints or leaves before its Z-Move fires hands the slot
  -- back at once; the Z-Power was not spent
  local function dropPending(battle, st, mon)
    for _, key in ipairs({ "pending", "foe" }) do
      local p = st[key]
      if p and not p.executed and (mon == nil or mon == p.mon) then
        if p.zId and p.inst.id == p.zId then p.inst.id = p.baseId end
        st[key] = nil
      end
    end
  end

  mod.events:on("battle.battler_switched", function(ev)
    local battle = ev and ev.battle
    local st = battles[battle]
    if not st then return end
    st.armed = false
    dropPending(battle, st, ev.previous)
  end)

  mod.events:on("battle.fainted", function(ev)
    local battle = ev and ev.battle
    local st = battles[battle]
    if st then dropPending(battle, st, ev.battler) end
  end)

  mod.events:on("battle.ended", function(ev)
    local b = ev and ev.battle
    local battle = isBattle(b) and b or (type(b) == "table" and b.battle) or nil
    if not isBattle(battle) then return end
    local st = battles[battle]
    finish(battle, st)
    -- RED leaves no flag behind; remember the win for MEWNIUM Z
    local result = ev.result
    if result == "win" and trainerClass(battle) == "RED" then
      pcall(function()
        local w = wins()
        w.RED = true
        mod.save:set("wins", w)
      end)
    end
    if rawget(battle, "takeTurn") ~= nil then battle.takeTurn = nil end
    battles[battle] = nil
  end)

  -- a save can never carry a Z-Move id in a move slot
  mod.events:on("save.writing", function()
    for battle, st in pairs(battles) do restore(battle, st) end
  end)

  -- ------- input: START toggles Z-Power

  local deliver  -- the overworld messages, below

  mod.hooks:wrap("input.step", function(next, game, dt)
    tick = tick + 1
    pcall(function()
      local input = game and game.input
      if input and input.wasPressed and input:wasPressed("start") then
        local screen = topScreen(game)
        local st = screen and stateFor(screen.battle)
        if st and screen.phase == "moves" and not screen.moveSwapIndex
            and not screen.link then
          toggle(screen.battle, st)
        end
      end
    end)
    if deliver then pcall(deliver, game) end
    return next(game, dt)
  end)

  -- the command menu's START is a shared hook; only claim it for a Pokemon
  -- that actually holds a crystal
  mod.hooks:wrap("battle.menu_auxiliary", function(next, game, info)
    local screen = topScreen(game)
    local st = screen and stateFor(screen.battle)
    local mon = st and screen.phase == "menu" and screen.battle.player
    if mon and Z[mon[FIELD] or ""] then
      toggle(screen.battle, st)
      return true
    end
    return next(game, info)
  end)

  -- ------- battle overlay
  -- One slim bar between the two Pokemon, 20 characters wide, on rows 5-6:
  -- clear of the foe's HUD (rows 0-3), your HUD (rows 7-11), the TYPE/PP box
  -- (rows 8-12) and the move list.  A name too long for its space scrolls.

  local BAR_Y = 40
  local BAR_H = 16
  local COLS = 20
  local FIELD_X = 72   -- the widescreen field's left edge

  -- Gen 2 has two special stats, so speed takes SPE and Sp. Def SPD
  local SHORT_STAT = { attack = "ATK", defense = "DEF", speed = "SPE",
                       specialAttack = "SPA", specialDefense = "SPD",
                       accuracy = "ACC", evasion = "EVA" }
  local function shortEffect(effect)
    if effect == "reset" then return "RESET" end
    if effect == "heal" then return "HEAL" end
    if effect == "all" then return "ALL+1" end
    if effect == "crit" then return "CRIT+" end
    return (SHORT_STAT[effect[1]] or "?") .. "+" .. effect[2]
  end

  local HOLD, STEP = 50, 9
  local function fits(Font, text, pixels) return Font.width(text) <= pixels end

  local function window(Font, text, pixels, since)
    if fits(Font, text, pixels) then return text end
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

  local function drawBar(Font, x0, left, right, st)
    local g = love.graphics
    local x, w = x0, COLS * 8
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
    if st.barText ~= left then st.barText, st.barSince = left, tick end
    Font.draw(prefix .. window(Font, left, room, st.barSince), x, BAR_Y + 4)
    if #right > 0 then Font.draw(right, x + w - rightW, BAR_Y + 4) end
  end

  local function docked(screen)
    local ok, yes = pcall(function()
      return screen.extendedHUD and screen:extendedHUD() == true
    end)
    return ok and yes
  end

  local function drawOverlay(screen)
    local battle = screen.battle
    local st = stateFor(battle)
    if not st or screen.link or screen.tutorial or screen.contest then return end
    local phase = screen.phase
    local choosing = phase == "menu" or phase == "moves"
    if st.armed and (not choosing or not available(battle, st)) then
      st.armed = false
    end
    if not choosing then return end

    local Font = mod.ui.Font
    local g = love.graphics
    local wide = false
    pcall(function() wide = screen:wideLayout() == true end)
    local barX = wide and FIELD_X or 0

    if st.notice then
      if tick < st.notice.untilTick then
        drawBar(Font, barX, st.notice.text, nil, st)
      else
        st.notice = nil
      end
    elseif st.armed and phase == "moves" then
      local info = usable(battle, screen.moveIndex or 1)
      if info and info.status then
        drawBar(Font, barX, tostring(info.def.name or info.def.id),
          shortEffect(info.status), st)
      elseif info and info.boost then
        drawBar(Font, barX, table.concat(info.z.name, " "), "ALL+2", st)
      elseif info then
        drawBar(Font, barX, table.concat(info.z.name, " "), tostring(info.power), st)
      else
        drawBar(Font, barX, "NO Z-MOVE", nil, st)
      end
    elseif st.armed then
      drawBar(Font, barX, "POWER READY", nil, st)
    elseif phase == "moves" and not (wide and docked(screen))
        and available(battle, st) then
      -- a Z in the list's last column, right of the name (Gen 2 names are
      -- twelve letters at most, from column 6), on each move that can
      -- become one.  The widescreen list has the same columns.
      for slot = 1, #(battle.player.moves or {}) do
        if usable(battle, slot) then
          local x, y = 18 * 8, (12 + slot) * 8
          g.setColor(1, 1, 1, 1)
          g.rectangle("fill", x, y, 8, 8)
          g.setColor(0, 0, 0, 1)
          Font.draw("Z", x, y)
        end
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  mod.hooks:wrap("battle.overlay", function(next, screen)
    next(screen)
    if screenOf(screen) then pcall(drawOverlay, screen) end
  end)

  -- ------- party menu: give / take a Z-Crystal

  local function monName(game, mon)
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end

  local function showText(game, text, onDone)
    game.stack:push(mod.ui.TextBox.new(game, text, onDone))
  end

  local function openCrystals(mon, game)
    local held = mon[FIELD]
    local fits = {}
    for _, inst in ipairs(mon.moves or {}) do
      local def = game.data.moves[inst.id]
      if zPower(def) or zStatus(def) then fits[typeKey(def.type)] = true end
    end
    local items = {}
    local function offered(key) return unlocked(game, key) or held == key end
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
      showText(game, "No Z-CRYSTALS\nyet.")
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
        showText(game, text)
      end,
    }))
  end

  local MAX_ROWS = 8  -- the field submenu's height

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local rows = next(game, items, mon, ctx)
    if type(rows) ~= "table" or type(mon) ~= "table" or (ctx and ctx.battle)
        or mon.isEgg then
      return rows
    end
    if not hasRing(game) and not mon[FIELD] then return rows end
    -- a Pokemon with four field moves fills the box; its crystal is then
    -- handled from Z-RING > PARTY
    local hasCancel = false
    for _, row in ipairs(rows) do
      if type(row) == "table" and row.id == "CANCEL" then hasCancel = true end
    end
    if #rows >= MAX_ROWS or (#rows + 1 > MAX_ROWS and not hasCancel) then
      return rows
    end
    local held = mon[FIELD] and Z[mon[FIELD]]
    local label = held and ("Z:" .. (held.species
      and (held.crystal:gsub(" Z$", "")) or held.key)) or "Z-CRYSTAL"
    local at = #rows + 1
    for i, row in ipairs(rows) do
      if type(row) == "table" and row.id == "STATS" then at = i break end
    end
    table.insert(rows, at, {
      label = label,
      onSelect = function(selected, g) openCrystals(selected or mon, g or game) end,
    })
    return rows
  end)

  -- ------- the Z-RING key item
  -- A key item in the KEY ITEMS pocket.  With the mod turned off the item
  -- simply has no definition: the PACK lists it by its id and does nothing
  -- with it, and nothing else in the save refers to it.

  local RING_ITEM = "Z_RING"
  local ringItem = pcall(function()
    mod.content.items:register(RING_ITEM, {
      id = RING_ITEM, name = "Z-RING", price = 0, tossable = false,
      pocket = "KEY_ITEM",
    })
  end)

  local function holdsRingItem(save)
    if type(save) ~= "table" then return false end
    for _, store in ipairs({ save.inventory, save.pcItems }) do
      if type(store) == "table" and (tonumber(store[RING_ITEM]) or 0) > 0 then
        return true
      end
    end
    return false
  end

  -- the KEY ITEMS pocket holds 25 (MAX_KEY_ITEMS)
  local function keyPocketHasRoom(game)
    local save, data = game and game.save, game and game.data
    if type(save) ~= "table" then return false end
    local used = 0
    for id, n in pairs(save.inventory or {}) do
      local def = data and data.items and data.items[id]
      if (tonumber(n) or 0) > 0 and def and def.pocket == "KEY_ITEM" then
        used = used + 1
      end
    end
    return used < 25
  end

  -- ------- "got a crystal" messages
  -- Which crystals have been announced is kept with the save, so a message
  -- missed to a reset still shows later.  They are shown only once the
  -- overworld is idle (no script, text, warp, cutscene or step running), so
  -- nothing can interrupt a map change.  Each one plays the item jingle.

  local LABEL, ORDER = {}, {}
  for i, row in ipairs(TYPES) do LABEL[row.key], ORDER[row.key] = row.crystal, i end
  for i, row in ipairs(EXCLUSIVE) do
    LABEL[row.key], ORDER[row.key] = row.crystal, 100 + i
  end

  local RING_TEXT = "_ZMovesGotZRingText"
  local RING_BAG_TEXT = "_ZMovesRingToBagText"
  local function gotText(key) return "_ZMovesGot" .. key .. "Text" end
  local GOT = {
    [RING_TEXT] = "{PLAYER} got a\nZ-RING!",
    [RING_BAG_TEXT] = "{PLAYER} put the\nZ-RING in the PACK.",
  }
  for key, label in pairs(LABEL) do
    if Z[key] then GOT[gotText(key)] = "{PLAYER} got\n" .. label .. "!" end
  end
  pcall(function()
    for id, text in pairs(GOT) do mod.content.rom_text:register(id, text) end
  end)

  local function playerName(game)
    local save = game and game.save
    local p = type(save) == "table" and save.player
    return (type(p) == "table" and p.name) or "PLAYER"
  end

  local function fieldText(game, id)
    local data = game and game.data
    local text = data and data.text and data.text[id]
    if type(text) ~= "string" then text = GOT[id] or id end
    return strip(text:gsub("{PLAYER}", playerName(game)))
  end

  -- every milestone already passed, without a message: a save from before
  -- this version, or one first loaded with the mod, starts here
  local function baseline(game)
    local seen = { RING = hasRing(game) or nil }
    for key in pairs(UNLOCK) do
      if Z[key] and unlocked(game, key) then seen[key] = true end
    end
    return seen
  end

  local function announced(game)
    local seen = mod.save:get("announced")
    if type(seen) ~= "table" then
      seen = baseline(game)
      mod.save:set("announced", seen)
    end
    return seen
  end

  mod.events:on("save.loaded", function()
    if storyMode() then pcall(announced, mod.game) end
  end)

  local function idleWorld(game)
    if not (game and game.save) then return nil end
    local stack = game.stack
    if stack and stack.top and stack:top() ~= nil then return nil end
    local ok, world = pcall(function() return mod.world:overworld() end)
    if not ok or type(world) ~= "table" then return nil end
    if game.phase ~= nil and game.phase ~= "play" then return nil end
    if world.battleActive or world.map == nil then return nil end
    local busy = true
    pcall(function() busy = world:busy() end)
    if busy then return nil end
    local player = world.player
    if player and player.moving and not world.stepFinished then return nil end
    -- the same test the game makes before it opens the START menu
    if type(world.acceptsMenuInput) == "function" then
      local ok, accepts = pcall(function() return world:acceptsMenuInput() end)
      if ok and accepts == false then return nil end
    end
    return world
  end

  local lastCheck = -1000
  deliver = function(game)
    -- a few times a second is plenty
    if tick - lastCheck < 20 then return end
    lastCheck = tick
    local world = idleWorld(game)
    if not world then return end
    local save = game.save
    local story = storyMode()
    local seen = story and announced(game) or {}
    local texts, keys = {}, {}
    local giveRing = ringItem and hasRing(game) and not holdsRingItem(save)
      and mod.save:get("ringGiven") ~= true and keyPocketHasRoom(game)
    if story and hasRing(game) and not seen.RING then
      texts[#texts + 1] = fieldText(game, RING_TEXT)
    elseif giveRing then
      texts[#texts + 1] = fieldText(game, RING_BAG_TEXT)
    end
    if story then
      for key in pairs(UNLOCK) do
        if Z[key] and not seen[key] and unlocked(game, key) then
          keys[#keys + 1] = key
        end
      end
      table.sort(keys, function(a, b) return ORDER[a] < ORDER[b] end)
      for _, key in ipairs(keys) do texts[#texts + 1] = fieldText(game, gotText(key)) end
    end
    if #texts == 0 then return end
    local rows = {}
    for _, text in ipairs(texts) do rows[#rows + 1] = { "text", text } end
    local queued = mod.world:queueScript(rows)
    if not queued then return end
    -- marked only once the message is actually on its way
    if story then
      if hasRing(game) then seen.RING = true end
      for _, key in ipairs(keys) do seen[key] = true end
      mod.save:set("announced", seen)
    end
    if giveRing then
      save.inventory = save.inventory or {}
      save.inventory[RING_ITEM] = 1
      mod.save:set("ringGiven", true)
    end
    pcall(function() world:playSfxNamed("Sfx_Item", 0x01) end)
  end

  -- ------- the Z-RING screen: crystals, party, record

  local function crystalStem(key)
    local label = LABEL[key] or key
    return (label:gsub(" Z$", ""))
  end

  local function typeName(game, key)
    for _, row in ipairs(TYPES) do
      if row.key == key then
        local sample = game.data.moves[row.anim]
        local types = game.data.type_chart and game.data.type_chart.types
        local rec = sample and type(types) == "table" and types[sample.type]
        if type(rec) == "table" and type(rec.name) == "string" then
          return rec.name
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

  local function openCollection(game)
    local items = {}
    local held = {}
    for _, mon in ipairs(game.save.party or {}) do
      if mon[FIELD] then held[mon[FIELD]] = true end
    end
    local function add(key)
      if not Z[key] then return end
      if unlocked(game, key) then
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

  -- also where a crystal is given or taken when the party menu has no room
  -- for the Z-CRYSTAL row
  local function openParty(game)
    local items = {}
    for _, mon in ipairs(game.save.party or {}) do
      if not mon.isEgg then
        local key = mon[FIELD]
        items[#items + 1] = { label = monName(game, mon), mon = mon,
          right = key and Z[key] and crystalStem(key) or "-----" }
      end
    end
    if #items == 0 then return showText(game, "No POKéMON.") end
    game.stack:push(mod.ui.ListMenu.new(game, "PARTY", items, {
      onChoose = function(item) openCrystals(item.mon, game) end,
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

  -- USE from the PACK opens the screen; the ring is never spent.  In battle
  -- the PACK answers with the game's own "can't use that here".
  mod.hooks:wrap("item.use", function(next, game, battle, id, ...)
    if id ~= RING_ITEM or battle then return next(game, battle, id, ...) end
    pcall(openRing, game)
  end)

  -- ------- for other mods (a custom battle UI can draw its own Z button)

  mod.exports.field = FIELD
  mod.exports.generation = 2
  mod.exports.zPower = zPower
  mod.exports.zStatus = zStatus
  mod.exports.unlocked = function(key) return unlocked(mod.game, key) end
  mod.exports.crystalOf = function(mon)
    local z = type(mon) == "table" and Z[mon[FIELD] or ""]
    return z and z.crystal or nil
  end
  local function battleOf(b)
    if isBattle(b) then return b end
    local screen = screenOf(b)
    return screen and screen.battle
  end
  mod.exports.state = function(b)
    local battle = battleOf(b)
    local st = battle and stateFor(battle)
    return { armed = st and st.armed or false, used = st and st.used or false,
             foeUsed = st and st.foeUsed or false }
  end
  mod.exports.preview = function(b, slot)
    local battle = battleOf(b)
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
