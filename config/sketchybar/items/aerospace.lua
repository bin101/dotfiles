local colors     = require("colors")
local settings   = require("settings")
local app_icons  = require("helpers.app_icons")
local aerospace  = sbar.aerospace
local workspaces = {}
local icon_cache = {}

-- Global focus state:
--   focused_workspace               current focused workspace name
--   focused_window_by_workspace     space_name -> window-id of last known focused window
local focused_workspace           = ""
local focused_window_by_workspace = {}

-- Launch the AeroSpace socket event provider (fires workspace/mode/window events)
sbar.exec("killall aerospace_events >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/aerospace_events/bin/aerospace_events", function() end)

-- Initial padding item
sbar.add("item", "aerospace.padding", { position = "left", width = settings.group_paddings })

-- Create a hidden item to subscribe to workspace change events
local workspace_watcher = sbar.add("item", "aerospace.eventlistener", {
  drawing = false,
  updates = true,
})

-- ─── helpers ─────────────────────────────────────────────────────────────────

local function getAppIcon(appName)
    if icon_cache[appName] then
        return icon_cache[appName]
    end
    local icon = app_icons[appName] or app_icons["default"] or "?"
    icon_cache[appName] = icon
    return icon
end

-- Returns the correct glyph color for an app icon given the four-state matrix.
local function iconColor(isWsFocused, isAppFocused)
    if isWsFocused and isAppFocused then
        return colors.red
    elseif isWsFocused then
        return colors.white
    elseif isAppFocused then
        return colors.with_alpha(colors.red, 0.6)
    else
        return colors.with_alpha(colors.grey, 0.55)
    end
end

-- ─── per-workspace item management ───────────────────────────────────────────

-- Rebuild the bracket to include the workspace number item + all current app items.
local function rebuildBracket(spaceId)
    local ws = workspaces[spaceId]
    if not ws then return end

    local members = { spaceId }
    for _, ai in ipairs(ws.app_items) do
        table.insert(members, ai.name)
    end

    local isFocused = (ws.space_name == focused_workspace)
    if ws.bracket then
        -- remove old bracket first
        sbar.remove(ws.bracket.name)
    end

    ws.bracket = sbar.add("bracket", spaceId .. ".bracket", members, {
        background = {
            color        = colors.transparent,
            border_color = isFocused and colors.grey or colors.bg2,
            height       = 28,
            border_width = 2,
        }
    })
end

-- Re-colour all existing app items for a workspace without rebuilding anything.
local function recolorAppItems(spaceId)
    local ws = workspaces[spaceId]
    if not ws then return end

    local isWsFocused  = (ws.space_name == focused_workspace)
    local focusedWinId = focused_window_by_workspace[ws.space_name]

    for _, ai in ipairs(ws.app_items) do
        local isAppFocused = (ai.window_id == focusedWinId)
        ai.item:set({
            icon = { color = iconColor(isWsFocused, isAppFocused) }
        })
    end
end

-- Full reconcile of per-app items for one workspace.
-- Called when the window list changes (windows opened/closed/moved).
local function reconcileAppItems(spaceId, windows)
    local ws = workspaces[spaceId]
    if not ws then return end

    local isWsFocused  = (ws.space_name == focused_workspace)
    local focusedWinId = focused_window_by_workspace[ws.space_name]
    local newCount     = windows and #windows or 0
    local oldCount     = #ws.app_items

    -- 1. Update or create items
    for i = 1, newCount do
        local win       = windows[i]
        local app_name  = win["app-name"] or ""
        local window_id = win["window-id"]
        local glyph     = getAppIcon(app_name)
        local isApp     = (window_id == focusedWinId)
        local itemName  = spaceId .. ".app_" .. i
        -- Give the first icon extra left padding (gap after workspace number),
        -- and the last icon extra right padding (tail before bracket edge).
        local pl = (i == 1)        and 5 or 3
        local pr = (i == newCount) and 9 or 3

        if ws.app_items[i] then
            -- Reuse existing item; always update padding in case it became first/last
            ws.app_items[i].window_id = window_id
            ws.app_items[i].item:set({
                icon = {
                    string        = glyph,
                    color         = iconColor(isWsFocused, isApp),
                    padding_left  = pl,
                    padding_right = pr,
                }
            })
        else
            -- Create new item
            local app_item = sbar.add("item", itemName, {
                icon = {
                    font          = "sketchybar-app-font:Regular:16.0",
                    string        = glyph,
                    color         = iconColor(isWsFocused, isApp),
                    padding_left  = pl,
                    padding_right = pr,
                    y_offset      = -1,
                },
                label      = { drawing = false },
                background = { drawing = false },
                padding_left  = 0,
                padding_right = 0,
            })
            ws.app_items[i] = { item = app_item, name = itemName, window_id = window_id }
        end
    end

    -- 2. Remove surplus items
    for i = newCount + 1, oldCount do
        sbar.remove(ws.app_items[i].name)
        ws.app_items[i] = nil
    end
    -- Trim table length
    for i = #ws.app_items, newCount + 1, -1 do
        table.remove(ws.app_items, i)
    end

    -- 3. Show an em-dash when the workspace is empty (on the number-item label)
    if newCount == 0 then
        ws.item:set({ label = { string = "—", drawing = true, padding_right = 9 } })
    else
        ws.item:set({ label = { drawing = false } })
    end

    -- 4. Rebuild bracket only if item count changed
    if newCount ~= oldCount then
        rebuildBracket(spaceId)
        reorderWorkspaces()
    end
