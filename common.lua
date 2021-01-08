------------------------------------------------------------------------------------
--     Some small functions that may also be useful in migration scripts etc.     --
------------------------------------------------------------------------------------
log("Entered common.lua of \"" .. script.mod_name .. "\".")

local common = {}

-- This will activate heavy logging because the mod reacts each time the
-- player position changes. Better set these to "false" before release!
local SPAM_THE_LOGFILE = true
local SPAM_THE_GAMECHAT = false


-- The settings won't change during the game, so we can cache this!
local SPAM = SPAM_THE_LOGFILE or SPAM_THE_GAMECHAT

-- Format logging output using string.format()
common.f_log = function(string, ...)
  if SPAM then
    -- Type casting is expensive. Let's format the message just once!
    local msg = string.format(string, ...)

    if SPAM_THE_LOGFILE then
      log(msg)
    end

    if SPAM_THE_GAMECHAT and game then
      game.print(msg)
    end
  end
end

-- Convert a lookup table to an array of strings that can be used as
-- filter for surface.find_entities_filtered
common.make_string_list_from_lookup = function(table)
  local ret = {}
  for string, _ in pairs(table) do
    ret[#ret + 1] = string
  end
  return ret
end

-- Convert an array of strings to a lookup table
common.make_lookup_from_string_list = function(array)
  local ret = {}
  for _, string in pairs(array) do
    ret[string] = true
  end
  return ret
end


-- Match string against a list of patterns. Returns nil if pattern list is {} or nil!
common.check_pattern = function(string, patterns)
  local ret
  for p, pattern in pairs(patterns or {}) do
    if string:match(pattern) then
      ret = true
      common.f_log("\"%s\" matches pattern \"%s\"!", string, pattern)
      break
    end
  end
  return ret
end


------------------------------------------------------------------------------------
--                                       EOF                                      --
------------------------------------------------------------------------------------
return common
