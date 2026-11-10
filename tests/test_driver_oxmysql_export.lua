-- tests/test_driver_oxmysql_export.lua
-- Driver mode "oxmysql_export": no MySQL global (the default orvexorm fxmanifest),
-- oxmysql reached through its sync exports.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_driver_oxmysql_export.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Test helpers ──────────────────────────────────────────────────

local passed, failed = 0, 0

local function check(cond, msg, detail)
    if cond then
        passed = passed + 1
        print(("  ✓ %s"):format(msg))
    else
        failed = failed + 1
        print(("  ✗ %s%s"):format(msg, detail and (" — " .. detail) or ""))
    end
end

local function assert_eq(got, expected, msg)
    check(got == expected, msg, ("expected: %s, got: %s"):format(tostring(expected), tostring(got)))
end

local function assert_error(fn, pattern, msg)
    local ok, err = pcall(fn)
    check(not ok and tostring(err):find(pattern, 1, true) ~= nil, msg, "error: " .. tostring(err))
end

-- ─── FiveM mocks ───────────────────────────────────────────────────

promise = {
    new = function()
        local p = { _done = false }
        function p:resolve(v) self._value = v; self._done = true end
        return p
    end,
}
Citizen = {
    Await = function(p)
        while not p._done do coroutine.yield() end
        return p._value
    end,
}

local resourceStates = {}
function GetResourceState(name)
    return resourceStates[name] or "missing"
end

-- Like FiveM, exports[resource] always returns a proxy, even for a resource that is not running.
local registered = {}
exports = setmetatable({}, {
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, method)
                local impl = registered[resource] and registered[resource][method]
                if impl then return impl end
                return function() error(("No such export %s in resource %s"):format(method, resource)) end
            end,
        })
    end,
})

local calls = {}
local results = {}

local function reset()
    calls = {}
    results = {}
end

local function syncExport(name)
    return function(_, query, params)
        calls[#calls + 1] = { fn = name, sql = query, params = params }
        local r = results[name]
        if type(r) == "table" and r.error then error(r.error) end
        return r
    end
end

registered.oxmysql = {
    executeSync = syncExport("executeSync"),
    insertSync = syncExport("insertSync"),
    updateSync = syncExport("updateSync"),
    transactionSync = syncExport("transactionSync"),
}

local Driver = require("database.mysql")

local function newDriver()
    Driver._mode = nil
    return Driver.new()
end

-- ─── Detection ─────────────────────────────────────────────────────

print("\n== oxmysql_export: detection ==")

assert_error(function() newDriver():_detect() end, "No MySQL library found",
    "no database resource started -> clear error (export proxies are not enough)")

resourceStates.oxmysql = "started"
local driver = newDriver()
driver:_detect()
assert_eq(driver._mode, "oxmysql_export", "oxmysql started, no MySQL global -> oxmysql_export")

resourceStates["mysql-async"] = "started"
driver = newDriver()
driver:_detect()
assert_eq(driver._mode, "oxmysql_export", "oxmysql is preferred when mysql-async is also started")
resourceStates["mysql-async"] = nil

-- ─── execute ───────────────────────────────────────────────────────

print("\n== oxmysql_export: execute ==")

reset()
results.executeSync = { { id = 1 } }
local rows = newDriver():execute("SELECT * FROM users", {})
assert_eq(rows[1] and rows[1].id, 1, "execute returns rows")
assert_eq(calls[1].fn, "executeSync", "execute -> exports.oxmysql:executeSync")

reset()
results.executeSync = nil
assert_eq(type(newDriver():execute("CREATE TABLE t (id INT)", {})), "table", "nil result -> empty table")

-- ─── scalar ────────────────────────────────────────────────────────

print("\n== oxmysql_export: scalar ==")

reset()
results.insertSync = 9
assert_eq(newDriver():scalar("INSERT INTO users (a) VALUES (?)", { 1 }), 9, "INSERT returns insertId")
assert_eq(calls[1].fn, "insertSync", "INSERT -> insertSync")

reset()
results.updateSync = 4
assert_eq(newDriver():scalar("UPDATE users SET a = 1", {}), 4, "UPDATE returns affectedRows")
assert_eq(calls[1].fn, "updateSync", "UPDATE -> updateSync")

reset()
results.executeSync = { { n = 1 } }
newDriver():scalar("SELECT COUNT(*) AS n FROM users", {})
assert_eq(calls[1].fn, "executeSync", "SELECT scalar -> executeSync")

-- ─── transaction ───────────────────────────────────────────────────

print("\n== oxmysql_export: transaction ==")

local queries = { { query = "INSERT INTO a VALUES (?)", values = { 1 } } }

reset()
results.transactionSync = true
assert_eq(newDriver():transaction(queries), true, "successful transaction -> true")
assert_eq(calls[1].fn, "transactionSync", "transaction -> transactionSync")

reset()
results.transactionSync = false
assert_eq(newDriver():transaction(queries), false, "failed transaction -> false")

-- ─── Thread requirement ────────────────────────────────────────────

print("\n== oxmysql_export: thread requirement ==")

registered.oxmysql.executeSync = function()
    -- A sync export awaits a JS promise, which yields the calling thread.
    coroutine.yield()
    return {}
end
assert_error(function() newDriver():execute("SELECT 1", {}) end,
    "Citizen.CreateThread", "outside a thread -> clear error naming Citizen.CreateThread")

registered.oxmysql.executeSync = syncExport("executeSync")
reset()
results.executeSync = { error = "Unknown column 'x'" }
assert_error(function() newDriver():execute("SELECT x FROM users", {}) end,
    "Unknown column 'x'", "SQL errors keep their original message outside a thread")

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
