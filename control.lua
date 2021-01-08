log("Entered control.lua of \"" .. script.mod_name .. "\".")

-- Add common functions that may also be called from other files, for example if you
-- ever have to make a migration script.
ATL = require("__" .. script.mod_name .. "__.common")

-- Add support for the Lua API global Variable Viewer (gvv)
if script.active_mods["gvv"] then
    log("Activating support for gvv!")
    require("__gvv__/gvv")()
end

-- Set search radius for player and player in vehicle
local radius_player = 2
local radius_vehicle = 3

-- These are the obviously rail-related prototypes that we always want! We need them
-- to get a list of prototype names and for entity searches later on. It may seem
-- more complicated than necessary, but can be easily extended.
-- Key:   Name of the filter used by game.get_filtered_entity_prototypes(), see: https://lua-api.factorio.com/latest/Concepts.html#EntityPrototypeFilters
-- Value: Array of prototype types we are looking for with that filter
local rail_types = {
    ["rail"] = {"straight-rail", "curved-rail"},
    ["type"] = {"rail-signal", "rail-chain-signal", "train-stop"}
}

-- These are prototypes that should be placed on account of other mods.
-- Key:   Mod name
-- Value: Table with
--          Key:   Prototype type needed by the mod
--          Value: Array of prototype names from the mod that are based on that type
local compatibility_types = {
    -- Bio Industries: Power-to-rail connector
    ["Bio_Industries"] = {
        ["electric-pole"] = {"bi-power-to-rail-pole"}
    },
    -- Cargo Ships: Floating electric pole
    ["cargo-ships"] = {
        ["electric-pole"] = {"floating-electric-pole"}
    }
}
-- You may want to add an ignore list. You could even provide a remote interface
-- other mods could use to add their entities to the compatibility and ignore lists!

-- If you want to make more complex filters, add more filter conditions!
-- Caveat: These restrictions will apply to all filters. The final filter
-- list will work like this:
-- ({filter = rail} AND restrictions[1] … AND restrictions[n]) OR
-- ({filter = "type", type = "rail-signal"} AND restrictions[1] … AND restrictions[n]) …
local restrictions = {{
    filter = "flag",
    flag = "not-blueprintable",
    invert = true,
    mode = "and"
}}

-- Array of the filters for the default rail-related entities
local rail_prototype_filters

-- There are some kinds of obstacles that prevent placing our ghosts:
-- e.g. cliffs, trees, and rocks (add more if you like!).
-- ghost_patterns:  Prototype names must match a pattern from this list
-- ignore_patterns: Prototype names that match a pattern from this list
--                  won't be removed!
local obstacle_prototype_filters = {
    -- Leave cliffs for now -- they can't be mined, but must be exploded!
    -- ~ ["cliff"] = {
    -- ~ ghost_patterns = {"^.+$"},
    -- ~ ignore_patterns = {}
    -- ~ },
    ["tree"] = {
        ghost_patterns = {"^.+$"},
        ignore_pattern = {}
    },
    -- Rocks are based on "simple-entity", but so are spaceship debris and
    -- crash-site entities. Some mod could make a simple-entity matching
    -- "rocket", so we'd better ignore this!
    ["simple-entity"] = {
        ghost_patterns = {"rock"},
        ignore_patterns = {"rocket"}
    }
}

