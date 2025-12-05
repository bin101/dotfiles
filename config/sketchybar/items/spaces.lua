local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

-- Table to keep track of created workspaces
local workspaces = {}

local function updateSpaceWindows(space, space_name)
  sbar.exec("aerospace list-windows --format %{app-name} --workspace " .. space_name, function(windows)
    local no_app = true
    local icon_line = ""
    for app in windows:gmatch("[^\r\n]+") do
      no_app = false
      local lookup = app_icons[app]
      local icon = ((lookup == nil) and app_icons["default"] or lookup)
      icon_line = icon_line .. " " .. icon
    end

    if (no_app) then
      icon_line = "—"
    end
    sbar.animate("tanh", 10, function()
      space:set({ label = icon_line })
    end)
  end)
end

local function createWorkspace(space_name)
  if workspaces[space_name] then
    return -- Workspace already exists
  end

  local space = sbar.add("item", "space." .. space_name, {
    icon = {
      font = { family = settings.font.numbers },
      string = space_name,
      padding_left = 7,
      padding_right = 3,
      color = colors.white,
      highlight_color = colors.red,
    },
    label = {
      padding_right = 12,
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:16.0",
      y_offset = -1,
    },
    padding_right = 1,
    padding_left = 1,
    background = {
      color = colors.bg1,
      border_width = 1,
      height = 26,
      border_color = colors.black,
    }
  })

  local space_bracket = sbar.add("bracket", { space.name }, {
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 28,
      border_width = 2
    }
  })

  -- Padding space
  local space_padding = sbar.add("item", "space.padding." .. space_name, {
    script = "",
    width = settings.group_paddings,
  })

  -- Store workspace info
  workspaces[space_name] = {
    space = space,
    bracket = space_bracket,
    padding = space_padding
  }

  -- Check if this workspace is currently focused
  sbar.exec("aerospace list-workspaces --focused", function(focused_workspace)
    local is_focused = focused_workspace:match("^%s*(.-)%s*$") == space_name
    if is_focused then
      space:set({
        icon = { highlight = true, },
        label = { highlight = true },
        background = { border_color = colors.black }
      })
      space_bracket:set({
        background = { border_color = colors.grey }
      })
    end
  end)

  -- custom trigger
  space:subscribe("aerospace_workspace_change", function(env)
    local selected = env.FOCUSED_WORKSPACE == space_name
    space:set({
      icon = { highlight = selected, },
      label = { highlight = selected },
      background = { border_color = selected and colors.black or colors.bg2 }
    })
    space_bracket:set({
      background = { border_color = selected and colors.grey or colors.bg2 }
    })
  end)

  space:subscribe("mouse.clicked", function()
    sbar.exec("aerospace workspace " .. space_name)
  end)

  space:subscribe("space_windows_change", function()
    updateSpaceWindows(space, space_name)
  end)

  -- initial setup
  updateSpaceWindows(space, space_name)

  -- Reorder items
  reorderWorkspaces()
end

local function removeWorkspace(space_name)
  local ws = workspaces[space_name]
  if not ws then
    return -- Workspace doesn't exist
  end

  -- Remove the items
  sbar.remove(ws.space.name)
  sbar.remove(ws.bracket.name)
  sbar.remove(ws.padding.name)

  -- Remove from tracking table
  workspaces[space_name] = nil

  -- Reorder remaining items
  reorderWorkspaces()
end

function reorderWorkspaces()
  local item_order = ""

  -- Get all workspace names and sort them
  local workspace_names = {}
  for name, _ in pairs(workspaces) do
    table.insert(workspace_names, name)
  end
  table.sort(workspace_names)

  -- Build the order string
  for _, name in ipairs(workspace_names) do
    local ws = workspaces[name]
    item_order = item_order .. " " .. ws.space.name .. " " .. ws.padding.name
  end

  if item_order ~= "" then
    sbar.exec("sketchybar --reorder apple " .. item_order .. " front_app")
  end
end

local function updateWorkspaces()
  sbar.exec("aerospace list-workspaces --all", function(spaces_output)
    local current_spaces = {}

    -- Collect all current workspaces
    for space_name in spaces_output:gmatch("[^\r\n]+") do
      current_spaces[space_name] = true
      createWorkspace(space_name)
    end

    -- Remove workspaces that no longer exist
    for space_name, _ in pairs(workspaces) do
      if not current_spaces[space_name] then
        removeWorkspace(space_name)
      end
    end
  end)
end

-- Initial workspace setup
updateWorkspaces()
