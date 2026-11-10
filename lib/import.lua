-- lib/import.lua
-- Include this file in your resource to get OrvexORM:
--
-- fxmanifest.lua:
--   dependency 'orvexorm'
--   server_script '@orvexorm/lib/import.lua'
--
-- Then in your scripts:
--   local User = OrvexORM.model("users", { ... })
--
-- Every FiveM resource runs in its own Lua state, and exports go through
-- msgpack, which drops metatables: rows, query builders and transactions
-- would lose their methods. So this file does not use exports.orvexorm:lib().
-- It reads the library scripts from orvexorm's fxmanifest (the single list,
-- in load order) and runs them in the consumer's own Lua state, making
-- OrvexORM a native table here. Each resource gets its own ORM instance
-- (its own cache and configuration).

-- luacheck: read globals GetNumResourceMetadata IsDuplicityVersion

local ORVEX_RESOURCE = "orvexorm"
local MANIFEST_KEY = "server_script"

--- lib/* scripts (export, studio) belong to the orvexorm resource itself.
local HOST_ONLY_PREFIX = "lib/"

---@return boolean
local function isClientSide()
    return type(IsDuplicityVersion) == "function" and not IsDuplicityVersion()
end

---@param path string
---@return boolean
local function isLibraryScript(path)
    return path:sub(1, #HOST_ONLY_PREFIX) ~= HOST_ONLY_PREFIX
end

--- Library scripts listed in orvexorm's fxmanifest, in load order.
---@return string[]
local function libraryScripts()
    local count = GetNumResourceMetadata(ORVEX_RESOURCE, MANIFEST_KEY) or 0
    assert(count > 0, ("OrvexORM: resource '%s' not found, add `dependency '%s'` to your fxmanifest")
        :format(ORVEX_RESOURCE, ORVEX_RESOURCE))
    local scripts = {}
    for index = 0, count - 1 do
        local path = GetResourceMetadata(ORVEX_RESOURCE, MANIFEST_KEY, index)
        if path and isLibraryScript(path) then scripts[#scripts + 1] = path end
    end
    return scripts
end

---@param path string
local function runScript(path)
    local source = LoadResourceFile(ORVEX_RESOURCE, path)
    assert(source, ("OrvexORM: cannot read @%s/%s"):format(ORVEX_RESOURCE, path))
    local chunk = assert(load(source, ("@@%s/%s"):format(ORVEX_RESOURCE, path), "t", _ENV))
    chunk()
end

local function importOrvexORM()
    for _, path in ipairs(libraryScripts()) do runScript(path) end
end

-- Server-only library: a shared_script include is a no-op on the client.
if not OrvexORM and not isClientSide() then
    importOrvexORM()
end
