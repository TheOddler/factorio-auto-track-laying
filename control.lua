local function debug_log(something)
    local str = serpent.block(something)
    game.print(str)
end

local function sign(x)
    -- ~ if (x < 0) then return -1 end
    -- ~ return 1
    -- Just a shorter version
    return (x < 0) and -1 or 1
end

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
---@return {x: number, y: number}
local function get_point_in_front_of(entity)
    -- Get some basic values first
    local speed_sign = sign(entity.speed or entity.character_running_speed) -- moving forward or backwards?
    local x = entity.position.x or entity.position[1]
    local y = entity.position.y or entity.position[2]

    -- Then calculate some values
    local dir = calculate_direction(entity)
    local length = calculate_length(entity.bounding_box)

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
        table.insert(types, p.type)
    end
    return types
end
local placeable_types = make_placeable_types_list()

---@param main_entity LuaEntity
---@param player LuaPlayer
local function try_revive_entity(main_entity, player)
    local vehicle = player.vehicle and player.vehicle.train or player.vehicle
    local surface = main_entity.surface

    -- When placing one entity, we might want to place tiles under it too, so gather everything we need to place
    local all_entities = {}
    local tiles_to_place = surface.find_tiles_filtered {
        area = main_entity.bounding_box,
        has_tile_ghost = true,
        force = "player" -- only place stuff from the player
    }
    rendering.draw_rectangle {
        surface = surface,
        color = { 1, 0.5, 0 },
        left_top = main_entity.bounding_box.left_top,
        right_bottom = main_entity.bounding_box.right_bottom,
        time_to_live = 5,
    }
    for _, tile in ipairs(tiles_to_place) do
        for _, ghost in ipairs(tile.get_tile_ghosts()) do
            table.insert(all_entities, ghost)
        end
    end
    table.insert(all_entities, main_entity) -- Add it last so it gets places last, as the tiles will need to be placed before this can

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
        area = main_entity.bounding_box,
        to_be_deconstructed = true,
        force = "neutral" -- only remove neutral stuff (like trees and rocks)
    }
    for _, to_remove in ipairs(stuff_to_remove) do
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
    local position = get_point_in_front_of(entity)

    local radius = 10

    local stuff_to_place = surface.find_entities_filtered {
        position = position,
        radius = radius,
        ghost_type = placeable_types,
        type = "entity-ghost",
        to_be_deconstructed = false
    }

    rendering.draw_circle {
        surface = surface,
        color = { 1, 0.5, 0 },
        target = position,
        radius = radius,
        time_to_live = 5,
    }

    for _, to_place in pairs(stuff_to_place) do
        try_revive_entity(to_place, player)
    end
end

script.on_event(defines.events.on_player_changed_position, on_player_changed_position)
