-- One-off converter (kept for provenance): turns the Hammerspoon version's
-- built-in shortcut list (window-mover/hammerspoon/known-shortcuts.lua) into
-- Sources/WindowShepherdCore/Resources/known-shortcuts.json.
--   lua scripts/port-known-shortcuts.lua [path/to/known-shortcuts.lua] > …json
local path = arg[1] or (os.getenv("HOME") .. "/CLAUDE/window-mover/hammerspoon/known-shortcuts.lua")
local K = dofile(path)

local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ({ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" })[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local out = {}
for _, e in ipairs(K.apps) do
  table.insert(out, string.format('    {"app": %s, "what": %s, "keys": %s}', str(e.app), str(e.what), str(e.keys)))
end
local ids = {}
for id in pairs(K.system) do table.insert(ids, id) end
table.sort(ids)
local sys = {}
for _, id in ipairs(ids) do table.insert(sys, string.format('    "%d": %s', id, str(K.system[id]))) end
print('{\n  "apps": [\n' .. table.concat(out, ",\n") .. '\n  ],\n  "system": {\n' .. table.concat(sys, ",\n") .. '\n  }\n}')
