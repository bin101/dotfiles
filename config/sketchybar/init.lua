local aerospace = require("aeroLua").new() -- it finds socket on its own
while not aerospace:is_initialized() do
    os.execute("sleep 0.1") -- wait for connection, not the best workaround, i am not a lua professional
end

-- Require the sketchybar module
sbar = require("sketchybar")
sbar.aerospace = aerospace

-- Bundle the entire initial configuration into a single message to sketchybar
sbar.begin_config()
require("bar")
require("default")
require("items")
sbar.add("event", "aerospace_workspace_change")
sbar.add("event", "aerospace_mode_change")
sbar.add("event", "space_windows_change")
sbar.add("event", "space_layout_change")
sbar.end_config()

-- Run the event loop of the sketchybar module (without this there will be no
-- callback functions executed in the lua module)
sbar.event_loop()
