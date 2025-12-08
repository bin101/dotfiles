local colors     = require("colors")
local settings   = require("settings")
local app_icons  = require("helpers.app_icons")
local cjson      = require("cjson")

local json       = cjson.new()
local aerospace  = sbar.aerospace
local workspaces = {}
local icon_cache = {}

-- Initial padding item
sbar.add("item", "aerospace.padding", { position = "left", width = settings.group_paddings })

-- Create a hidden item to subscribe to workspace change events
local workspace_watcher = sbar.add("item", "aerospace.eventlistener", {
  drawing = false,
  updates = true,
})

local function getAppIcon(appName)
    if icon_cache[appName] then
        return icon_cache[appName]
    end
    local icon = app_icons[appName] or app_icons["default"] or "?"
    icon_cache[appName] = icon
    return icon
end

local function updateSpaceWindows(space, space_name)
    aerospace:list_windows(space_name, function(windows_json)
        local windows = json.decode(windows_json)
        local hasApps = windows and #windows > 0
        local icon_line = ""

        if hasApps then
            for _, window in ipairs(windows) do
                if window["app-name"] then
                    local icon = getAppIcon(window["app-name"])
                    icon_line = icon_line .. " " .. icon
                end
            end
        else
            icon_line = "—"
        end

        sbar.animate("tanh", 10, function()
            space:set({ label = icon_line })
        end)
    end)
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
        item_order = item_order .. " " .. ws.item.name .. " " .. ws.bracket.name .. " " .. ws.padding.name
    end

    if item_order ~= "" then
        sbar.exec("sketchybar --reorder aerospace.padding aerospace.eventlistener " .. item_order .. " front_app")
    end
end

local function createWorkspace(space_name, isFocused)
    local spaceId = "aerospace.space_" .. space_name

    if workspaces[spaceId] then
        return spaceId
    end

    local space = sbar.add("item", spaceId, {
        icon = {
            font = { family = settings.font.numbers },
            string = space_name,
            padding_left = 7,
            padding_right = 3,
            color = colors.white,
            highlight = isFocused,
            highlight_color = colors.red,
        },
        label = {
            padding_right = 12,
            color = colors.grey,
            highlight = isFocused,
            highlight_color = colors.white,
            font = "sketchybar-app-font:Regular:16.0",
            y_offset = -1,
        },
        background = {
            color = colors.bg1,
            border_width = 1,
            height = 26,
            border_color = isFocused and colors.black or colors.bg2,
        },
        padding_right = 1,
        padding_left = 1,
    })

    local space_bracket = sbar.add("bracket", spaceId .. ".bracket", { spaceId }, {
        background = {
          color = colors.transparent,
          border_color = isFocused and colors.grey or colors.bg2,
          height = 28,
          border_width = 2
        }
    })

    -- Padding space
    local space_padding = sbar.add("item", spaceId .. ".padding", {
        script = "",
        width = settings.group_paddings,
    })

    -- Store workspace info
    workspaces[spaceId] = {
        item = space,
        bracket = space_bracket,
        padding = space_padding
    }

    -- subscribe event listeners
    space:subscribe("aerospace_workspace_change", function(env)
        local isFocused = env.FOCUSED_WORKSPACE == space_name
        space:set({
            icon = { highlight = isFocused },
            label = { highlight = isFocused },
            background = { border_color = isFocused and colors.black or colors.bg2 }
        })
        space_bracket:set({
            background = { border_color = isFocused and colors.grey or colors.bg2 }
        })
    end)

    space:subscribe("mouse.clicked", function()
        aerospace:workspace(space_name)
    end)

    space:subscribe({"space_windows_change", "front_app_switched"}, function()
        updateSpaceWindows(space, space_name)
    end)

    -- initial setup
    updateSpaceWindows(space, space_name)

    -- Reorder workspaces
    reorderWorkspaces()

    return spaceId
end

local function removeWorkspace(spaceId)
    local ws = workspaces[spaceId]
    if not ws then
        return -- Workspace doesn't exist
    end

    -- Remove the items
    sbar.remove(ws.item.name)
    sbar.remove(ws.bracket.name)
    sbar.remove(ws.padding.name)

    -- Remove from tracking table
    workspaces[spaceId] = nil

    -- Reorder remaining items
    reorderWorkspaces()
end

local function updateWorkspaces()
    local current_spaces = {}

    aerospace:list_workspaces_focused(function(focusedWorkspace)
        local focusedWorkspace = focusedWorkspace:match("[^\r\n]+") or ""

        aerospace:list_workspaces_all(function(allWorkspaces)
            for _, ws_info in ipairs(allWorkspaces) do
                local space_name = ws_info.workspace
                local isFocused = (space_name == focusedWorkspace)
                local spaceId = createWorkspace(space_name, isFocused)
                current_spaces[spaceId] = true
            end
        end)
    end)

    -- Remove workspaces that no longer exist
    for spaceId, _ in pairs(workspaces) do
        if not current_spaces[spaceId] then
            removeWorkspace(spaceId)
        end
    end
end

workspace_watcher:subscribe("aerospace_workspace_change", function()
  updateWorkspaces()
end)

workspace_watcher:subscribe("space_windows_change", function()
  updateWorkspaces()
end)

-- Initial workspace setup
updateWorkspaces()
