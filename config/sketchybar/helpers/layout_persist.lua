--- layout_persist: named AeroSpace layout profiles ("Work" / "Home" / ...)
--
-- A profile is a snapshot of every window's workspace + layout mode
-- (floating / h_tiles / v_tiles / h_accordion / v_accordion). AeroSpace has
-- no CLI to serialize/restore the tiling tree itself (container hierarchy,
-- split ratios) — only workspace assignment and per-window layout mode can
-- be captured and replayed, so that is what a profile stores.
--
-- Profiles live outside the git repo (survive a reboot):
--   ~/.local/state/aerospace/profiles/<slug>.json   one file per profile
--   ~/.local/state/aerospace/active                 name of the active profile
--
-- All `aero:_query(...)` calls (list-windows / move-node-to-workspace /
-- layout) are synchronous socket round-trips (see aeroLua.lua) — no
-- callback plumbing is needed for them. Only shell subprocesses (mkdir,
-- ls, osascript) go through sbar.exec and need a callback.

local json = require("dkjson")

local M = {}

local HOME          = os.getenv("HOME") or ""
local STATE_DIR      = HOME .. "/.local/state/aerospace"
local PROFILES_DIR   = STATE_DIR .. "/profiles"
local ACTIVE_FILE    = STATE_DIR .. "/active"

local FLOATING       = "floating"

local aero = nil   -- aerospace binding, set by init()
M.active   = nil   -- name of the active profile (nil until the first save)

-- ─── small utilities ──────────────────────────────────────────────────────

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- AppleScript string literal: backslash+quote escape only.
local function asQuote(s)
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function slugify(name)
    local s = (name or ""):gsub("%s+", "_")
    s = s:gsub("[^%w_%-]", "")
    if s == "" then s = "profile" end
    return s
end

