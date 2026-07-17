local colors     = require("colors")
local settings   = require("settings")
local app_icons  = require("helpers.app_icons")
local persist    = require("helpers.layout_persist")
local aerospace  = sbar.aerospace
local workspaces = {}
local icon_cache = {}

persist.init(aerospace)

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

-- ─── event providers (self-restarting) ────────────────────────────────────────

-- Generation counter: every (re)launch bumps it; exit callbacks from older
-- generations (e.g. our own killall during a restart) are ignored.
local provider_gen = 0
local recovering   = false

-- Defined in the connection-watchdog section below; assigned before any exit
-- callback can fire (exec callbacks are only delivered once the event loop runs).
local beginRecovery

-- Launch the AeroSpace socket event provider (fires workspace/mode/window events).
-- Its exit callback is the instant "connection lost" signal: the provider
-- terminates as soon as the AeroSpace socket closes.
local function launchAerospaceEvents(gen)
    sbar.exec("killall aerospace_events >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/aerospace_events/bin/aerospace_events", function()
        if gen ~= provider_gen then return end  -- superseded by a newer launch
        if beginRecovery then beginRecovery() end
    end)
end

-- Launch the window-position watcher (polls CGWindowList, fires space_layout_change).
-- Independent of the AeroSpace socket; on unexpected exit just relaunch it
-- after a short delay (avoids a tight crash loop).
local function launchLayoutWatcher(gen)
    sbar.exec("killall layout_change_watcher >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/layout_change_watcher/bin/layout_change_watcher", function()
        if gen ~= provider_gen then return end
        sbar.exec("sleep 1", function()
            if gen ~= provider_gen then return end
            launchLayoutWatcher(gen)
        end)
    end)
end

local function startEventProviders()
    provider_gen = provider_gen + 1
    launchAerospaceEvents(provider_gen)
    launchLayoutWatcher(provider_gen)
end
startEventProviders()

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
            app_item:subscribe("mouse.clicked", function()
                if not workspaces[spaceId] then return end
                aerospace:workspace(ws.space_name)
            end)
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

-- Windows must differ by more than this many pixels on an axis to be considered
-- spatially separate (handles sub-pixel compositor rounding only).
local X_TOLERANCE = 2

-- AeroSpace's default accordion-padding, used when the config doesn't set one.
local ACCORDION_PADDING_DEFAULT = 30

-- Read accordion-padding from the loaded aerospace.toml so the cluster distance
-- tracks config changes without touching this file. `aerospace config --get`
-- only exposes mode.* keys, so the value is parsed from the config file itself.
local function readAccordionPadding()
    local ok, path = pcall(function() return aerospace:config_path() end)
    if ok and type(path) == "string" then
        path = path:match("[^\r\n]+")
        local f = path and io.open(path, "r")
        if f then
            for line in f:lines() do
                local v = line:match("^%s*accordion%-padding%s*=%s*(%d+)")
                if v then f:close(); return tonumber(v) end
            end
            f:close()
        end
    end
    return ACCORDION_PADDING_DEFAULT
end

-- Accordion peek offsets are 0/P/2P, so members of the same accordion are at
-- most 2*P apart on either axis.
local accordion_padding      = readAccordionPadding()
local ACCORDION_CLUSTER_DIST = 2 * accordion_padding + X_TOLERANCE

-- Call the window_positions helper and parse its output into a lookup table.
-- cb receives pos[window_id] = { x = N, y = N, w = N, h = N }.
-- Off-screen/parked windows (macOS sentinel at -9999, -9999) are omitted so
-- they fall into the "unknown → append at end" path instead of sorting to the left.
local function queryWindowPositions(cb)
    sbar.exec("$CONFIG_DIR/helpers/window_positions/bin/window_positions", function(output)
        local pos = {}
        if output then
            for line in output:gmatch("[^\n]+") do
                local wid_s, x_s, y_s, w_s, h_s = line:match("^(%d+)%s+(-?%d+)%s+(-?%d+)%s+(%d+)%s+(%d+)")
                if wid_s then
                    local x = tonumber(x_s)
                    local y = tonumber(y_s)
                    -- Discard off-screen park sentinel (-9999, -9999) and any other
                    -- unrealistic coordinates (< -9000). Legitimate multi-monitor
                    -- negative X values don't reach this threshold.
                    if x > -9000 and y > -9000 then
                        pos[tonumber(wid_s)] = { x = x, y = y, w = tonumber(w_s), h = tonumber(h_s) }
                    end
                end
            end
        end
        cb(pos)
    end)
