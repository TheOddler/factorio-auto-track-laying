local radius = 2

local function can_build(item, player)
    return string.find(item.name, "rail") -- Player can only build rail-related items
       and player.get_item_count(item.name) >= item.count
end

local function try_build_entity(entity, player)
    if entity.type == "entity-ghost" then
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

local function get_build_area(player)
    return {
        {player.position.x - radius, player.position.y - radius},
        {player.position.x + radius, player.position.y + radius}
    }
end

local function on_player_changed_position(event)
    local player = game.get_player(event.player_index)
    local entities = player.surface.find_entities(get_build_area(player))
    
    for _, entity in pairs(entities) do
        try_build_entity(entity, player)
    end
end

script.on_event(defines.events.on_player_changed_position, on_player_changed_position)
