local http = require("socket.http")
local json = require("dkjson")

local colors = require("colors")
local settings = require("settings")

local label = "Loading..."
local color = colors.orange

local cryptovalue = sbar.add("item", "widgets.cryptovalue", {
  position = "right",
  icon = { drawing = false },
  label = { 
    font = { family = settings.font.numbers },
    string = label,
    color = color,
    padding_left = 8,
    padding_right= 8,
  },
  update_freq = 360,
  click_script = "open -a 'Google Chrome' 'https://www.coingecko.com/en/coins/xrp'",
})

local function fetchCryptoValue()
  local response, status = http.request("https://api.coingecko.com/api/v3/simple/price?ids=ripple&vs_currencies=eur")
  if status == 200 then
    local data = json.decode(response)
    local value = data.ripple.eur
    label = "XRP: " .. value .. "€"
    color = colors.green
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
end

cryptovalue:subscribe({ "forced", "routine", "system_woke" }, function(env)
    fetchCryptoValue()
end)