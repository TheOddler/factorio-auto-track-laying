local function debug_log(something)
    local str = serpent.block(something)
    game.print(str)
end

local function table_contains(tbl, item)
    for _, value in ipairs(tbl) do
        if value == item then
            return true
        end
    end
    return false
end

local function sign(x)
    -- ~ if (x < 0) then return -1 end
    -- ~ return 1
    -- Just a shorter version
    return (x < 0) and -1 or 1
end

---@param entity LuaEntity
local function calculate_direction(entity)
    local rad = entity.orientation * 2 * math.pi
    return {
        x = math.sin(rad),
        y = -math.cos(rad)
    }
end

local function calculate_length(bounding_box)
    return bounding_box.right_bottom.y - bounding_box.left_top.y
end

---@param entity LuaEntity
---@param distance number
---@return {x: number, y: number}
local function get_point_in_front_of(entity, distance)
    local train = entity.train
    if train then
        local speed_sign = sign(train.speed)
        local train_stock = speed_sign > 0 and train.front_stock or train.back_stock
        entity = train_stock or entity
    end

    -- Get some basic values first
    local speed_sign = sign(entity.speed or entity.character_running_speed) -- moving forward or backwards?
    local x = entity.position.x or entity.position[1]
    local y = entity.position.y or entity.position[2]

    -- Then calculate some values
    local dir = calculate_direction(entity)
    local length = calculate_length(entity.bounding_box) + distance

    -- Return offset position
    return {
        x = x + dir.x * length * speed_sign,
        y = y + dir.y * length * speed_sign
    }
end

-- Build the list of placeable entity types
---@return string[]
local function make_placeable_types_list()
    local types = {
        "rail-support",
        "rail-signal",
        "rail-chain-signal",
        "train-stop",
        -- Some names for compatibility
        -- Bio_Industries
        "bi-power-to-rail-pole",
        -- cargo-ships
        "floating-electric-pole",
    }
    -- Add all the rail types
    local rail_prototypes = prototypes.get_entity_filtered {
        { filter = "rail" }
    }
    for _, p in pairs(rail_prototypes) do
        if not table_contains(types, p.type) then
            table.insert(types, p.type)
        end
    end
    return types
end
local placeable_types = make_placeable_types_list()

local function make_elevated_rail_types_list()
    local types = {}
    for _, type in pairs(placeable_types) do
        if string.find(type, "elevated") ~= nil then
            table.insert(types, type)
        end
    end
    return types
end
local elevated_rail_types = make_elevated_rail_types_list()