end

-- Query AeroSpace for the window list of a workspace and reconcile items.
local function updateSpaceWindows(spaceId)
    local ws = workspaces[spaceId]
    if not ws then return end
    aerospace:list_windows(ws.space_name, function(windows)
        if not workspaces[spaceId] then return end
        sbar.animate("tanh", 10, function()
            reconcileAppItems(spaceId, windows)
        end)
    end)
end

function reorderWorkspaces()
    local item_order = ""

    local workspace_names = {}
    for name, _ in pairs(workspaces) do
        table.insert(workspace_names, name)
    end
    table.sort(workspace_names)

    for _, name in ipairs(workspace_names) do
        local ws = workspaces[name]
        item_order = item_order .. " " .. ws.item.name
        for _, ai in ipairs(ws.app_items) do
            item_order = item_order .. " " .. ai.name
        end
        item_order = item_order .. " " .. ws.bracket.name .. " " .. ws.padding.name
    end

    if item_order ~= "" then
        sbar.exec("sketchybar --reorder aerospace.padding aerospace.eventlistener " .. item_order .. " front_app", function() end)
    end
end

-- ─── workspace lifecycle ──────────────────────────────────────────────────────

local function createWorkspace(space_name, isFocused, skip_reorder)
    local spaceId = "aerospace.space_" .. space_name

    if workspaces[spaceId] then
        return spaceId
    end

    local space = sbar.add("item", spaceId, {
        icon = {
            font          = { family = settings.font.numbers },
            string        = space_name,
            padding_left  = 7,
            padding_right = 3,
            color         = colors.white,
            highlight     = isFocused,
            highlight_color = colors.red,
        },
        label = {
            drawing       = false,   -- hidden by default; shown only when 0 windows
            padding_right = 0,
            color         = colors.grey,
            font          = "sketchybar-app-font:Regular:16.0",
            y_offset      = -1,
        },
        background = {
            color        = colors.bg1,
            border_width = 1,
            height       = 26,
            border_color = isFocused and colors.black or colors.bg2,
        },
        padding_right = 1,
        padding_left  = 1,
    })

    -- Padding space
    local space_padding = sbar.add("item", spaceId .. ".padding", {
        script = "",
        width  = settings.group_paddings,
    })

    -- Store workspace info (bracket built once app items are known)
    workspaces[spaceId] = {
        item       = space,
        bracket    = nil,      -- set by rebuildBracket
        padding    = space_padding,
        space_name = space_name,
        app_items  = {},       -- list of { item, name, window_id }
    }

    -- Build initial (empty) bracket so the structure exists immediately
    rebuildBracket(spaceId)

    -- ── event subscriptions ──

    space:subscribe("aerospace_workspace_change", function(env)
        if not workspaces[spaceId] then return end
        local nowFocused = env.FOCUSED_WORKSPACE == space_name
        space:set({
            icon       = { highlight = nowFocused },
            background = { border_color = nowFocused and colors.black or colors.bg2 }
        })
        space_bracket_update(spaceId, nowFocused)
        -- Re-colour all app items for this workspace (WS brightness changed)
        recolorAppItems(spaceId)
    end)

    space:subscribe("mouse.clicked", function()
        if not workspaces[spaceId] then return end
        aerospace:workspace(space_name)
    end)

    space:subscribe({"space_windows_change", "front_app_switched"}, function()
        updateSpaceWindows(spaceId)
    end)

    space:subscribe("aerospace_focus_change", function()
        -- Refresh focused window state, then re-colour
        seedFocusedWindow(function()
            recolorAppItems(spaceId)
        end)
    end)

    -- initial window load
    updateSpaceWindows(spaceId)

    if not skip_reorder then
        reorderWorkspaces()
    end

    return spaceId
end