local function profilePath(name)
    return PROFILES_DIR .. "/" .. slugify(name) .. ".json"
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function writeFile(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function readActiveFile()
    local content = readFile(ACTIVE_FILE)
    return content and content:match("[^\r\n]+")
end

local function setActive(name)
    M.active = name
    writeFile(ACTIVE_FILE, name)
end

local function clearActive()
    M.active = nil
    os.remove(ACTIVE_FILE)
end

-- ─── init ──────────────────────────────────────────────────────────────────

-- `aerospace_binding` is the same `sbar.aerospace` instance used everywhere
-- else (see aeroLua.lua / items/aerospace.lua).
function M.init(aerospace_binding)
    aero = aerospace_binding
    sbar.exec("mkdir -p " .. shellQuote(PROFILES_DIR), function()
        M.active = readActiveFile()
    end)
end

function M.get_active()
    return M.active
end

-- ─── listing ───────────────────────────────────────────────────────────────

-- cb receives an array of { name = "...", file = "...", active = bool },
-- sorted alphabetically by name.
function M.list(cb)
    sbar.exec("ls -1 " .. shellQuote(PROFILES_DIR) .. " 2>/dev/null", function(out)
        local profiles = {}
        for line in (out or ""):gmatch("[^\r\n]+") do
            if line:match("%.json$") then
                local path = PROFILES_DIR .. "/" .. line
                local content = readFile(path)
                local ok, doc = pcall(json.decode, content or "")
                local name = (ok and type(doc) == "table" and doc.name) or line:gsub("%.json$", "")
                table.insert(profiles, { name = name, file = path, active = (name == M.active) })
            end
        end
        table.sort(profiles, function(a, b) return a.name < b.name end)
        cb(profiles)
    end)
end

-- ─── snapshot (save) ───────────────────────────────────────────────────────

-- Synchronous — list_windows_all is a blocking socket round-trip.
local function queryWindows()
    local ok, windows = pcall(function() return aero:list_windows_all() end)
    if not ok or type(windows) ~= "table" then return {} end
    return windows
end

function M.save(name, cb)
    local windows  = queryWindows()
    local snapshot = {}
    for _, w in ipairs(windows) do
        table.insert(snapshot, {
            id        = w["window-id"],
            app       = w["app-name"],
            title     = w["window-title"],
            workspace = w["workspace"],
            layout    = w["window-layout"],
        })
    end
    local doc = { name = name, saved_at = os.time(), windows = snapshot }
    writeFile(profilePath(name), json.encode(doc, { indent = true }))
    setActive(name)
    if cb then cb() end
end

-- ─── restore (apply) ───────────────────────────────────────────────────────

-- Match each snapshot entry to a live window: first by window-id (stable
-- across an AeroSpace restart within the same login session), then by
-- app+title (survives a reboot, where window ids are reassigned), then by
-- app alone when exactly one live candidate of that app remains unmatched.
-- Every live window is consumed at most once so identical titles can't
-- double-match the same window to two snapshot entries.
local function matchWindows(snapshot, live)
    local by_id = {}
    for _, w in ipairs(live) do by_id[w["window-id"]] = w end

    local used, matched, matches = {}, {}, {}

    for _, entry in ipairs(snapshot) do
        local w = by_id[entry.id]
        if w and not used[w["window-id"]] then
            used[w["window-id"]] = true
            matched[entry]       = true
            table.insert(matches, { entry = entry, current = w })
        end
    end

    for _, entry in ipairs(snapshot) do
        if not matched[entry] then
            for _, w in ipairs(live) do
                if not used[w["window-id"]]
                   and w["app-name"] == entry.app
                   and w["window-title"] == entry.title then
                    used[w["window-id"]] = true
                    matched[entry]       = true
                    table.insert(matches, { entry = entry, current = w })
                    break
                end
            end
        end
    end

    for _, entry in ipairs(snapshot) do
        if not matched[entry] then
            local candidate, count = nil, 0
            for _, w in ipairs(live) do
                if not used[w["window-id"]] and w["app-name"] == entry.app then
                    candidate = w
                    count     = count + 1
                end
            end
            if count == 1 then
                used[candidate["window-id"]] = true
                matched[entry]                = true
                table.insert(matches, { entry = entry, current = candidate })
            end
        end
    end

    return matches
end

-- Move + relayout one window to match its snapshot entry. Idempotent: only
-- issues a command when the live state actually differs.
--
-- A floating window can't be switched directly to an exact tiling variant
-- (AeroSpace rejects it with "The window is non-tiling"); it must first be
-- un-floated via the generic "tiling" target, which lands on whatever
-- layout the destination container currently has — the exact saved variant
-- (e.g. h_accordion vs h_tiles) is then re-applied explicitly. Verified by
-- hand against a running AeroSpace 0.21.2 instance.
local function applyWindow(entry, current)
    local wid = current["window-id"]

    if entry.workspace and entry.workspace ~= current["workspace"] then
        pcall(function()
            aero:_query({ "move-node-to-workspace", "--window-id", tostring(wid), entry.workspace })
        end)
    end

    local target = entry.layout
    local live_layout = current["window-layout"]
    if target and target ~= "" and target ~= live_layout then
        if live_layout == FLOATING and target ~= FLOATING then
            pcall(function() aero:_query({ "layout", "--window-id", tostring(wid), "tiling" }) end)
        end
        pcall(function() aero:_query({ "layout", "--window-id", tostring(wid), target }) end)
    end
end

-- Apply profile `name`: move/relayout every matched window, then mark it
-- active. No-op if the profile doesn't exist. `cb()` always fires.
function M.apply(name, cb)
    if not name then if cb then cb() end return end

    local content = readFile(profilePath(name))
    if not content then if cb then cb() end return end

    local ok, doc = pcall(json.decode, content)
    if not ok or type(doc) ~= "table" or type(doc.windows) ~= "table" then
        if cb then cb() end
        return
    end

    local live    = queryWindows()
    local matches = matchWindows(doc.windows, live)
    for _, m in ipairs(matches) do
        applyWindow(m.entry, m.current)
    end

    setActive(name)
    if cb then cb() end
end

-- ─── profile management (osascript dialogs) ────────────────────────────────

-- Prompt for a name, then save the current layout under it. Cancel → no-op.
function M.create(cb)
    local script = "display dialog " .. asQuote("New profile name:") ..
        ' default answer "" with title ' .. asQuote("AeroSpace Profiles") ..
        ' buttons {"Cancel","Create"} default button "Create"'
    sbar.exec("osascript -e " .. shellQuote(script) .. " 2>/dev/null", function(out)
        local name = out and out:match("text returned:(.*)$")
        if name then name = name:gsub("[\r\n]+$", "") end
        if not name or name:match("^%s*$") then
            if cb then cb() end
            return
        end
        M.save(name, cb)
    end)
end

-- Show a "choose from list" picker built from the current profiles.
-- calls `handler(chosen_name)` with nil if the user cancelled or there is
-- nothing to choose from.
local function pickProfile(prompt, handler)
    M.list(function(profiles)
        if #profiles == 0 then handler(nil) return end
        local items = {}
        for _, p in ipairs(profiles) do table.insert(items, asQuote(p.name)) end
        local script = "set chosen to (choose from list {" .. table.concat(items, ",") ..
            "} with prompt " .. asQuote(prompt) .. ")\n" ..
            'if chosen is false then return "CANCELLED"\n' ..
            "return item 1 of chosen"
        sbar.exec("osascript -e " .. shellQuote(script) .. " 2>/dev/null", function(out)
            local sel = out and out:gsub("[\r\n]+$", "")
            if not sel or sel == "" or sel == "CANCELLED" then
                handler(nil)
            else
                handler(sel)
            end
        end)
    end)
end

-- Pick a profile, confirm, then delete it. Clears the active marker if the
-- deleted profile was active.
function M.delete(cb)
    pickProfile("Delete which profile?", function(name)
        if not name then if cb then cb() end return end
        local script = "display alert " .. asQuote('Delete profile "' .. name .. '"?') ..
            ' buttons {"Cancel","Delete"} default button "Cancel" cancel button "Cancel"'
        sbar.exec("osascript -e " .. shellQuote(script) .. " 2>/dev/null", function(out)
            if not (out and out:match("Delete")) then
                if cb then cb() end
                return
            end
            os.remove(profilePath(name))
            if M.active == name then clearActive() end
            if cb then cb() end
        end)
    end)
end

-- Pick a profile, prompt for a new name, rewrite its file under the new slug
-- (removing the old one) and update the `name` field / active marker.
function M.rename(cb)
    pickProfile("Rename which profile?", function(name)
        if not name then if cb then cb() end return end
        local script = "display dialog " .. asQuote("New name for \"" .. name .. "\":") ..
            " default answer " .. asQuote(name) ..
            ' with title ' .. asQuote("AeroSpace Profiles") ..
            ' buttons {"Cancel","Rename"} default button "Rename"'
        sbar.exec("osascript -e " .. shellQuote(script) .. " 2>/dev/null", function(out)
            local new_name = out and out:match("text returned:(.*)$")
            if new_name then new_name = new_name:gsub("[\r\n]+$", "") end
            if not new_name or new_name:match("^%s*$") or new_name == name then
                if cb then cb() end
                return
            end

            local content = readFile(profilePath(name))
            if content then
                local ok, doc = pcall(json.decode, content)
                if ok and type(doc) == "table" then
                    doc.name = new_name
                    writeFile(profilePath(new_name), json.encode(doc, { indent = true }))
                    os.remove(profilePath(name))
                end
            end
            if M.active == name then setActive(new_name) end
            if cb then cb() end
        end)
    end)
end

return M
