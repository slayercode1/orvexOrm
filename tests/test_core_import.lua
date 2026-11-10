-- tests/test_core_import.lua
-- Cross-resource loading: a consumer resource includes '@orvexorm/lib/import.lua'.
-- In FiveM every resource runs in its own Lua state, so the consumer is
-- simulated by a fresh environment that only sees the standard library and
-- the natives a consumer has (LoadResourceFile, resource metadata, oxmysql).
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_core_import.lua

local passed, failed = 0, 0

local function assert_eq(got, expected, msg)
    if got == expected then
        passed = passed + 1
        print(("  ✓ %s"):format(msg))
    else
        failed = failed + 1
        print(("  ✗ %s — expected: %s, got: %s"):format(msg, tostring(expected), tostring(got)))
    end
end

local function assert_true(value, msg) assert_eq(value and true or false, true, msg) end

-- ─── Disk-backed FiveM natives ─────────────────────────────────────

local ORVEX = "orvexorm"

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("a")
    f:close()
    return content
end

--- Runs fxmanifest.lua like FiveM does: every directive is a function call,
--- and a plural directive (`server_scripts`) is stored under its singular key.
local function readManifestMetadata()
    local metadata = {}
    local function singular(directive)
        if directive:sub(-3) == "ies" then return directive:sub(1, -4) .. "y" end
        if #directive > 1 and directive:sub(-1) == "s" then return directive:sub(1, -2) end
        return directive
    end
    local env = setmetatable({}, {
        __index = function(_, directive)
            return function(value)
                local key = type(value) == "table" and singular(directive) or directive
                metadata[key] = metadata[key] or {}
                for _, entry in ipairs(type(value) == "table" and value or { value }) do
                    table.insert(metadata[key], entry)
                end
            end
        end,
    })
    assert(load(assert(readFile("fxmanifest.lua")), "@fxmanifest.lua", "t", env))()
    return metadata
end

local MANIFEST = readManifestMetadata()

--- Every chunk the consumer loads, in order.
local loadedFiles = {}

