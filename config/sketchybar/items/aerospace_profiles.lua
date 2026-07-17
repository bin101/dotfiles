-- aerospace_profiles: leftmost bar item — named AeroSpace layout profiles
-- ("Work" / "Home" / ...) with a dropdown to apply / save / create /
-- rename / delete them. See helpers/layout_persist.lua for the storage and
-- restore logic; this file is only the SketchyBar UI on top of it.

local colors   = require("colors")
local settings = require("settings")
local icons    = require("icons")
local persist  = require("helpers.layout_persist")

local ROW_WIDTH = 220

local anchor = sbar.add("item", "aerospace.profiles", {
    position = "left",
    icon = {
        string = icons.yabai.stack,
        color  = colors.white,
    },
    label = { drawing = false },
    popup = { align = "left" },
})

sbar.add("bracket", "aerospace.profiles.bracket", { anchor.name }, {
    background = { color = colors.bg1 },
})

sbar.add("item", "aerospace.profiles.padding", {
    position = "left",
    width = settings.group_paddings,
})

-- ─── popup content management ───────────────────────────────────────────────

-- Names of the dynamically (re)built popup rows, so they can be removed
-- before the next rebuild (profile count changes between opens).
local popup_rows  = {}
local popup_open  = false

local function clearPopupRows()
    for _, name in ipairs(popup_rows) do
        sbar.remove(name)
    end
    popup_rows = {}
end

local function addRow(id_suffix, text, color, onClick)
    local name = anchor.name .. ".row." .. id_suffix
    local item = sbar.add("item", name, {
        position   = "popup." .. anchor.name,
        icon       = { drawing = false },
        label      = {
            string = text,
            color  = color or colors.white,
            width  = ROW_WIDTH,
            align  = "left",
        },
        background = { drawing = false },
    })
    if onClick then
        item:subscribe("mouse.clicked", onClick)
    end
    table.insert(popup_rows, name)
    return item
end

local function addSeparator(id_suffix)
    local name = anchor.name .. ".row.sep" .. id_suffix
    sbar.add("item", name, {
        position   = "popup." .. anchor.name,
        icon       = { drawing = false },
        label      = { drawing = false },
        width      = ROW_WIDTH,
        background = {
            drawing = true,
            color   = colors.bg2,
            height  = 1,
        },
    })
    table.insert(popup_rows, name)
end

local function closePopup()
    popup_open = false
    anchor:set({ popup = { drawing = false } })
end

-- Rebuild every popup row from the current profile list, then call cb().
-- Called each time the popup is opened so the list/active-marker are fresh.
local function rebuildPopup(cb)
    clearPopupRows()
    addRow("header", "Profiles", colors.grey)

    persist.list(function(profiles)
        if #profiles == 0 then
            addRow("empty", "No profiles yet", colors.grey)
        else
            for i, p in ipairs(profiles) do
                local prefix = p.active and "✓ " or "   "
                addRow("p" .. i, prefix .. p.name, p.active and colors.green or colors.white, function()
                    persist.apply(p.name, function()
                        closePopup()
                    end)
                end)
            end
        end

        addSeparator("actions")

        addRow("new", "+  New profile…", colors.white, function()
            persist.create(function()
                closePopup()
            end)
        end)

        local active = persist.get_active()
        if active then
            addRow("save", "Save current → " .. active, colors.white, function()
                persist.save(active, function()
                    closePopup()
                end)
            end)
        end

        addRow("rename", "Rename profile…", colors.white, function()
            persist.rename(function()
                closePopup()
            end)
        end)

        addRow("delete", "Delete profile…", colors.red, function()
            persist.delete(function()
                closePopup()
            end)
        end)

        if cb then cb() end
    end)
end

anchor:subscribe("mouse.clicked", function()
    if popup_open then
        closePopup()
        return
    end
    rebuildPopup(function()
        popup_open = true
        anchor:set({ popup = { drawing = true } })
    end)
end)
