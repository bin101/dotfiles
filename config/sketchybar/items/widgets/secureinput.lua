local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

-- Execute the event provider binary which provides the event "secure_input_update"
-- for the secure input status data, which is fired every 2.0 seconds.
sbar.exec("killall secure_input >/dev/null; $CONFIG_DIR/helpers/event_providers/secure_input/bin/secure_input secure_input_update 2.0")

local label = icons.error
local color = colors.orange
local current_app_name = "None"
local current_secure_state = false

local secureinput = sbar.add("item", "widgets.secureinput", {
  position = "right",
  icon = { drawing = false },
  label = { 
    font = { family = settings.font.numbers },
    string = label,
    color = color,
    padding_left = 8,
    padding_right= 8,
  },
  popup = { align = "right" }
})

local secureinputbracket = sbar.add("bracket", "widgets.secureinput.bracket", { secureinput.name }, {
  background = { 
    color = colors.bg1,
    border_color = color,
    border_width = 1,
  }
})

local popup_info = sbar.add("item", "widgets.secureinput.popup_info", {
  position = "popup." .. secureinput.name,
  label = {
    string = "Secure Input Inactive",
    width = 250,
    align = "center",
    color = colors.green,
  },
})

local function setSecureInput(enabled)
  current_secure_state = enabled
  if enabled then
    label = icons.locked
    color = colors.red
  else
    label = icons.unlocked
    color = colors.green
  end
  secureinput:set({
    label = { 
      string = label,
      color = color,
    },
  })
  secureinputbracket:set({
    background = {
      border_color = color,
    }
  })
end

secureinput:subscribe("secure_input_update", function(env)
  -- Event provides: env.enabled, env.process_count, env.process_names, env.process_pids
  local is_secure = env.enabled == "true"
  local process_count = tonumber(env.process_count) or 0
  local process_names = env.process_names or ""
  local process_pids = env.process_pids or ""
  
  setSecureInput(is_secure)
  
  -- Update popup info
  if is_secure then
    local status_text = "Secure Input Active"
    if process_count > 0 and process_names ~= "" then
      status_text = process_names:gsub(",", ", ")
    end
    popup_info:set({
      label = {
        string = status_text,
        color = colors.red,
      }
    })
  else
    popup_info:set({
      label = {
        string = "Secure Input Inactive",
        color = colors.green,
      }
    })
  end
end)

secureinput:subscribe("mouse.clicked", function()
  secureinput:set( { popup = { drawing = "toggle" } })
end)

sbar.add("item", "widgets.secureinput.padding", {
  position = "right",
  width = settings.group_paddings,
})