end

-- Sort `windows` in-place by reading order: left→right (X), then top→bottom (Y).
-- Accordion members are clustered by proximity (ACCORDION_CLUSTER_DIST) and
-- sorted by their cluster anchor so peek-offsets don't produce wrong orderings.
-- Within a cluster the tree order is reconstructed from the frame classes of
-- the accordion layout math (offset + far edge identify first/prev/next/last);
-- residual ambiguity and non-cluster ties fall back to cached_order.
-- Windows whose id is absent from `pos` preserve their relative list order at the end.
local function sortWindowsSpatially(windows, pos, cached_order, focused_wid)
    local orig_idx = {}
    for i, w in ipairs(windows) do orig_idx[w["window-id"]] = i end

    -- Build rank lookup from cached order (nil → empty table)
    local rank = {}
    if cached_order then
        for i, wid in ipairs(cached_order) do rank[wid] = i end
    end

    -- Identify accordion windows that have a known position
    local is_accordion = {}
    for _, w in ipairs(windows) do
        local layout = w["window-parent-container-layout"]
        if (layout == "h_accordion" or layout == "v_accordion") and pos[w["window-id"]] then
            is_accordion[w["window-id"]] = true
        end
    end

    -- Greedy cluster assignment: two accordion windows in the same cluster when
    -- their positions are within ACCORDION_CLUSTER_DIST on both axes (transitively).
    local cluster_id  = {}   -- wid -> cluster index
    local cluster_members = {}
    local next_cluster = 0
    for _, w in ipairs(windows) do
        local wid = w["window-id"]
        if is_accordion[wid] and not cluster_id[wid] then
            next_cluster = next_cluster + 1
            cluster_id[wid] = next_cluster
            cluster_members[next_cluster] = { wid }
            -- Merge any other unassigned accordion windows that are close enough
            local changed = true
            while changed do
                changed = false
                for _, w2 in ipairs(windows) do
                    local wid2 = w2["window-id"]
                    if is_accordion[wid2] and not cluster_id[wid2] then
                        local p2 = pos[wid2]
                        -- Check against all current cluster members
                        for _, mwid in ipairs(cluster_members[next_cluster]) do
                            local pm = pos[mwid]
                            if math.abs(p2.x - pm.x) <= ACCORDION_CLUSTER_DIST
                               and math.abs(p2.y - pm.y) <= ACCORDION_CLUSTER_DIST then
                                cluster_id[wid2] = next_cluster
                                table.insert(cluster_members[next_cluster], wid2)
                                changed = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Compute cluster anchor: (min x, min y) across all members.
    local cluster_anchor = {}
    for cid, members in pairs(cluster_members) do
        local min_x, min_y = math.huge, math.huge
        for _, mwid in ipairs(members) do
            local pm = pos[mwid]
            if pm.x < min_x then min_x = pm.x end
            if pm.y < min_y then min_y = pm.y end
        end
        cluster_anchor[cid] = { x = min_x, y = min_y }
    end

    -- Reconstruct the tree order of each accordion cluster from the frame
    -- classes of the accordion layout math (see comment above): left edge o
    -- and right edge e = o + size relative to the cluster extent identify the
    -- first window, the direct neighbours of the focused window and the last
    -- window exactly; remaining mid-field windows are placed into the gap(s)
    -- using the cached order. Result: cluster_seq[wid] = position within the
    -- cluster. Exact for accordions of up to 4 windows in any focus position.
    local cluster_seq = {}
    for cid, members in pairs(cluster_members) do
        local anchor = cluster_anchor[cid]
        -- axis: v_accordion offsets are vertical, h_accordion horizontal
        local vertical = false
        for _, w in ipairs(windows) do
            if w["window-id"] == members[1] then
                vertical = (w["window-parent-container-layout"] == "v_accordion")
                break
            end
        end
        -- offsets and far edges along the accordion axis
        local off, edge = {}, {}
        local extent, have_size = 0, true
        for _, mwid in ipairs(members) do
            local p = pos[mwid]
            local size = vertical and p.h or p.w
            if not size then have_size = false break end
            local o = vertical and (p.y - anchor.y) or (p.x - anchor.x)
            off[mwid]  = o
            edge[mwid] = o + size
            if edge[mwid] > extent then extent = edge[mwid] end
        end

        local P = accordion_padding
        local function near(a, b) return math.abs(a - b) < P / 2 end
        local function cacheCmp(a, b)
            local ra, rb = rank[a], rank[b]
            if ra and rb then return ra < rb end
            if ra then return true end
            if rb then return false end
            return (orig_idx[a] or 0) < (orig_idx[b] or 0)
        end

        local first, prev, nxt, last, mids = nil, nil, nil, nil, {}
        local ok = have_size and #members >= 2
        if ok then
            for _, mwid in ipairs(members) do
                if mwid ~= focused_wid then
                    local o, e = off[mwid], edge[mwid]
                    if near(o, 0) and near(e, extent - P) then
                        if first then ok = false break end
                        first = mwid
                    elseif near(o, 0) and near(e, extent - 2 * P) then
                        if prev then ok = false break end
                        prev = mwid
                    elseif near(o, 2 * P) then
                        if nxt then ok = false break end
                        nxt = mwid
                    elseif near(o, P) and near(e, extent) then
                        if last then ok = false break end
                        last = mwid
                    else
                        table.insert(mids, mwid)  -- mid-field or unclassifiable
                    end
                end
            end
        end

        local ordered = {}
        local has_focused = false
        for _, mwid in ipairs(members) do
            if mwid == focused_wid then has_focused = true break end
        end
        if ok and has_focused then
            -- gap before the focused window exists only when PREV exists
            -- (otherwise idx0 is adjacent to the focused window); the gap
            -- after it only when LAST exists (otherwise focused is last).
            local before_mids, after_mids = {}, {}
            for _, mwid in ipairs(mids) do
                if prev and last then
                    -- both gaps possible: side decided by the cached order
                    local rm, rf = rank[mwid], rank[focused_wid]
                    if rm and rf and rm < rf then
                        table.insert(before_mids, mwid)
                    else
                        table.insert(after_mids, mwid)
                    end
                elseif prev then
                    table.insert(before_mids, mwid)
                else
                    table.insert(after_mids, mwid)
                end
            end
            table.sort(before_mids, cacheCmp)
            table.sort(after_mids, cacheCmp)

            if first then table.insert(ordered, first) end
            for _, m in ipairs(before_mids) do table.insert(ordered, m) end
            if prev then table.insert(ordered, prev) end
            table.insert(ordered, focused_wid)
            if nxt then table.insert(ordered, nxt) end
            for _, m in ipairs(after_mids) do table.insert(ordered, m) end
            if last then table.insert(ordered, last) end
        else
            -- Fallback (focused unknown, missing sizes or contradictory
            -- classes, e.g. cell-snapping terminals): sort by raw offset,
            -- then cached order. Exact for 2-member accordions.
            for _, mwid in ipairs(members) do table.insert(ordered, mwid) end
            table.sort(ordered, function(a, b)
                local oa, ob = off[a] or 0, off[b] or 0
                if math.abs(oa - ob) > X_TOLERANCE then return oa < ob end
                return cacheCmp(a, b)
            end)
        end
        for i, mwid in ipairs(ordered) do cluster_seq[mwid] = i end
    end

    -- Effective position: accordion windows use their cluster anchor; others use real pos.
    local function eff(wid)
        local cid = cluster_id[wid]
        if cid then return cluster_anchor[cid] end
        return pos[wid]
    end

    table.sort(windows, function(a, b)
        local wida = a["window-id"]
        local widb = b["window-id"]
        local pa = eff(wida)
        local pb = eff(widb)
        if not pa and not pb then
            return (orig_idx[wida] or 0) < (orig_idx[widb] or 0)
        end
        if not pa then return false end  -- unknown after known
        if not pb then return true  end  -- known before unknown
        local dx = pa.x - pb.x
        if math.abs(dx) > X_TOLERANCE then return dx < 0 end
        if pa.y ~= pb.y then return pa.y < pb.y end
        -- Same accordion cluster: use the reconstructed tree order.
        local ca = cluster_id[wida]
        local cb_id = cluster_id[widb]
        if ca and ca == cb_id then
            return cluster_seq[wida] < cluster_seq[widb]
        end
        -- Fall back to cached order for stability.
        local ra = rank[wida]
        local rb = rank[widb]
        if ra and rb then return ra < rb end
        if ra then return true  end  -- ranked before unranked
        if rb then return false end
        return (orig_idx[wida] or 0) < (orig_idx[widb] or 0)
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
                sortWindowsSpatially(windows, pos, window_order_by_workspace[space_name], focused_window_by_workspace[space_name])
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

-- ─── connection watchdog ──────────────────────────────────────────────────────

-- Full state resync after the AeroSpace connection was re-established.
-- Events were lost while the server was away, so focus, workspace list,
-- window lists, highlights and the mode indicator are all rebuilt.
local function fullResync()
    -- accordion-padding may have changed across an AeroSpace restart
    accordion_padding      = readAccordionPadding()
    ACCORDION_CLUSTER_DIST = 2 * accordion_padding + X_TOLERANCE
    mode_indicator:set({ drawing = false })  -- server restarts land in "main"
    aerospace:list_workspaces_focused(function(raw_ws)
        focused_workspace = (raw_ws or ""):match("[^\r\n]+") or ""
        syncWorkspaceList()
        seedFocusedWindow(function()
            for spaceId, ws in pairs(workspaces) do
                local isFocused = (ws.space_name == focused_workspace)
                ws.item:set({ icon = { highlight = isFocused } })
                space_bracket_update(spaceId, isFocused)
                recolorAppItems(spaceId)
                updateSpaceWindows(spaceId)
            end
            -- Re-apply the active layout profile after an AeroSpace restart.
            -- Settle first: on-window-detected rules re-run windows through
            -- their static workspace assignment as AeroSpace comes back up,
            -- and the profile restore must win over that, not race it.
            sbar.exec("sleep 1", function()
                persist.apply(persist.get_active())
            end)
        end)
    end)
end

-- Fast recovery loop, triggered instantly by the provider's exit callback.
-- Pings AeroSpace with exponential backoff (0.2s → 5s cap); _query's
-- self-healing re-establishes the Lua socket on the first successful ping,
-- then providers are relaunched and the full state resync runs.
beginRecovery = function()
    if recovering then return end
    recovering = true
    local function attempt(delay)
        sbar.exec("sleep " .. delay, function()
            local ok = pcall(function() return aerospace:list_workspaces_focused() end)
            if ok then
                recovering = false
                startEventProviders()
                fullResync()
            else
                attempt(math.min(delay * 2, 5))
            end
        end)
    end
    attempt(0.2)
end

-- Fallback watchdog: the provider exit callbacks above are the primary
-- "connection lost" signal; this routine only catches lost callback chains.
local watchdog = sbar.add("item", "aerospace.watchdog", {
    drawing     = false,
    updates     = true,
    update_freq = 10,
})

watchdog:subscribe("routine", function()
    if recovering then return end
    sbar.exec("pgrep -x aerospace_events >/dev/null && echo up || echo down", function(out)
        if recovering then return end
        if (out or ""):match("down") then beginRecovery() end
    end)
end)

-- ─── initial setup ────────────────────────────────────────────────────────────

-- Seed focus state before building workspaces so initial colours are correct.
-- If AeroSpace is down at startup, start the recovery loop right away.
local ok = pcall(function()
    seedFocusedWindow(function()
        initWorkspaces()

        -- Auto-apply the active profile on a genuine boot (covers a full
        -- reboot, where window ids are reassigned and the static
        -- on-window-detected rules alone can't reproduce a manual layout).
        -- Guarded by system uptime so a plain `sketchybar --reload` on an
        -- already-running session never clobbers windows the user just
        -- arranged by hand — the AeroSpace-restart path above (fullResync)
        -- covers that case unconditionally instead.
        sbar.exec("sysctl -n kern.boottime", function(out)
            local boot_epoch = tonumber((out or ""):match("sec%s*=%s*(%d+)"))
            if boot_epoch and (os.time() - boot_epoch) < 120 then
                sbar.exec("sleep 1", function()
                    persist.apply(persist.get_active())
                end)
            end
        end)
    end)
end)
if not ok then beginRecovery() end
