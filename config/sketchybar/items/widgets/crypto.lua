local json = require("dkjson")

local colors = require("colors")
local settings = require("settings")

local cryptovalue = sbar.add("item", "widgets.cryptovalue", {
  position = "right",
  background = {
      color = colors.bg2,
      border_color = { alpha = 0 },
      border_width = 1
  },
  icon = { 
    string = "XRP",
    color = colors.white,
    padding_left = 8,
    font = {
      style = settings.font.style_map["Black"],
      size = 12.0,
    },
  },
  label = { 
    string = "Loading...",
    font = { family = settings.font.numbers },
    color = colors.orange,
    padding_left = 8,
    padding_right= 8,
  },
  update_freq = 360,
  click_script = "open -a 'Google Chrome' 'https://www.coingecko.com/en/coins/xrp'",
})

local function fetchCryptoValue()
  -- Non-blocking asynchronous HTTP request using curl
  sbar.exec("curl -s 'https://api.coingecko.com/api/v3/simple/price?ids=ripple&vs_currencies=eur'", function(response, exit_code)
    local label, color
    
    if exit_code == 0 and response and response ~= "" then
      -- Check if response is already a table or needs to be decoded
      local data
      if type(response) == "string" then
        data = json.decode(response)
      elseif type(response) == "table" then
        data = response
      end
      
      if data and data.ripple and data.ripple.eur then
        local value = data.ripple.eur
        label = value .. "€"
        color = colors.green
      else
        label = "Error"
        color = colors.red
      end
    else
      label = "Error"
      color = colors.red
    end
    
    cryptovalue:set({
      label = { 
        string = label,
        color = color,
      },
    })
  end)
end

cryptovalue:subscribe({ "forced", "routine", "system_woke" }, function(env)
    fetchCryptoValue()
end)