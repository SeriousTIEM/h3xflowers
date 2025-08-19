-- init.lua
-- ElysFlowers — temperature + humidity placement (Minetest core only)
-- Adds grass-replacement spawning and tunable rarity. Keeps variants and xcompat/Woodsoils.

local core = minetest
local modname = core.get_current_modname() or "elysflowers"
local S = core.get_translator and core.get_translator(modname) or function(s) return s end

-- =========================================================
-- Settings
-- =========================================================
-- Multiply per-family rarity (1 in N) by this scale.
-- Example: elysflowers_chance_scale = 0.5  -> about 2× denser
local CHANCE_SCALE = tonumber(core.settings:get("elysflowers_chance_scale") or "1.0") or 1.0
if CHANCE_SCALE < 0.05 then CHANCE_SCALE = 0.05 end
if CHANCE_SCALE > 20.0 then CHANCE_SCALE = 20.0 end

-- Replace decorative plants (grass, dry grass, ferns, junglegrass) when placing.
local REPLACE_GRASS = core.settings:get_bool("elysflowers_replace_grass", true)

-- Optional per-chunk debug log of placements
local DEBUG = core.settings:get_bool("elysflowers_debug", false)

-- =========================================================
-- xcompat (non-biome) — allow other mods to extend "place_on" surfaces
-- =========================================================
local ALLOWED_BASE_NAMES = {}
local _allowed_cids = nil
local _allowed_dirty = true

local function add_place_on(names)
  for _, n in ipairs(names or {}) do
    if core.registered_nodes[n] then
      ALLOWED_BASE_NAMES[n] = true
      _allowed_dirty = true
    end
  end
end

elysflowers_xcompat = {
  add_place_on = add_place_on,
}

-- Core defaults (MTG surfaces)
add_place_on({
  "default:dirt", "default:dirt_with_grass", "default:dirt_with_dry_grass",
  "default:dirt_with_coniferous_litter", "default:dirt_with_rainforest_litter",
  "default:dirt_with_snow", "default:snowblock",
  "default:sand", "default:silver_sand",
  "default:gravel",
  "default:permafrost_with_moss", "default:permafrost_with_stones", "variety:dirt_with_meadow_grass", "variety:meadow_dirt_with_grass", "livingdesert:coldsteppe_ground", "livingdesert:coldsteppe_ground2",
})

-- Opportunistic Woodsoils integration
core.register_on_mods_loaded(function()
  if core.get_modpath("woodsoils") then
    for name, def in pairs(core.registered_nodes) do
      if name:sub(1,10) == "woodsoils:" and type(def.groups) == "table" then
        local g = def.groups
        if g.soil or g.dirt or g.humus or g.loam or g.podzol or g.forest_litter then
          ALLOWED_BASE_NAMES[name] = true
          _allowed_dirty = true
        end
      end
    end
  end
end)

local function resolve_allowed_cids()
  if not _allowed_dirty and _allowed_cids then return _allowed_cids end
  local t = {}
  for n in pairs(ALLOWED_BASE_NAMES) do
    local cid = core.get_content_id(n)
    if cid and cid ~= 0 then t[cid] = true end
  end
  _allowed_cids = t
  _allowed_dirty = false
  return _allowed_cids
end

-- =========================================================
-- Replaceable decorative plants (grass etc.)
-- =========================================================
local _replaceable_cids
local function resolve_replaceable_cids()
  if _replaceable_cids then return _replaceable_cids end
  local names = {
    "default:grass_1","default:grass_2","default:grass_3","default:grass_4","default:grass_5",
    "default:dry_grass_1","default:dry_grass_2","default:dry_grass_3","default:dry_grass_4","default:dry_grass_5",
    "default:fern_1","default:fern_2","default:fern_3",
    "default:junglegrass",
  }
  local t = {}
  for _, n in ipairs(names) do
    local cid = core.get_content_id(n)
    if cid and cid ~= 0 then t[cid] = true end
  end
  _replaceable_cids = t
  return _replaceable_cids
end

-- =========================================================
-- Helpers and registry
-- =========================================================
local ELYS = { families = {} }

