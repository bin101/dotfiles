local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- Execute the event provider binary which auto-detects the active network
-- interface (Wi-Fi or Ethernet) and fires "network_update" every 2.0 seconds.
sbar.exec("killall network_load >/dev/null; $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load network_update 2.0", function() end)

local popup_width = 250
local popup_drawing = false
local label_cache = {}
local current_interface = ""
local current_is_wifi = false
local current_hw_type = "Unknown"

local wifi_up = sbar.add("item", "widgets.wifi.up", {
  position = "right",
  padding_left = -5,
  width = 0,
  icon = {
    padding_right = 0,
    font = {
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    string = icons.wifi.upload,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    color = colors.red,
    string = "??? Bps",
  },
  y_offset = 4,
})

local wifi_down = sbar.add("item", "widgets.wifi.down", {
  position = "right",
  padding_left = -5,
  icon = {
    padding_right = 0,
    font = {
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    string = icons.wifi.download,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    color = colors.blue,
    string = "??? Bps",
  },
  y_offset = -4,
})

local wifi = sbar.add("item", "widgets.wifi_padding", {
  position = "right",
  label = { drawing = false },
})

-- Background around the item
local wifi_bracket = sbar.add("bracket", "widgets.wifi.bracket", {
  wifi.name,
  wifi_up.name,
  wifi_down.name
}, {
  background = { color = colors.bg1 },
  popup = { align = "center", height = 30 }
})

local connection_header = sbar.add("item", "widgets.wifi.connection_header", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    font = {
      style = settings.font.style_map["Bold"]
    },
    string = icons.wifi.router,
  },
  width = popup_width,
  align = "center",
  label = {
    font = {
      size = 15,
      style = settings.font.style_map["Bold"]
    },
    max_chars = 18,
    string = "????????????",
  },
  background = {
    height = 2,
    color = colors.grey,
    y_offset = -15
  }
})

local ssid = sbar.add("item", "widgets.wifi.ssid", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "SSID:",
    width = popup_width / 2,
  },
  label = {
    max_chars = 20,
    string = "????????????",
    width = popup_width / 2,
    align = "right",
  },
  drawing = false,
})

local hostname = sbar.add("item", "widgets.wifi.hostname", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Hostname:",
    width = popup_width / 2,
  },
  label = {
    max_chars = 20,
    string = "????????????",
    width = popup_width / 2,
    align = "right",
  }
})

local ip = sbar.add("item", "widgets.wifi.ip", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "IP:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  }
})

local mask = sbar.add("item", "widgets.wifi.mask", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Subnet mask:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  }
})

local router = sbar.add("item", "widgets.wifi.router", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Router:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  },
})

local iface_item = sbar.add("item", "widgets.wifi.iface", {
  position = "popup." .. wifi_bracket.name,
  icon = {
    align = "left",
    string = "Interface:",
    width = popup_width / 2,
  },
  label = {
    string = "???",
    width = popup_width / 2,
    align = "right",
  },
})

sbar.add("item", "widgets.wifi.padding", { position = "right", width = settings.group_paddings })

-- Resolve the hardware port name for a given BSD interface (e.g. en0 -> Wi-Fi)
local function detect_interface_type(ifname, callback)
  sbar.exec(
    "networksetup -listallhardwareports"
    .. " | grep -B1 'Device: " .. ifname .. "'"
    .. " | grep 'Hardware Port'",
    function(result)
      local hw_type = result:match("Hardware Port: (.+)")
      if hw_type then hw_type = hw_type:gsub("%s+$", "") end
      local is_wifi = hw_type and (hw_type:match("Wi%-Fi") ~= nil) or false
      callback(is_wifi, hw_type or "Unknown")
    end
  )
end

-- Update the bar icon to reflect the current connection type
local function update_icon(ifname)
  if ifname == "none" or ifname == "" then
    wifi:set({
      icon = {
        string = icons.wifi.disconnected,
        color = colors.red,
      },
    })
    return
  end

  detect_interface_type(ifname, function(is_wifi_if, hw_type)
    current_is_wifi = is_wifi_if
    current_hw_type = hw_type

    if is_wifi_if then
      wifi:set({ icon = { string = icons.wifi.connected, color = colors.white } })
    else
      wifi:set({ icon = { string = icons.wifi.ethernet or icons.wifi.connected, color = colors.white } })
    end
  end)

  -- Check for VPN
  sbar.exec("scutil --nc list | grep 'Connected'", function(result)
    if result ~= "" then
      wifi:set({ icon = { string = icons.wifi.vpn, color = colors.white } })
    end
  end)
