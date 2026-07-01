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

-- Spatial ordering state:
--   window_order_by_workspace       space_name -> ordered list of window-ids (last measured)
--   visible_by_workspace            space_name -> bool (currently shown on a monitor)
--   update_serial                   space_name -> monotonic counter; stale async chains abort on mismatch
local window_order_by_workspace = {}
local visible_by_workspace      = {}
local update_serial             = {}

-- Launch the AeroSpace socket event provider (fires workspace/mode/window events)
sbar.exec("killall aerospace_events >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/aerospace_events/bin/aerospace_events", function() end)

-- Launch the window-position watcher (polls CGWindowList, fires space_layout_change)
sbar.exec("killall layout_change_watcher >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/layout_change_watcher/bin/layout_change_watcher", function() end)

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
        return colors.white
    elseif isWsFocused then
        return colors.with_alpha(colors.grey, 0.75)
    elseif isAppFocused then
        return colors.with_alpha(colors.white, 0.55)
    else
        return colors.with_alpha(colors.grey, 0.35)
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

-- ─── spatial window ordering ──────────────────────────────────────────────────

-- Windows must differ by more than this many pixels in X to be considered
-- spatially separate (handles sub-pixel compositor rounding only).
-- Accordion peek offsets are typically 20-50px, so those members ARE sorted
-- by X, not collapsed into a column.
local X_TOLERANCE = 2

-- Call the window_positions helper and parse its output into a lookup table.
-- cb receives pos[window_id] = { x = N, y = N }.
-- Off-screen/parked windows (macOS sentinel at -9999, -9999) are omitted so
-- they fall into the "unknown → append at end" path instead of sorting to the left.
local function queryWindowPositions(cb)
    sbar.exec("$CONFIG_DIR/helpers/window_positions/bin/window_positions", function(output)
        local pos = {}
        if output then
            for line in output:gmatch("[^\n]+") do
                local wid_s, x_s, y_s = line:match("^(%d+)%s+(-?%d+)%s+(-?%d+)")
                if wid_s then
                    local x = tonumber(x_s)
                    local y = tonumber(y_s)
                    -- Discard off-screen park sentinel (-9999, -9999) and any other
                    -- unrealistic coordinates (< -9000). Legitimate multi-monitor
                    -- negative X values don't reach this threshold.
                    if x > -9000 and y > -9000 then
                        pos[tonumber(wid_s)] = { x = x, y = y }
                    end
                end
            end
        end
        cb(pos)
    end)
end

-- Sort `windows` in-place by reading order: left→right (X), then top→bottom (Y).
-- Windows whose id is absent from `pos` preserve their relative list order at the end.
local function sortWindowsSpatially(windows, pos)
    local orig_idx = {}
    for i, w in ipairs(windows) do orig_idx[w["window-id"]] = i end

    table.sort(windows, function(a, b)
        local pa = pos[a["window-id"]]
        local pb = pos[b["window-id"]]
        if not pa and not pb then
            return (orig_idx[a["window-id"]] or 0) < (orig_idx[b["window-id"]] or 0)
        end
        if not pa then return false end  -- unknown after known
        if not pb then return true  end  -- known before unknown
        local dx = pa.x - pb.x
        if math.abs(dx) > X_TOLERANCE then return dx < 0 end
        if pa.y ~= pb.y then return pa.y < pb.y end
        -- Same column and same row (e.g. accordion members): preserve AeroSpace tree order
        return (orig_idx[a["window-id"]] or 0) < (orig_idx[b["window-id"]] or 0)
    end)
end

-- Sort `windows` in-place using the last known spatial order for `space_name`.
-- Windows not yet in the cache (opened while the workspace was invisible)
-- are appended in their original list order.
local function applyCachedOrder(space_name, windows)
    local order = window_order_by_workspace[space_name]
    if not order or #order == 0 then return end

    local rank     = {}
    for i, wid in ipairs(order) do rank[wid] = i end

    local max_rank = #order + 1
    local orig_idx = {}
    for i, w in ipairs(windows) do orig_idx[w["window-id"]] = i end

    table.sort(windows, function(a, b)
        local wa = a["window-id"]
        local wb = b["window-id"]
        local ra = rank[wa] or (max_rank + (orig_idx[wa] or 0))
        local rb = rank[wb] or (max_rank + (orig_idx[wb] or 0))
        return ra < rb
    end)
end