-- Helper: update bracket border when WS focus changes
function space_bracket_update(spaceId, isFocused)
    local ws = workspaces[spaceId]
    if not ws or not ws.bracket then return end
    ws.bracket:set({
        background = { border_color = isFocused and colors.grey or colors.bg2 }
    })
end

local function removeWorkspace(spaceId)
    local ws = workspaces[spaceId]
    if not ws then return end

    for _, ai in ipairs(ws.app_items) do
        sbar.remove(ai.name)
    end
    sbar.remove(ws.item.name)
    if ws.bracket then sbar.remove(ws.bracket.name) end
    sbar.remove(ws.padding.name)

    workspaces[spaceId] = nil
    reorderWorkspaces()
end

-- ─── focus seeding ────────────────────────────────────────────────────────────

-- Ask AeroSpace for the globally focused window; update our tracking table.
-- Calls cb() when done (may be nil).
function seedFocusedWindow(cb)
    aerospace:list_workspaces_focused(function(raw_ws)
        local ws_name = (raw_ws or ""):match("[^\r\n]+") or ""
        aerospace:list_window_focused(function(windows)
            if windows and #windows > 0 then
                local win = windows[1]
                local wid = win["window-id"]
                if ws_name ~= "" then
                    focused_window_by_workspace[ws_name] = wid
                end
            end
            if cb then cb() end
        end)
    end)
end

-- ─── bulk workspace update ────────────────────────────────────────────────────

local function updateWorkspaces()
    aerospace:list_workspaces_focused(function(raw_ws)
        focused_workspace = (raw_ws or ""):match("[^\r\n]+") or ""

        aerospace:list_workspaces_all(function(allWorkspaces)
            local current_spaces = {}

            for _, ws_info in ipairs(allWorkspaces) do
                local space_name = ws_info.workspace
                local isFocused  = (space_name == focused_workspace)
                local spaceId    = createWorkspace(space_name, isFocused, true)
                current_spaces[spaceId] = true
            end

            for spaceId, _ in pairs(workspaces) do
                if not current_spaces[spaceId] then
                    removeWorkspace(spaceId)
                end
            end

            reorderWorkspaces()
        end)
    end)
end

-- ─── global event subscriptions ──────────────────────────────────────────────

workspace_watcher:subscribe("aerospace_workspace_change", function(env)
    local prev_ws     = focused_workspace
    focused_workspace = env.FOCUSED_WORKSPACE or ""
    updateWorkspaces()
    -- Re-colour old and new focused workspace so brightness flips immediately
    local prevId = "aerospace.space_" .. prev_ws
    local newId  = "aerospace.space_" .. focused_workspace
    if workspaces[prevId] then recolorAppItems(prevId) end
    if workspaces[newId]  then recolorAppItems(newId) end
end)

workspace_watcher:subscribe("space_windows_change", function()
    for spaceId, _ in pairs(workspaces) do
        updateSpaceWindows(spaceId)
    end
end)

workspace_watcher:subscribe("aerospace_focus_change", function()
    seedFocusedWindow(function()
        -- Re-colour every workspace (focused window may have been in any of them)
        for spaceId, _ in pairs(workspaces) do
            recolorAppItems(spaceId)
        end
    end)
end)

workspace_watcher:subscribe("front_app_switched", function()
    -- front_app_switched fires for same-workspace app changes; re-seed and re-colour
    seedFocusedWindow(function()
        for spaceId, _ in pairs(workspaces) do
            recolorAppItems(spaceId)
        end
    end)
end)

-- ─── mode indicator ───────────────────────────────────────────────────────────

local mode_indicator = sbar.add("item", "aerospace.mode", {
    position = "left",
    drawing  = false,
    icon     = { drawing = false },
    label    = {
        string       = "MODE",
        color        = colors.red,
        font         = {
            family = settings.font.text,
            style  = settings.font.style_map["Bold"],
            size   = 11.0,
        },
        padding_left  = 8,
        padding_right = 8,
    },
    background = {
        color        = colors.bg1,
        border_width = 1,
        border_color = colors.red,
        height       = 26,
    },
    padding_left  = 1,
    padding_right = settings.group_paddings,
})

mode_indicator:subscribe("aerospace_mode_change", function(env)
    local mode    = env.AEROSPACE_MODE or ""
    local is_main = (mode == "main" or mode == "")
    mode_indicator:set({
        drawing = not is_main,
        label   = { string = mode:upper() },
    })
end)

-- ─── initial setup ────────────────────────────────────────────────────────────

-- Seed focus state before building workspaces so initial colours are correct
seedFocusedWindow(function()
    updateWorkspaces()
end)