local function newNatives(currentResource)
    return {
        GetCurrentResourceName = function() return currentResource end,
        IsDuplicityVersion = function() return true end,
        GetNumResourceMetadata = function(resource, key)
            if resource ~= ORVEX then return 0 end
            return #(MANIFEST[key] or {})
        end,
        GetResourceMetadata = function(resource, key, index)
            if resource ~= ORVEX then return nil end
            return (MANIFEST[key] or {})[index + 1]
        end,
        LoadResourceFile = function(resource, path)
            if resource ~= ORVEX then return nil end
            loadedFiles[#loadedFiles + 1] = path
            return readFile(path)
        end,
    }
end

-- ─── oxmysql mock (the consumer talks to oxmysql directly) ─────────

local dbLog, txLog = {}, {}
local nextSelect = {}

local function mockQuery(query, params, cb)
    dbLog[#dbLog + 1] = { sql = query, params = params }
    if query:match("^SELECT") then cb(table.remove(nextSelect, 1) or {})
    elseif query:match("^INSERT") then cb(1)
    else cb({ affectedRows = 1 }) end
end

local function newOxmysql()
    return {
        prepare = mockQuery, query = mockQuery, insert = mockQuery, update = mockQuery,
        transaction = function(queries, cb) txLog[#txLog + 1] = queries; cb(true) end,
    }
end

local function newPromiseLib()
    return {
        new = function()
            local p = {}
            function p:resolve(v) self._value = v end
            return p
        end,
    }
end

--- `exports` of the consumer: the import must never go through exports.orvexorm.
local exportCalls = 0
local function newExports()
    return setmetatable({}, {
        __index = function(_, resource)
            if resource == ORVEX then exportCalls = exportCalls + 1 end
            return setmetatable({}, { __index = function() return function() return nil end end })
        end,
    })
end

-- ─── Consumer runtime ──────────────────────────────────────────────

local STD = {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget",
    "rawlen", "rawset", "select", "setmetatable", "getmetatable", "tonumber", "tostring",
    "type", "xpcall", "load", "string", "table", "math", "os", "coroutine", "utf8", "debug",
}

--- A fresh global environment standing in for the consumer's own Lua state.
local function newConsumerRuntime(resourceName)
    local env = {}
    for _, name in ipairs(STD) do env[name] = _G[name] end
    for name, fn in pairs(newNatives(resourceName)) do env[name] = fn end
    env._G = env
    env.MySQL = newOxmysql()
    env.Citizen = { Await = function(p) return p._value end }
    env.promise = newPromiseLib()
    env.json = { encode = function() return "{}" end, decode = function() return {} end }
    env.exports = newExports()
    env.require = function(name)
        error(("require('%s') called inside a consumer: FiveM has no require"):format(name), 2)
    end
    return env
end

local function runImport(env)
    local chunk = assert(load(assert(readFile("lib/import.lua")), "@@orvexorm/lib/import.lua", "t", env))
    return pcall(chunk)
end

-- ─── Test: import loads the ORM natively in the consumer ───────────

print("\n== import.lua loads OrvexORM into the consumer runtime ==")

local consumer = newConsumerRuntime("my_consumer")
local ok, err = runImport(consumer)
assert_eq(ok, true, "import.lua runs in a consumer: " .. tostring(err))
assert_eq(exportCalls, 0, "import.lua never calls exports.orvexorm")
assert_eq(rawget(_G, "OrvexORM"), nil, "nothing leaks into the test's own globals")

local ORM = consumer.OrvexORM
assert_eq(type(ORM), "table", "OrvexORM is a global of the consumer")
assert_eq(type(ORM and ORM.model), "function", "OrvexORM.model is a native function")

local expectedFiles = {}
for _, path in ipairs(MANIFEST.server_script) do
    if path:sub(1, 4) ~= "lib/" then expectedFiles[#expectedFiles + 1] = path end
end
assert_eq(table.concat(loadedFiles, ","), table.concat(expectedFiles, ","),
    "loads every library server_script in fxmanifest order, without lib/*")

local manifestVersion = MANIFEST.version[1]
assert_eq(ORM and ORM.version, manifestVersion, "ORM.version is orvexorm's version, not the consumer's")

-- ─── Test: instances, builders and transactions keep their methods ─

print("\n== Methods survive in the consumer ==")

if ORM then
    local User = ORM.model("users", { id = "number", name = "string", money = "number" })
    nextSelect[#nextSelect + 1] = { { id = 1, name = "John", money = 10 } }
    local user = User.find({ id = 1 })
    assert_true(getmetatable(user) ~= nil, "a found row keeps its instance metatable")
    assert_eq(type(user and user.update), "function", "instance:update is callable")
    local updated = pcall(function() user:update({ money = 20 }) end)
    assert_eq(updated, true, "instance:update() runs")
    assert_true(dbLog[#dbLog].sql:match("^UPDATE"), "instance:update() issues an UPDATE")

    local builder = User.query()
    assert_eq(type(builder.where), "function", "User.query():where is callable")
    nextSelect[#nextSelect + 1] = { { id = 1, name = "John", money = 20 } }
    local rows = builder:where("money", ">", 5):get()
    assert_eq(#rows, 1, "builder chain returns rows")

    local txOk = pcall(function()
        ORM.transaction(function(tx)
            tx:insert("users", { name = "Jane" })
            tx:update("users", { money = 1 }, { id = 1 })
        end)
    end)
    assert_eq(txOk, true, "ORM.transaction(fn) gives a tx with methods")
    assert_eq(#txLog[#txLog], 2, "tx queries are committed together")

    local okMisuse, misuse = pcall(function() User.update({ money = 1 }, {}) end)
    assert_eq(okMisuse, false, "update() without where raises in the consumer")
    assert_true(tostring(misuse):find("test_core_import.lua:", 1, true),
        "a misuse error points at the consumer's line, not into the imported library")
end

-- ─── Test: importing twice is a no-op ──────────────────────────────

print("\n== Idempotent import ==")

local loadedBefore = #loadedFiles
local firstORM = consumer.OrvexORM
local again = runImport(consumer)
assert_eq(again, true, "a second import runs")
assert_eq(#loadedFiles, loadedBefore, "a second import loads no file")
assert_eq(consumer.OrvexORM, firstORM, "a second import keeps the same OrvexORM")

-- ─── Test: separate consumers get separate ORMs ────────────────────

print("\n== Separate consumers ==")

local other = newConsumerRuntime("other_consumer")
assert_eq(runImport(other), true, "a second resource imports too")
assert_true(other.OrvexORM ~= consumer.OrvexORM, "each resource owns its own OrvexORM")

-- ─── Test: clear failure when orvexorm is missing ──────────────────

print("\n== Missing orvexorm ==")

local orphan = newConsumerRuntime("orphan")
orphan.GetNumResourceMetadata = function() return 0 end
local okMissing, missingErr = runImport(orphan)
assert_eq(okMissing, false, "import fails when orvexorm has no server scripts")
assert_true(tostring(missingErr):find("orvexorm", 1, true), "the error names the orvexorm resource")

-- ─── Test: client side of a shared_script include ──────────────────

print("\n== shared_script on the client ==")

local client = newConsumerRuntime("client_side")
client.IsDuplicityVersion = function() return false end
local filesBeforeClient = #loadedFiles
assert_eq(runImport(client), true, "import is harmless on the client")
assert_eq(client.OrvexORM, nil, "the server-only ORM is not loaded on the client")
assert_eq(#loadedFiles, filesBeforeClient, "no file is read on the client")

-- ─── Test: why the export path is limited ──────────────────────────

print("\n== Legacy exports.orvexorm:lib() (msgpack round trip) ==")

--- FiveM marshals export values through msgpack: tables are copied without
--- their metatable and functions become callable references whose results
--- are marshalled the same way.
local marshal
local function marshalFunction(fn)
    return function(...)
        local results = table.pack(fn(...))
        for i = 1, results.n do results[i] = marshal(results[i]) end
        return table.unpack(results, 1, results.n)
    end
end
marshal = function(value, seen)
    if type(value) == "function" then return marshalFunction(value) end
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[k] = marshal(v, seen) end
    return copy
end

if ORM then
    local exported = marshal(ORM)
    local LegacyUser = exported.model("users", { id = "number", name = "string", money = "number" })
    nextSelect[#nextSelect + 1] = { { id = 1, name = "John", money = 10 } }
    local row = LegacyUser.find({ id = 1 })
    assert_eq(getmetatable(row), nil, "a row returned through the export lost its metatable")
    assert_eq(row.update, nil, "so row:update does not exist on the export path")
    local okBuilder = pcall(function() return LegacyUser.query():where("id", 1) end)
    assert_eq(okBuilder, false, "and User.query():where fails on the export path")
end

-- ─── Test: the legacy export warns once ────────────────────────────

print("\n== Legacy export warning ==")

local host = newConsumerRuntime(ORVEX)
assert_eq(runImport(host), true, "host runtime loads the library")
local exportedFns = {}
host.exports = setmetatable({}, { __call = function(_, name, fn) exportedFns[name] = fn end })
host.print = function() end
local warnings = {}
host.OrvexLogger.setSink(function(_, event)
    if event.level == "warn" then warnings[#warnings + 1] = event.message end
end)
assert(load(assert(readFile("lib/export.lua")), "@@orvexorm/lib/export.lua", "t", host))()
assert_eq(exportedFns.lib(), host.OrvexORM, "exports.orvexorm:lib() still returns OrvexORM")
exportedFns.lib()
assert_eq(#warnings, 1, "the export warns once about its limits")
assert_true(warnings[1] and warnings[1]:find("lib/import.lua", 1, true), "the warning points at lib/import.lua")
host.OrvexLogger.setSink(nil)

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