-- Query AeroSpace for the window list of a workspace and reconcile items.
-- If the workspace is currently visible on a monitor, also query real pixel
-- positions to sort the pill in reading order (left→right, top→bottom) and
-- cache that order for later use when the workspace is hidden.
-- If the workspace is hidden, the last cached order is applied instead.
--
-- Optional `shared_pos`: pre-fetched position table (from queryWindowPositions).
-- When provided, the internal queryWindowPositions call is skipped — callers
-- that update multiple visible workspaces at once (e.g. space_layout_change)
-- should pass the same snapshot to all workspaces to avoid N redundant processes.
local function updateSpaceWindows(spaceId, shared_pos)
    local ws = workspaces[spaceId]
    if not ws then return end
    local space_name = ws.space_name

    -- Bump serial so any in-flight async chains for this workspace abort.
    update_serial[space_name] = (update_serial[space_name] or 0) + 1
    local my_serial = update_serial[space_name]

    aerospace:list_windows(space_name, function(windows)
        if not workspaces[spaceId] then return end
        if update_serial[space_name] ~= my_serial then return end  -- superseded

        if visible_by_workspace[space_name] then
            -- Inner helper: apply a position snapshot and reconcile.
            local function applyPositions(pos)
                if not workspaces[spaceId] then return end
                if update_serial[space_name] ~= my_serial then return end  -- superseded
                sortWindowsSpatially(windows, pos)
                local ordered_ids = {}
                for _, w in ipairs(windows) do
                    table.insert(ordered_ids, w["window-id"])
                end
                window_order_by_workspace[space_name] = ordered_ids
                sbar.animate("tanh", 10, function()
                    reconcileAppItems(spaceId, windows)
                end)
            end

            if shared_pos then
                -- Caller already has a snapshot — use it directly (no subprocess).
                applyPositions(shared_pos)
            else
                queryWindowPositions(applyPositions)
            end
        else
            applyCachedOrder(space_name, windows)
            sbar.animate("tanh", 10, function()
                reconcileAppItems(spaceId, windows)
            end)
        end
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
        background = { drawing = false },
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
            icon = { highlight = nowFocused },
        })
        space_bracket_update(spaceId, nowFocused)
        -- Re-colour all app items for this workspace (WS brightness changed)
        recolorAppItems(spaceId)
    end)

    space:subscribe("mouse.clicked", function()
        if not workspaces[spaceId] then return end
        aerospace:workspace(space_name)
    end)

    -- space_windows_change: only this workspace needs a reconcile.
    -- front_app_switched and aerospace_focus_change are handled globally (seed + recolor all).
    space:subscribe("space_windows_change", function()
        updateSpaceWindows(spaceId)
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
            if cb then cb(ws_name) end  -- pass live ws_name to callback
        end)
    end)
end

-- ─── bulk workspace update ────────────────────────────────────────────────────

-- Sync the workspace list against AeroSpace. focused_workspace must already be
-- up to date. Only calls reorderWorkspaces() when a workspace was added.
-- (removeWorkspace calls it internally for removals.)
local function syncWorkspaceList()
    aerospace:list_workspaces_all(function(allWorkspaces)
        local current_spaces = {}
        local added          = false
        local became_visible = {}  -- spaceIds that just transitioned hidden → visible

        for _, ws_info in ipairs(allWorkspaces) do
            local space_name = ws_info.workspace
            local spaceId    = "aerospace.space_" .. space_name
            local is_visible = (ws_info["workspace-is-visible"] == true)

            local was_visible = visible_by_workspace[space_name]
            visible_by_workspace[space_name] = is_visible

            if not workspaces[spaceId] then
                createWorkspace(space_name, (space_name == focused_workspace), true)
                added = true
            elseif is_visible and not was_visible then
                -- Workspace just appeared on a monitor → re-measure with real coords
                table.insert(became_visible, spaceId)
            end
            current_spaces[spaceId] = true
        end

        local removed = false
        for spaceId, _ in pairs(workspaces) do
            if not current_spaces[spaceId] then
                removeWorkspace(spaceId)
                removed = true
            end
        end

        if added and not removed then
            reorderWorkspaces()
        end

        for _, spaceId in ipairs(became_visible) do
            if workspaces[spaceId] then updateSpaceWindows(spaceId) end
        end
    end)
end

-- Used only at startup: seeds focused_workspace first, then syncs the list.
local function initWorkspaces()
    aerospace:list_workspaces_focused(function(raw_ws)
        focused_workspace = (raw_ws or ""):match("[^\r\n]+") or ""
        syncWorkspaceList()
    end)
end

-- ─── global event subscriptions ──────────────────────────────────────────────

-- Workspace focus changed: update global state and sync the list.
-- Visual updates (highlight, bracket, icon colours) are handled by the
-- per-item aerospace_workspace_change subscriptions — no duplicate work here.
workspace_watcher:subscribe("aerospace_workspace_change", function(env)
    focused_workspace = env.FOCUSED_WORKSPACE or ""
    syncWorkspaceList()
end)

-- Window focus changed: re-seed and re-colour.
-- space_windows_change is handled per-item (each workspace reconciles itself).
workspace_watcher:subscribe({"aerospace_focus_change", "front_app_switched"}, function()
    seedFocusedWindow(function(ws_name)
        for spaceId, _ in pairs(workspaces) do
            recolorAppItems(spaceId)
        end
        -- Use the live workspace name from seedFocusedWindow (more reliable than
        -- the globally-cached focused_workspace during rapid workspace transitions).
        local target = (ws_name ~= "" and ws_name) or focused_workspace
        local fsid   = "aerospace.space_" .. target
        if workspaces[fsid] then updateSpaceWindows(fsid) end
    end)
end)

-- Window positions changed (detected by layout_change_watcher polling CGWindowList).
-- Re-sort all visible workspaces so accordion/tile reorders are picked up immediately
-- without needing a focus change.
-- One shared window_positions snapshot is fetched and reused by all visible workspaces
-- to avoid N redundant subprocesses and ensure a consistent spatial ordering.
workspace_watcher:subscribe("space_layout_change", function()
    queryWindowPositions(function(pos)
        for spaceId, ws in pairs(workspaces) do
            if visible_by_workspace[ws.space_name] then
                updateSpaceWindows(spaceId, pos)
            end
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
    initWorkspaces()
end)
