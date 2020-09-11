local radius_player = 2
local radius_vehicle = 3
local allowed_ghost_names = {"straight-rail", "curved-rail", "rail-signal", "rail-chain-signal"}

function sign(x)
    if (x < 0) then return -1 end
    return 1
end

local function try_revive_entity(entity, player)
    items = entity.ghost_prototype.items_to_place_this

    -- Check if the player has all items, if not fail
    for _, item in pairs(items) do
        if (player.get_item_count(item.name) < item.count) then
            return false
        end
    end

    -- Try to revive
    success = entity.revive()

    if (success) then
        -- Actually remove items from player inventory
        for _, item in pairs(items) do
            player.remove_item(item)
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
    local x = entity.position.x
    local y = entity.position.y

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

    if (not entity) then return end

    local radius = player.vehicle and radius_vehicle or radius_player -- kinda like ternary
    local position = get_point_in_front_of(entity)

    local entities = player.surface.find_entities_filtered{
        position = position,
        radius = radius,
        ghost_name = allowed_ghost_names,
        type = "entity-ghost"
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
            try_revive_entity(entity, player)
        end
    end
end

script.on_event(defines.events.on_player_changed_position, on_player_changed_position)