local function infer_heat_from_biomes(biomes)
  if type(biomes) ~= "table" then return {min=35,max=70} end
  local cold, hot, swamp = false,false,false
  for _, b in ipairs(biomes) do
    local v = tostring(b):lower()
    if v:find("tundra") or v:find("taiga") or v:find("cold") or v:find("ice") or v:find("snow") then cold = true end
    if v:find("desert") or v:find("savanna") or v:find("jungle") or v:find("rainforest") or v:find("mangrove") then hot = true end
    if v:find("swamp") or v:find("mire") or v:find("bog") then swamp = true end
  end
  if cold and not hot then return {min=0,max=35} end
  if hot and not cold then return {min=60,max=100} end
  if swamp then return {min=45,max=70} end
  return {min=35,max=70}
end

local function infer_humidity_from_biomes(biomes)
  if type(biomes) ~= "table" then return {min=0,max=100} end
  local arid, wet = false,false
  for _, b in ipairs(biomes) do
    local v = tostring(b):lower()
    if v:find("desert") or v:find("savanna") then arid = true end
    if v:find("rainforest") or v:find("swamp") or v:find("jungle") or v:find("mangrove") then wet = true end
  end
  if wet  and not arid then return {min=60,max=100} end
  if arid and not wet  then return {min=0, max=40}  end
  return {min=20,max=85}
end

local function register_node(def)
  local groups = {
    snappy=3, flammable=2, attached_node=1, dig_immediate=3, flower=1, flora=1, plant=1
  }
  if def.not_in_creative_inventory then groups.not_in_creative_inventory = 1 end
  core.register_node(def.name, {
    description         = def.description or def.name,
    drawtype            = "plantlike",
    tiles               = def.tiles,
    wield_image         = def.wield_image or (def.tiles and def.tiles[1]),
    inventory_image     = def.inventory_image or (def.tiles and def.tiles[1]),
    visual_scale        = def.visual_scale or 1.0,
    waving              = 1,
    paramtype           = "light",
    sunlight_propagates = true,
    walkable            = false,
    groups              = groups,
    floodable           = true,
    selection_box       = { type="fixed", fixed = def.selection_box or { -0.3,-0.5,-0.3, 0.3,0.3,0.3 } },
    on_place            = def.on_place,
    drop                = def.drop,
  })
  if def._botanical_name then
    local d = core.registered_nodes[def.name].description
    core.override_item(def.name, { description = d .. "\n" .. core.colorize("#d0ffd0", def._botanical_name) })
  end
  if core.global_exists("flowerpot") then
    pcall(function() flowerpot.register_node(def.name) end)
  end
end

-- Family/variant registration
local function register_family(def)
  local heat   = def.heat_range     or infer_heat_from_biomes(def.biomes)
  local humid  = def.humidity_range or infer_humidity_from_biomes(def.biomes)

  local family = {
    content_ids = {},
    step        = math.max(3, def.sidelen or 8),
    chance      = math.max(1, math.floor((def.chance or 650) * CHANCE_SCALE)),
    y_min       = def.y_min or 1,
    y_max       = def.y_max or 31000,
    heat_min    = heat.min or 0,
    heat_max    = heat.max or 100,
    humid_min   = humid.min or 0,
    humid_max   = humid.max or 100,
  }

  -- 1) Auto-register variants if provided
  if def.variant_defs and #def.variant_defs > 0 then
    for _, v in ipairs(def.variant_defs) do
      if not core.registered_nodes[v.name] then
        register_node(v)
      end
      local cid = core.get_content_id(v.name)
      if cid and cid ~= 0 then table.insert(family.content_ids, cid) end
    end
  end

  -- 2) Adopt pre-registered variant names (safe if some are missing)
  if def.variants and #def.variants > 0 then
    for _, name in ipairs(def.variants) do
      if core.registered_nodes[name] then
        local cid = core.get_content_id(name)
        if cid and cid ~= 0 then
          table.insert(family.content_ids, cid)
        end
      else
        minetest.log("warning",
          ("[h3xflowers] Skipping unknown variant '%s' (not registered)"):format(name))
      end
    end
  end

  -- 3) Optional single-node family
  if def.name then
    if not core.registered_nodes[def.name] then
      register_node(def)
    end
    local cid = core.get_content_id(def.name)
    if cid and cid ~= 0 then table.insert(family.content_ids, cid) end
  end

  -- De-duplicate CIDs
  local uniq, out = {}, {}
  for _, cid in ipairs(family.content_ids) do
    if not uniq[cid] then uniq[cid] = true table.insert(out, cid) end
  end
  family.content_ids = out

  if #family.content_ids > 0 then
    table.insert(ELYS.families, family)
  end