-- Construct the filters we need for finding the prototype names used per default
local function get_rail_prototype_filters()
    local filters = {}

    local function add_restrictions()
        for _, restriction in ipairs(restrictions) do
            filters[#filters + 1] = restriction
        end
    end

    for filter_name, filter_prototypes in pairs(rail_types) do
        -- Filtering by "type", "name" etc. requires additional fields
        if filter_name == "type" or filter_name == "name" then
            -- Make filter for each prototype in the list!
            for p, prototype in ipairs(filter_prototypes) do
                filters[#filters + 1] = {
                    ["filter"] = filter_name, -- e.g. {filter = "type"}
                    [filter_name] = prototype -- e.g. {type = "rail-signal"}
                    
                }
                add_restrictions()
            end
            -- Otherwise, use just the filter
        else
            filters[#filters + 1] = {
                ["filter"] = filter_name
            }
            add_restrictions()
        end
    end

    ATL.f_log("Filters for prototype name search: %s", serpent.block(filters))

    return filters
end

-- Construct a list of allowed ghost types
local function get_ghost_types()
    -- This will be the final array of strings with the prototype types
    local type_list = {}
    -- This will be indexed by prototype type, to make sure we don't add
    -- the same strings repeatedly!
    local tmp = {}

    -- Get the default types as lookup table
    for t, types in pairs(rail_types) do
        for r, rtype in ipairs(types) do
            tmp[rtype] = true
        end
    end
    ATL.f_log("Default types: %s", serpent.block(tmp))

    -- Get the types needed by other mods
    for mod_name, mod_needs in pairs(compatibility_types) do
        -- Check if the mod is active before adding its stuff!
        if script.active_mods[mod_name] then
            -- Add needed prototype types to temporary list
            for p_type, p_names in pairs(mod_needs) do
                if not tmp[p_type] then
                    tmp[p_type] = true
                    ATL.f_log("%s: Added %s to list of prototype types", mod_name, p_type)
                end
            end
        end
    end
    ATL.f_log("Default types + mod types: %s", serpent.block(tmp))

    -- We need an array of strings for filtering!
    type_list = ATL.make_string_list_from_lookup(tmp)

    ATL.f_log("Will look for these prototype types: %s", serpent.line(type_list))
    return type_list
end

-- Make a list of all prototypes that are stored in rail_types or compatibility_types
local function get_ghost_names()
    local rail_types = game.get_filtered_entity_prototypes(rail_prototype_filters)

    local ret = {}

    -- Get default prototype names (rail-related)
    ATL.f_log("Found %g rail-related prototypes", #rail_types)
    for rail_type, r in pairs(rail_types) do
        ATL.f_log("rail_type: \"%s\"", rail_type)

        -- Add names of rails, signals etc. to list of allowed ghost names!
        ret[#ret + 1] = rail_type
    end

    -- Get prototypes needed by other mods
    for mod_name, mod_needs in pairs(compatibility_types) do
        -- ~ ATL.f_log("%s: %s", mod_name, serpent.line(mod_needs))
        -- Check if mod is active
        if script.active_mods[mod_name] then
            -- Check prototype types
            for p_type, p_names in pairs(mod_needs) do
                for p, p_name in ipairs(p_names) do
                    ret[#ret + 1] = p_name
                    ATL.f_log("%s (%g): Added %s (%s)", mod_name, p, p_name, p_type)
                end
            end
        end
    end
    ATL.f_log("Looking for entity ghosts with these names: %s", serpent.block(ret))

    return ret
end

-- Build the default filters just once
rail_prototype_filters = get_rail_prototype_filters()
ATL.f_log("rail_prototype_filters: %s", serpent.line(rail_prototype_filters))

local function make_obstacle_lists()
    local tmp, found
    local ret = {}

    for prototype_type, filters in pairs(obstacle_prototype_filters) do
        tmp = {}
        ATL.f_log("Looking for prototypes of type %s", prototype_type)
        -- Find all prototypes based on this type
        found = game.get_filtered_entity_prototypes({{
            filter = "type",
            type = prototype_type
        }})
        ATL.f_log("Found %g entities", #found)
        -- Check the found prototypes
        for p, prototype in pairs(found) do
            ATL.f_log("%s:  %s", p, prototype.name)

            -- Add prototype name to lookup list if it matches one of the ghost_patterns!
            -- (ATL.check_pattern will return true or nil)
            tmp[prototype.name] = ATL.check_pattern(prototype.name, filters.ghost_patterns)
            ATL.f_log("tmp[%s]:  %s", prototype.name, tmp[prototype.name])
            -- We only need to check the ignore list if there was a match!
            if tmp[prototype.name] and ATL.check_pattern(prototype.name, filters.ignore_patterns) then
                tmp[prototype.name] = nil
                ATL.f_log("Removed %s from list again!", prototype.name)
            end
        end

        ret[prototype_type] = ATL.make_string_list_from_lookup(tmp)
    end
    ATL.f_log("Return: %s", serpent.block(ret))
    return ret
end

local function sign(x)
    -- ~ if (x < 0) then return -1 end
    -- ~ return 1
    -- Just a shorter version
    return (x < 0) and -1 or 1
end

local function try_revive_entity(entity, player)
    local items = entity.ghost_prototype.items_to_place_this

    local vehicle = player and player.vehicle
    local train = vehicle and vehicle.train

    -- Item count for items of player and vehicle
    local p_items, v_items
    local item_map = {}
    item_map.player = {}
    item_map.vehicle = {}

    ATL.f_log("Need these items: %s", serpent.line(items))
    ATL.f_log("Player is in a vehicle: %s", vehicle and vehicle.name or false)
    ATL.f_log("Player is in a train with this cargo: %s", serpent.block(train and train.get_contents() or "empty"))
    ATL.f_log("Vehicle contents: %s", serpent.line(vehicle and vehicle.get_item_count() or "empty"))

    -- Check if the player has all items, if not fail
    -- ~ for _, item in pairs(items) do
    -- ~ if (player.get_item_count(item.name) < item.count) then
    -- ~ return false
    -- ~ end
    -- ~ end
    for i, item in ipairs(items) do
        -- Check if player has enough items
        p_items = player.get_item_count(item.name)
        item_map.player[item.name] = (p_items >= item.count) and item.count or (p_items > 0) and p_items or nil
        ATL.f_log("Player has %g of %s.", p_items, item.name)

        -- Player doesn't have enough items. Check vehicle!
        if p_items < item.count then
            ATL.f_log("Not enough %s. Checking vehicle!", item.name)

            -- If the player is on a train, "vehicle" will be just the locomotive
            -- or wagon he's riding in, and "train" will be the complete train.
            v_items = train and train.get_item_count(item.name) or vehicle and vehicle.get_item_count(item.name)

            if not v_items or -- Player is not in a vehicle
            ((v_items < item.count) and -- Vehicle doesn't have enough items
            (p_items + v_items < item.count) -- Even combined, there's not enough!
             -- Even combined, there's not enough!
            ) then
                ATL.f_log("Not enough %s. Returning immediately!", item.name)
                return false
                -- Take from player first, get the rest from the vehicle
            else
                item_map.vehicle[item.name] = item.count - p_items
                ATL.f_log("Got enough %s!", item.name)
            end
        end
    end
    ATL.f_log("item_map: %s", serpent.block(item_map))

    -- Try to revive
    local success = entity.revive({
        raise_revive = true
    })
    ATL.f_log("Tried to revive entity with this result: %s", serpent.block(success))
    if (success) then
        -- Return values of entity.remove_item
        local removed
        -- ~ -- Actually remove items from player inventory
        -- ~ for _, item in pairs(items) do
        -- ~ player.remove_item(item)
        -- ~ end
        -- Actually remove items from inventories
        -- Remove from player
        for item_name, item_count in pairs(item_map.player or {}) do
            removed = player.remove_item({
                name = item_name,
                count = item_count
            })
            ATL.f_log("Removed %g %s from player.", removed, item_name)
        end

        -- Remove from train or vehicle
        for item_name, item_count in pairs(item_map.vehicle or {}) do
            -- Train
            if train then
                removed = train.remove_item({
                    name = item_name,
                    count = item_count
                })
                ATL.f_log("Removed %g %s from train %g.", removed, item_name, train.id)
                -- Vehicle
            elseif vehicle then
                removed = vehicle.remove_item({
                    name = item_name,
                    count = item_count
                })
                ATL.f_log("Removed %g %s from %s (%g).", removed, item_name, vehicle.name, vehicle.unit_number)
            end
        end

        -- Could not revive the ghost. Is there a rock or tree in the way?
    else
        ATL.f_log("Couldn't place \"%s\". Check what's in the way!", entity.ghost_name)
        local obstacles = entity.surface.find_entities_filtered(
                              {
                position = entity.position,
                radius = 2,
                type = global.removable.filter.type,
                name = global.removable.filter.name
            })
        ATL.f_log("Found %s obstacles", #obstacles)

        -- We want to mine this. Make a temporary inventory to store the items,
        -- we then can distribute them to player/vehicle/train or spill them on
        -- the ground.
        -- We always want to keep one spare stack because we don't know how many
        -- different types of items we will mine, and how many stacks. (Mods could
        -- set mining_results to whatever insane value they want!) So, let's create
        -- 2 slots right away, and add another slot if none is empty.
        local inventory = game.create_inventory(2)

        local remaining, stack, position

        for o, obstacle in ipairs(obstacles or {}) do
            ATL.f_log("Mining %s", obstacle.name)
            position = obstacle.position
            -- Mine the obstacle until all items are in the inventory
            while obstacle.valid and obstacle.mine({
                inventory = inventory
            }) do
                -- Make sure there's at least one empty slot!
                if inventory.count_empty_stacks() == 0 then
                    inventory.resize(#inventory + 1)
                    ATL.f_log("Resized inventory!")
                end
            end
            ATL.f_log("Mined: %s", serpent.block(inventory.get_contents()))

            -- Distribute mined items (train/vehicle first, then player, then spill)
            for item, count in pairs(inventory.get_contents()) do
                -- entity.insert(stack) will insert as much as possible, so we don't need to
                -- adjust stack.count, but can always use the original count!
                stack = {
                    name = item,
                    count = count
                }

                -- Try to unload
                for a, add_to in pairs({
                    train = train,
                    vehicle = vehicle,
                    player = player
                }) do
                    -- The thing we want to unload to exists, and nothing has been inserted yet
                    -- (remaining == nil) or not everything has been inserted (remaining > 0)
                    if add_to and not remaining or remaining > 0 then
                        remaining = count - add_to.insert(stack)
                    end
                    ATL.f_log("Remaining after trying to insert %s into %s (%s): %s", item,
                        (a == "train" and a) or (a == "vehicle" and vehicle.name) or player.name, (a == "train" and
                            train.id) or (a == "vehicle" and vehicle.unit_number) or player.index, remaining)
                    -- Got rid of everything, no need to go on
                    if remaining == 0 then
                        break
                    end
                end

                -- Spill any items we still have!
                if not remaining or remaining > 0 then
                    ATL.f_log("MUST SPILL NOW!")
                    player.surface.spill_item_stack(position, {
                        name = stack.name,
                        count = remaining or stack.count
                    }, true, -- enable_looted (Can be picked up by walking over it)
                    player.force, -- Items will be marked for deconstruction by this force
                    false -- Whether items can be spilled onto belts
                    )
                end
            end
            ATL.f_log("Inventory size: %s, Mined: %s", #inventory, serpent.block(inventory.get_contents()))
            inventory.destroy()
        end
    end

    return success
end

local function calculate_length(bounding_box)
    return bounding_box.right_bottom.y - bounding_box.left_top.y
end

local function calculate_direction(entity)
    local rad = entity.orientation * 2 * math.pi
    return {
        x = math.sin(rad),
        y = -math.cos(rad)
    }
end

local function get_point_in_front_of(entity)
    -- Get some basic values first
    local speed_sign = sign(entity.speed or entity.character_running_speed) -- moving forward or backwards?
    local x = entity.position.x or entity.position[1]
    local y = entity.position.y or entity.position[2]

    -- Then calculate some values
    local rad = entity.orientation * 2 * math.pi
    local dir = calculate_direction(entity)
    local length = calculate_length(entity.bounding_box)

    -- Offset the position
    local x = x + dir.x * length * speed_sign
    local y = y + dir.y * length * speed_sign

    return {
        x = x,
        y = y
    }
end

local function on_player_changed_position(event)
    local player = game.get_player(event.player_index)
    local entity = player.vehicle or player.character

    if (not entity) then
        return
    end

    -- The entity could be a vehicle which is a locomotive or wagon at
    -- any position in a train. In this case, you will need the position
    -- of the first loco/wagon from the direction the train is moving!
    local train = entity.train
    if train then
        ATL.f_log("Player is riding on train %s in a %s (%s).", train.id, entity.name, entity.unit_number)
        -- ~ for k,v in pairs(train.carriages) do
        -- ~ ATL.f_log("%s: %s (%s)", k, v.name, v.unit_number)
        -- ~ end

        -- We only need to find the front entity if the train consists of
        -- several rolling stock (locomotives and/or wagons). If the player
        -- changed position because he entered a stopped train, we do nothing.
        if (#train.carriages > 1) and (train.speed ~= 0) then
            -- ~ ATL.f_log("Count of rolling stock: %s", #train.carriages)
            ATL.f_log("Train is moving %s", train.speed > 0 and "forwards" or "backwards")

            entity = train.speed > 0 and train.front_stock or train.back_stock
        end
    end

    ATL.f_log("Looking for ghosts ahead of %s (%s)", entity.name, entity.unit_number)

    local radius = player.vehicle and radius_vehicle or radius_player -- kinda like ternary
    
    local position = get_point_in_front_of(entity)

    -- ~ local entities = player.surface.find_entities_filtered{
    -- ~ position = position,
    -- ~ radius = radius,
    -- ~ ghost_type = allowed_ghost_types,
    -- ~ type = "entity-ghost",
    -- ~ collision_mask = "ghost-layer"
    -- ~ }
    local entities = player.surface.find_entities_filtered {
        position = position,
        radius = radius,
        ghost_type = global.allowed_ghost_types,
        ghost_name = global.allowed_ghost_names,
        type = "entity-ghost",
        collision_mask = "ghost-layer"
    }

    -- Debug draw
    -- rendering.draw_circle{
    --     color = {r = 1},
    --     width = 2,
    --     filled = false,
    --     target = position,
    --     radius = radius,
    --     surface = 1,
    --     time_to_live = 2
    -- }

    for _, entity in pairs(entities) do
        if entity.valid then
            ATL.f_log("Trying to revive %s", entity.ghost_name)
            -- ~ try_revive_entity(entity, player)
            local revived = try_revive_entity(entity, player)
            ATL.f_log("Returned from try_revive_entity with this result: %s", serpent.block(revived))
        end
    end
end

-- We want to cache a list of allowed entity names.
local function init(event)
    ATL.f_log("Entered function init(%s)", serpent.block(event))

    global = global or {}
    global.allowed_ghost_types = get_ghost_types()
    global.allowed_ghost_names = get_ghost_names()

    global.removable = make_obstacle_lists()
    local types, names = {}, {}
    for prototype_type, prototype_names in pairs(global.removable) do
        types[#types + 1] = prototype_type
        for p, prototype_name in ipairs(prototype_names) do
            names[#names + 1] = prototype_name
        end
    end
    ATL.f_log("Types: %s\nNames: %s", serpent.line(types), serpent.line(names))
    global.removable.filter = {
        type = types,
        name = names
    }

end

script.on_event(defines.events.on_player_changed_position, on_player_changed_position)

-- Will be triggered on starting a new game or when this mod is added to an old game.
script.on_init(init)

-- Will be triggered when mods are added/removed/updated or when settings have changed.
script.on_configuration_changed(init)

------------------------------------------------------------------------------------
--                    FIND LOCAL VARIABLES THAT ARE USED GLOBALLY                 --
--                              (Thanks to eradicator!)                           --
------------------------------------------------------------------------------------
setmetatable(_ENV, {
    __newindex = function(self, key, value) -- locked_global_write
        error('\n\n[ER Global Lock] Forbidden global *write*:\n' .. serpent.line {
            key = key or '<nil>',
            value = value or '<nil>'
        } .. '\n')
    end,
    __index = function(self, key) -- locked_global_read
        if (key ~= "game" and key ~= "mods") then
            error('\n\n[ER Global Lock] Forbidden global *read*:\n' .. serpent.line {
                key = key or '<nil>'
            } .. '\n')
        end
    end
})