---@param entity_to_revive LuaEntity
---@param player LuaPlayer
local function try_revive_entity(entity_to_revive, player)
    local train = player.vehicle and player.vehicle.train
    local vehicle = train or player.vehicle
    local surface = entity_to_revive.surface

    -- When placing one entity, we might want to place tiles under it too, so gather everything we need to place
    local all_entities = {}
    -- Add tiles (landfill, but I guess mods could add other stuff too)
    local tiles_to_place = surface.find_tiles_filtered {
        area = entity_to_revive.bounding_box,
        has_tile_ghost = true,
        force = "player" -- only place stuff from the player
    }
    for _, tile in ipairs(tiles_to_place) do
        for _, ghost in ipairs(tile.get_tile_ghosts()) do
            table.insert(all_entities, ghost)
        end
    end
    -- Add rail supports
    if (table_contains(elevated_rail_types, entity_to_revive.ghost_type)) then
        local rail_supports = surface.find_entities_filtered {
            position = entity_to_revive.position,
            radius = 6,
            ghost_type = "rail-support",
            type = "entity-ghost",
            to_be_deconstructed = false,
            force = "player" -- only place stuff from the player
        }
        for _, rail_support in ipairs(rail_supports) do
            table.insert(all_entities, rail_support)
        end
    end
    -- Add the main entity last so it gets revived last, as it'll need the other found entities to be able to be revived
    table.insert(all_entities, entity_to_revive)

    -- Calculate the whole cost
    local full_cost = {}
    for _, entity in ipairs(all_entities) do
        for _, cost in ipairs(entity.ghost_prototype.items_to_place_this) do
            table.insert(full_cost, cost)
        end
    end

    -- Check that we have the needed items to place the entity
    for _, item in ipairs(full_cost) do
        local still_needed = item.count
        -- By default get_item_count uses normal quality.
        -- TODO: Support other quality levels
        still_needed = still_needed - player.get_item_count(item.name)
        if vehicle then
            still_needed = still_needed - vehicle.get_item_count(item.name)
        end
        if still_needed > 0 then
            -- We are missing at least one thing
            return
        end
    end

    -- Check if there's anything colliding with the entity, and if so remove it if we can
    local stuff_to_remove = surface.find_entities_filtered {
        area = entity_to_revive.bounding_box,
        to_be_deconstructed = true,
        force = "neutral" -- only remove neutral stuff (like trees and rocks)
    }
    for _, to_remove in ipairs(stuff_to_remove) do
        -- When removing stuff, it can happen that a next entity we found gets removed or changed with it.
        -- The time I found this happens is with cliffs, as they can change when they are destroyed.
        -- There might be other cases as well, perhaps in some mod.
        -- So check here that the entity we're trying to remove is still valid.
        if to_remove.valid then
            remove_success = to_remove.mine {
                inventory =
                    player.character
                    and player.character.get_main_inventory(),
                raise_destroyed = true,
            }
            if not remove_success then
                return
            end
        end
    end

    -- Now do the actual reviving:
    for _, entity in ipairs(all_entities) do
        -- Get the cost and type before placing, because after the entity will be invalid
        local cost = entity.ghost_prototype.items_to_place_this
        local ghost_type = entity.ghost_type

        -- Do the actual reviving
        collisions, revived_entity, item_request_proxy = entity.revive {
            raise_revive = true,
            overflow = player.get_main_inventory()
        }

        -- If the reviving was successful, we'll actually take the items
        -- Note that tiles don't have a revived_entity, so we just assume they places successfully
        if (revived_entity or ghost_type == "tile") then
            for _, item in ipairs(cost) do
                local still_to_remove = item.count
                still_to_remove = still_to_remove - player.remove_item({
                    name = item.name,
                    count = item.count,
                    -- TODO: Support other quality levels
                    quality = "normal"
                })
                if still_to_remove > 0 and vehicle then
                    vehicle.remove_item({
                        name = item.name,
                        count = still_to_remove,
                        -- TODO: Support other quality levels
                        quality = "normal"
                    })
                end
            end
        end
    end
end

local function on_player_changed_position(event)
    local player = game.get_player(event.player_index)
    if (not player) then return end

    local entity = player.vehicle or player.character
    if (not entity) then return end
    local surface = entity.surface

    local radius = player.vehicle and 6 or 4
    local position = get_point_in_front_of(entity, radius / 3)

    local stuff_to_place = surface.find_entities_filtered {
        position = position,
        radius = radius,
        ghost_type = placeable_types,
        type = "entity-ghost",
        to_be_deconstructed = false,
        force = "player" -- only place stuff from the player
    }

    -- rendering.draw_circle {
    --     surface = surface,
    --     color = { 1, 0.5, 0 },
    --     target = position,
    --     radius = radius,
    --     time_to_live = 5,
    -- }

    for _, to_place in pairs(stuff_to_place) do
        -- It's possible that while placing stuff other entities become invalid, this seems to happen when placing rail supports.
        -- I'm not 100% sure why, but was able to consistently reproduce by standing on a rail support ghost with a bunch of other random rail and rail support ghosts around me. I think it might be because the entity itself gets changed when another rail support is placed or something like that.
        if to_place.valid then
            try_revive_entity(to_place, player)
        end
    end
end

script.on_event(defines.events.on_player_changed_position, on_player_changed_position)