end

-- =========================================================
-- DEFINITIONS — full set (all original node names preserved)
-- =========================================================

register_family({
  name="h3xflowers:indian_paintbrush",
  _botanical_name="Castilleja coccinea",
  description=S("Indian Paintbrush"),
  tiles={"indian_paintbrush.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=60,max=95}, humidity_range={min=15,max=65}, chance=700,
})

register_family({
  name="h3xflowers:forget_me_not",
  _botanical_name="C. Amabile",
  description=S("Chinese Forget-me-not"),
  tiles={"forget_me_not.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=35,max=70}, humidity_range={min=35,max=85}, chance=600,
})

register_family({
  name="h3xflowers:foxglove",
  _botanical_name="Digitalis purpurea",
  description=S("Foxglove"),
  tiles={"foxglove2.png"},
  selection_box={-0.25,-0.49,-0.25,0.25,0.50,0.25},
  heat_range={min=30,max=65}, humidity_range={min=35,max=90}, chance=750,
})

register_family({
  name="h3xflowers:hibiscus",
  _botanical_name="H. Aponeurus",
  description=S("Hibiscus"),
  tiles={"hibiscus_flower.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=70,max=100}, humidity_range={min=40,max=100}, chance=650,
})

register_family({
  name="h3xflowers:larkspur",
  _botanical_name="D. nuttallianum",
  description=S("Larkspur"),
  tiles={"larkspur.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=30,max=65}, humidity_range={min=30,max=80}, chance=700,
})

register_family({
  name="h3xflowers:black_eyed_susan",
  _botanical_name="Rudbeka. Hertia",
  description=S("Black-eyed-susan"),
  tiles={"black_eyed_susan.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=50,max=85}, humidity_range={min=30,max=75}, chance=650,
})

register_family({
  name="h3xflowers:phlox",
  _botanical_name="P. drummondii",
  description=S("Phlox"),
  tiles={"phlox.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=35,max=70}, humidity_range={min=35,max=85}, chance=650,
})

-- Purple Coneflower — registers original node names and keeps on_place randomizer
register_family({
  variant_defs={
    {
      name="h3xflowers:purple_coneflower",
      _botanical_name="Echinacea purpurea",
      description=S("Purple Coneflower"),
      tiles={"purple_coneflower_0.png"},
      wield_image="purple_coneflower_0.png",
      inventory_image="purple_coneflower_0.png",
      selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
      on_place=function(itemstack, placer, pointed_thing)
        if not pointed_thing or pointed_thing.type ~= "node" then
          return itemstack
        end
        local pos = pointed_thing.above
        local variant = math.random(0,1)
        local name = (variant == 0) and "h3xflowers:purple_coneflower" or "h3xflowers:purple_coneflower_1"
        core.set_node(pos, { name = name })
        itemstack:take_item()
        return itemstack
      end,
    },
    {
      name="h3xflowers:purple_coneflower_1",
      _botanical_name="Echinacea purpurea",
      description=S("Purple Coneflower"),
      tiles={"purple_coneflower_1.png"},
      wield_image="purple_coneflower_0.png",
      inventory_image="purple_coneflower_0.png",
      selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
      not_in_creative_inventory=true,
    },
  },
  heat_range={min=40,max=75}, humidity_range={min=25,max=70}, chance=700,
})

register_family({
  name="h3xflowers:california_poppy",
  _botanical_name="E. californica",
  description=S("California Poppy"),
  tiles={"california_poppy.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=60,max=95}, humidity_range={min=10,max=50}, chance=600,
})

register_family({
  name="h3xflowers:hyacinth",
  _botanical_name="Hyacinthus Orientalis",
  description=S("Hyacinth"),
  tiles={"hyacinth.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=10,max=45}, humidity_range={min=30,max=85}, chance=800,
})

register_family({
  name="h3xflowers:lavender",
  _botanical_name="Lavandula officinalis",
  description=S("Lavender"),
  tiles={"lavender.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=40,max=70}, humidity_range={min=25,max=60}, chance=650,
})

register_family({
  name="h3xflowers:marshmallow",
  _botanical_name="A. officinalis",
  description=S("Marshmallow"),
  tiles={"marshmallow_1.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=40,max=65}, humidity_range={min=50,max=95}, chance=750,
})

register_family({
  name="h3xflowers:yarrow_pink",
  _botanical_name="A. millefolium",
  description=S("Yarrow"),
  tiles={"yarrow.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=35,max=65}, humidity_range={min=30,max=70}, chance=700,
})

register_family({
  name="h3xflowers:african_marigold",
  _botanical_name="Tagetes. Erecta",
  description=S("African Marigold"),
  tiles={"marigold_1.png"},
  selection_box={-0.35,-0.5,-0.35,0.35,0.40,0.35},
  heat_range={min=60,max=95}, humidity_range={min=20,max=70}, chance=600,
})

register_family({
  name="h3xflowers:arctic_poppy",
  _botanical_name="P. radicatum",
  description=S("Arctic Poppy"),
  tiles={"arctic_poppy.png"},
  selection_box={-0.45,-0.5,-0.35,0.35,0.45,0.35},
  heat_range={min=0,max=30}, humidity_range={min=10,max=60}, chance=650,
})

register_family({
  name="h3xflowers:dames_rocket",
  _botanical_name="H. matronalis",
  description=S("Dame's Rocket"),
  tiles={"dames_rocket.png"},
  selection_box={-0.25,-0.5,-0.25,0.25,0.30,0.25},
  heat_range={min=25,max=60}, humidity_range={min=50,max=90}, chance=700,
})

register_family({
  name="h3xflowers:crocus",
  _botanical_name="C. sativus",
  description=S("Crocus"),
  tiles={"crocus.png"},
  selection_box={-0.25,-0.5,-0.25,0.25,0.30,0.25},
  heat_range={min=0,max=30}, humidity_range={min=20,max=60}, chance=700,
})

-- Fireweed — multi-node set (original names)
register_family({
  variants={ "h3xflowers:fireweed", "h3xflowers:fireweed_2", "h3xflowers:fireweed_3", "h3xflowers:fireweed_4" },
  heat_range={min=15,max=50}, humidity_range={min=30,max=80}, chance=600,
})

register_family({
  name="h3xflowers:chamomile",
  _botanical_name="M. chamomilla",
  description=S("Chamomile"),
  tiles={"chamomile.png"},
  selection_box={-0.35,-0.4,-0.35,0.35,0.40,0.35},
  heat_range={min=25,max=60}, humidity_range={min=30,max=70}, chance=650,
})

register_family({
  name="h3xflowers:rose_pogonia",
  _botanical_name="P. ophioglossoides",
  description=S("Rose Pogonia"),
  tiles={"rose_pogonia.png"},
  selection_box={-0.35,-0.4,-0.35,0.35,0.40,0.35},
  heat_range={min=15,max=60}, humidity_range={min=60,max=100}, chance=700,
})

register_family({
  name="h3xflowers:yellow_bell",
  _botanical_name="P. ophioglossoides",
  description=S("Yellow Bell"),
  tiles={"yellow_bell.png"},
  selection_box={-0.35,-0.4,-0.35,0.35,0.40,0.35},
  heat_range={min=20,max=60}, humidity_range={min=30,max=80}, chance=700,
})

register_family({
  name="h3xflowers:bergamot",
  _botanical_name="P. ophioglossoides",
  description=S("Bergamot"),
  tiles={"bergamot.png"},
  selection_box={-0.35,-0.4,-0.35,0.35,0.40,0.35},
  heat_range={min=35,max=65}, humidity_range={min=30,max=70}, chance=650,
})

-- =========================================================
-- Mapgen: temperature + humidity based placement with variants
-- - Places a flower if the above node is air OR (REPLACE_GRASS and above is a decorative plant)
-- =========================================================
core.register_on_generated(function(minp, maxp, seed)
  if maxp.y < 0 then return end

  local heatmap     = core.get_mapgen_object("heatmap")
  local humiditymap = core.get_mapgen_object("humiditymap")
  local heightmap   = core.get_mapgen_object("heightmap")
  if not (heatmap and humiditymap and heightmap) then return end

  local vm, emin, emax = core.get_mapgen_object("voxelmanip")
  local data = vm:get_data()
  local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
  local c_air = core.CONTENT_AIR

  local ALLOWED = resolve_allowed_cids()
  local REPL = resolve_replaceable_cids()

  local w = maxp.x - minp.x + 1
  local d = maxp.z - minp.z + 1
  local pr = PseudoRandom(seed + 2897)

  local total_placed = 0

  for _, fam in ipairs(ELYS.families) do
    if fam.content_ids and #fam.content_ids > 0 then
      local step = fam.step
      -- jitter starting offsets to break grid patterns
      local ox = pr:next(0, step - 1)
      local oz = pr:next(0, step - 1)
      local fam_placed = 0

      for dz = oz, d - 1, step do
        for dx = ox, w - 1, step do
          local idx = dz * w + dx + 1
          local heat  = heatmap[idx]
          local humid = humiditymap[idx]
          if heat and humid and
             heat  >= fam.heat_min  and heat  <= fam.heat_max and
             humid >= fam.humid_min and humid <= fam.humid_max then

            local y = heightmap[idx]
            if y and y >= fam.y_min and y <= fam.y_max then
              local px = minp.x + dx
              local pz = minp.z + dz
              local below = area:index(px, y, pz)
              local above = area:index(px, y + 1, pz)

              local cid_above = data[above]
              local cid_below = data[below]

              if ALLOWED[cid_below] then
                local can_place = (cid_above == c_air) or (REPLACE_GRASS and REPL[cid_above])
                if can_place and pr:next(1, fam.chance) == 1 then
                  data[above] = fam.content_ids[pr:next(1, #fam.content_ids)]
                  fam_placed = fam_placed + 1
                end
              end
            end
          end
        end
      end

      total_placed = total_placed + fam_placed
      if DEBUG and fam_placed > 0 then
        minetest.log("action", ("[h3xflowers] chunk (%d,%d)-(%d,%d) family placed: %d")
          :format(minp.x, minp.z, maxp.x, maxp.z, fam_placed))
      end
    end
  end

  vm:set_data(data)
  vm:write_to_map()
  vm:update_map()

  if DEBUG and total_placed == 0 then
    minetest.log("action", ("[h3xflowers] chunk (%d,%d)-(%d,%d): no placements")
      :format(minp.x, minp.z, maxp.x, maxp.z))
  end
end)

-- elysflowers_awards.lua
-- Awards for ElysFlowers + a couple of MTG flowers; includes a “collect them all” meta-award.
-- Depends (optional): awards, flowers
-- Place this file in the elysflowers mod folder (or another mod) and ensure the awards mod is enabled.

local minetest = minetest
if not minetest.global_exists("awards") then
  minetest.log("warning", "[elysflowers_awards] Awards mod not found; skipping award registration.")
  return
end

local S = minetest.get_translator and minetest.get_translator(minetest.get_current_modname() or "elysflowers") or function(s) return s end

-- Utility: only register awards for nodes that actually exist.
local function node_exists(n) return minetest.registered_nodes[n] ~= nil end

-- Species list: each entry is a species-level award. For multi-variant species,
-- list all acceptable nodes so digging any of them grants the species award.
local SPECIES = {
  -- ElysFlowers species (all single-node unless noted)
  { key="indian_paintbrush", title=S("Prairie Painter"), desc=S("Pick an Indian Paintbrush."), nodes={"h3xflowers:indian_paintbrush"}, icon="indian_paintbrush.png" },
  { key="forget_me_not", title=S("Never Forget"), desc=S("Pick a Chinese forget-me-not."), nodes={"h3xflowers:forget_me_not"}, icon="forget_me_not.png" },
  { key="foxglove", title=S("Border Bells"), desc=S("Pick a foxglove."), nodes={"h3xflowers:foxglove"}, icon="foxglove2.png" },
  { key="hibiscus", title=S("Tropical Bloom"), desc=S("Pick a hibiscus."), nodes={"h3xflowers:hibiscus"}, icon="hibiscus_flower.png" },
  { key="larkspur", title=S("Sky Lancer"), desc=S("Pick a larkspur."), nodes={"h3xflowers:larkspur"}, icon="larkspur.png" },
  { key="black_eyed_susan", title=S("Summer’s Eye"), desc=S("Pick a black-eyed Susan."), nodes={"h3xflowers:black_eyed_susan"}, icon="black_eyed_susan.png" },
  { key="phlox", title=S("Cottage Classic"), desc=S("Pick a phlox."), nodes={"h3xflowers:phlox"}, icon="phlox.png" },

  -- Purple Coneflower — any variant counts
  { key="purple_coneflower", title=S("Cone of Power"), desc=S("Pick a purple coneflower."), nodes={"h3xflowers:purple_coneflower","h3xflowers:purple_coneflower_1"}, icon="purple_coneflower_0.png" },

  { key="california_poppy", title=S("Golden State"), desc=S("Pick a California poppy."), nodes={"h3xflowers:california_poppy"}, icon="california_poppy.png" },
  { key="hyacinth", title=S("Spring Perfume"), desc=S("Pick a hyacinth."), nodes={"h3xflowers:hyacinth"}, icon="hyacinth.png" },
  { key="lavender", title=S("Provence Breeze"), desc=S("Pick a lavender sprig."), nodes={"h3xflowers:lavender"}, icon="lavender.png" },
  { key="marshmallow", title=S("Sweet Root"), desc=S("Pick a marshmallow plant."), nodes={"h3xflowers:marshmallow"}, icon="marshmallow_1.png" },
  { key="yarrow_pink", title=S("Healer’s Fronds"), desc=S("Pick a yarrow."), nodes={"h3xflowers:yarrow_pink"}, icon="yarrow.png" },
  { key="african_marigold", title=S("Sunward Bloom"), desc=S("Pick an African marigold."), nodes={"h3xflowers:african_marigold"}, icon="marigold_1.png" },
  { key="arctic_poppy", title=S("Polar Petals"), desc=S("Pick an Arctic poppy."), nodes={"h3xflowers:arctic_poppy"}, icon="arctic_poppy.png" },
  { key="dames_rocket", title=S("Evening Scent"), desc=S("Pick Dame’s rocket."), nodes={"h3xflowers:dames_rocket"}, icon="dames_rocket.png" },
  { key="crocus", title=S("First to Wake"), desc=S("Pick a crocus."), nodes={"h3xflowers:crocus"}, icon="crocus.png" },

  -- Fireweed — any variant counts
  { key="fireweed", title=S("After the Fire"), desc=S("Pick a fireweed."), nodes={"h3xflowers:fireweed","h3xflowers:fireweed_2","h3xflowers:fireweed_3","h3xflowers:fireweed_4"}, icon="fireweed.png" },

  { key="chamomile", title=S("Calm Cup"), desc=S("Pick a chamomile."), nodes={"h3xflowers:chamomile"}, icon="chamomile.png" },
  { key="rose_pogonia", title=S("Bog Orchid"), desc=S("Pick a rose pogonia."), nodes={"h3xflowers:rose_pogonia"}, icon="rose_pogonia.png" },
  { key="yellow_bell", title=S("Desert Bell"), desc=S("Pick a yellow bell."), nodes={"h3xflowers:yellow_bell"}, icon="yellow_bell.png" },
  { key="bergamot", title=S("Bee Favorite"), desc=S("Pick a bergamot."), nodes={"h3xflowers:bergamot"}, icon="bergamot.png" },

  { key="mtg_rose", title=S("Stop and Smell the Roses"), desc=S("Pick a red rose."), nodes={"flowers:rose"}, icon="flowers_rose.png" },
  { key="mtg_dandelion_yellow", title=S("Sunny Dandelion"), desc=S("Pick a yellow dandelion."), nodes={"flowers:dandelion_yellow"}, icon="flowers_dandelion_yellow.png" },
}

-- Build lookup maps and register a per-species award using Awards’ simple `dig` trigger.
-- (API: awards.register_achievement with a trigger { type="dig", node=..., target=1 }). :contentReference[oaicite:1]{index=1}
local NODE_TO_SPECIES = {}
local SPECIES_BY_KEY  = {}
local TOTAL_SPECIES   = 0

for _, sp in ipairs(SPECIES) do
  -- Filter out species whose nodes don’t exist in this game setup.
  local valid_nodes = {}
  for _, n in ipairs(sp.nodes) do
    if node_exists(n) then
      table.insert(valid_nodes, n)
    end
  end
  if #valid_nodes > 0 then
    -- Internal award name
    sp.award_name = "ef_pick_" .. sp.key
    SPECIES_BY_KEY[sp.key] = sp
    TOTAL_SPECIES = TOTAL_SPECIES + 1

    -- Map every acceptable node to this species key (for variants and meta-progress)
    for _, n in ipairs(valid_nodes) do
      NODE_TO_SPECIES[n] = sp.key
    end

    -- Register the visible award with a simple dig trigger on the first valid node
    awards.register_achievement(sp.award_name, {
      title       = sp.title,
      description = sp.desc,
      -- Older docs call this field `image`; some packs use `icon`. Set both.
      image       = sp.icon,
      icon        = sp.icon,
      trigger     = { type = "dig", node = valid_nodes[1], target = 1 },
    })
  else
    minetest.log("action", "[elysflowers_awards] Skipping species with no present nodes: " .. sp.key)
  end
end

-- Meta award: collect every species at least once (from the filtered set above).
-- We grant this ourselves using on_dignode and per-player meta.
awards.register_achievement("ef_pick_all_flowers", {
  title       = S("Flora Completionist"),
  description = S("Pick every flower species in this world."),
  image       = "flowers_flora_complete.png",
  icon        = "flowers_flora_complete.png",
})

local META_KEY = "ef:species_collected"  -- serialized table { [species_key]=true, ... }
local META_DONE = "ef:all_award_given"

minetest.register_on_dignode(function(pos, oldnode, digger)
  if not digger or not oldnode then return end
  local sp_key = NODE_TO_SPECIES[oldnode.name]
  if not sp_key then return end

  local meta = digger:get_meta()
  local raw  = meta:get_string(META_KEY)
  local have = raw ~= "" and minetest.deserialize(raw) or {}
  if type(have) ~= "table" then have = {} end

  if not have[sp_key] then
    have[sp_key] = true
    meta:set_string(META_KEY, minetest.serialize(have))

    -- Ensure the per-species award is granted when the player finds a variant
    -- different from the trigger node.
    local sp = SPECIES_BY_KEY[sp_key]
    if sp and sp.award_name then
      awards.give_achievement(digger:get_player_name(), sp.award_name) -- name, award :contentReference[oaicite:2]{index=2}
    end

    -- Check for completion
    if not meta:get_string(META_DONE) or meta:get_string(META_DONE) == "" then
      local count = 0
      for k,_ in pairs(have) do
        if SPECIES_BY_KEY[k] ~= nil then count = count + 1 end
      end
      if count >= TOTAL_SPECIES then
        awards.give_achievement(digger:get_player_name(), "ef_pick_all_flowers") -- meta-award
        meta:set_string(META_DONE, "1")
      end
    end
  end
end)


