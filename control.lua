local radius_player = 1.8
local radius_vehicle = 3

function sign(x)
    if (x < 0) then return -1 end
    return 1
end

local function can_build(item, player)
    return string.find(item.name, "rail") -- Player can only build rail-related items
       and player.get_item_count(item.name) >= item.count
end

local function try_build_entity(entity, player)
    if entity.valid and entity.type == "entity-ghost" then
        items = entity.ghost_prototype.items_to_place_this

        -- Check if this is an allowed item, and the player has all items, if not fail
        for _, item in pairs(items) do
            if (not can_build(item, player)) then
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
end

local function calculate_length(bounding_box)
    local bb_lt = bounding_box.left_top
    local bb_rb = bounding_box.right_bottom
    return math.max(bb_rb.x - bb_lt.x, bb_rb.y - bb_lt.y)
end

local function get_build_area(player)
    local entity = player.vehicle or player.character

    -- Get some basic values first
    local speed_sign = sign(entity.speed or entity.character_running_speed) -- moving forward or backwards?
    local x = entity.position.x
    local y = entity.position.y

    -- Then calculate some values
    local rad = entity.orientation * 2 * math.pi
    local dir_x = math.sin(rad)
    local dir_y = -math.cos(rad)
    local length = calculate_length(entity.bounding_box)
    local radius = player.vehicle and radius_vehicle or radius_player -- kinda like ternary

    -- Offset the position
    local x = x + dir_x * length * speed_sign
    local y = y + dir_y * length * speed_sign

    -- Create an area around the position
    local area = {
        left_top = { x - radius, y - radius },
        right_bottom = { x + radius, y + radius }
    }
    
    -- Debug draw
    -- rendering.draw_rectangle{
    --     color = {r = 1},
    --     width = 2,
    --     filled = false,
    --     left_top = area.left_top,
    --     right_bottom = area.right_bottom,
    --     surface = 1,
    --     time_to_live = 2
    -- }

    return area
end

local function on_player_changed_position(event)
    local player = game.get_player(event.player_index)

    if (not player.character) then return end

    local entities = player.surface.find_entities(get_build_area(player))
    
    for _, entity in pairs(entities) do
        try_build_entity(entity, player)
    end
end

script.on_event(defines.events.on_player_changed_position, on_player_changed_position)