end

wifi_up:subscribe("network_update", function(env)
  local up_color = (env.upload == "000 Bps") and colors.grey or colors.red
  local down_color = (env.download == "000 Bps") and colors.grey or colors.blue
  wifi_up:set({
    icon = { color = up_color },
    label = {
      string = env.upload,
      color = up_color
    }
  })
  wifi_down:set({
    icon = { color = down_color },
    label = {
      string = env.download,
      color = down_color
    }
  })

  -- React to interface changes reported by the C helper
  local new_if = env.interface or ""
  if new_if ~= current_interface then
    current_interface = new_if
    update_icon(current_interface)
  end
end)

wifi:subscribe({"wifi_change", "system_woke"}, function(env)
  if current_interface ~= "" then
    update_icon(current_interface)
  end
end)

local function hide_details()
  if not popup_drawing then return end
  popup_drawing = false
  wifi_bracket:set({ popup = { drawing = false } })
end

local function toggle_details()
  if not popup_drawing then
    popup_drawing = true
    wifi_bracket:set({ popup = { drawing = true }})

    local ifname = current_interface
    if ifname == "" or ifname == "none" then
      connection_header:set({ label = "No Network" })
      ssid:set({ drawing = false })
      return
    end

    detect_interface_type(ifname, function(is_wifi_if, hw_type)
      current_is_wifi = is_wifi_if
      current_hw_type = hw_type
      connection_header:set({ label = hw_type })
      label_cache[connection_header.name] = hw_type

      -- SSID is only meaningful for Wi-Fi
      ssid:set({ drawing = is_wifi_if })
      if is_wifi_if then
        sbar.exec(
          "ipconfig getsummary " .. ifname
          .. " | awk -F ' SSID : '  '/ SSID : / {print $2}'",
          function(result)
            ssid:set({ label = result })
            label_cache[ssid.name] = result:gsub("%s+$", "")
          end
        )
      end

      -- Subnet mask & router via the hardware port name
      sbar.exec("networksetup -getinfo '" .. hw_type .. "'", function(result)
        local subnet = result:match("Subnet mask: ([^\n]+)")
        local rtr = result:match("Router: ([^\n]+)")
        if subnet then
          mask:set({ label = subnet })
          label_cache[mask.name] = subnet:gsub("%s+$", "")
        end
        if rtr then
          router:set({ label = rtr })
          label_cache[router.name] = rtr:gsub("%s+$", "")
        end
      end)
    end)

    sbar.exec("networksetup -getcomputername", function(result)
      hostname:set({ label = result })
      label_cache[hostname.name] = result:gsub("%s+$", "")
    end)
    sbar.exec("ipconfig getifaddr " .. ifname, function(result)
      ip:set({ label = result })
      label_cache[ip.name] = result:gsub("%s+$", "")
    end)

    iface_item:set({ label = ifname })
    label_cache[iface_item.name] = ifname
  else
    hide_details()
  end
end

wifi_up:subscribe("mouse.clicked", toggle_details)
wifi_down:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.clicked", toggle_details)
wifi:subscribe("mouse.exited.global", hide_details)

local function copy_label_to_clipboard(env)
  local label = label_cache[env.NAME]
  if not label or label == "" then return end
  sbar.exec("echo \"" .. label .. "\" | pbcopy", function() end)
  sbar.set(env.NAME, { label = { string = icons.clipboard, align="center" } })
  sbar.delay(1, function()
    sbar.set(env.NAME, { label = { string = label, align = "right" } })
  end)
end

ssid:subscribe("mouse.clicked", copy_label_to_clipboard)
hostname:subscribe("mouse.clicked", copy_label_to_clipboard)
ip:subscribe("mouse.clicked", copy_label_to_clipboard)
mask:subscribe("mouse.clicked", copy_label_to_clipboard)
router:subscribe("mouse.clicked", copy_label_to_clipboard)
iface_item:subscribe("mouse.clicked", copy_label_to_clipboard)
