-- tests/test_driver_oxmysql.lua
-- Driver mode "oxmysql_global": the MySQL global exported by @oxmysql/lib/MySQL.lua.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_driver_oxmysql.lua

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

-- Mirrors the real scheduler: Await yields while the promise is pending,
-- which raises "attempt to yield from outside a coroutine" outside a thread.
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

exports = setmetatable({}, {
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, method)
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

--- Builds an oxmysql lib function: callable with a callback, plus an .await form.
local function oxFunction(name)
    return setmetatable({
        await = function(query, params)
            calls[#calls + 1] = { fn = name, style = "await", sql = query, params = params }
            local r = results[name]
            if type(r) == "table" and r.error then error(r.error) end
            return r
        end,
    }, {
        __call = function(_, query, params, cb)
            calls[#calls + 1] = { fn = name, style = "callback", sql = query, params = params }
            cb(results[name])
        end,
    })
end

MySQL = {
    query = oxFunction("query"),
    insert = oxFunction("insert"),
    update = oxFunction("update"),
    prepare = oxFunction("prepare"),
    transaction = oxFunction("transaction"),
}

local Driver = require("database.mysql")

local function newDriver()
    Driver._mode = nil
    return Driver.new()
end

-- ─── Detection ─────────────────────────────────────────────────────

print("\n== oxmysql_global: detection ==")

local driver = newDriver()
driver:_detect()
assert_eq(driver._mode, "oxmysql_global", "MySQL global with prepare -> oxmysql_global")

-- ─── execute ───────────────────────────────────────────────────────

print("\n== oxmysql_global: execute ==")

reset()
results.query = { { id = 1 }, { id = 2 } }
local rows = newDriver():execute("SELECT * FROM users WHERE id = ?", { 1 })
assert_eq(#rows, 2, "execute returns every row")
assert_eq(calls[1].fn, "query", "execute goes through MySQL.query (text protocol, no flattening)")
assert_eq(calls[1].style, "await", "execute uses MySQL.query.await (raises on SQL error)")

reset()
results.query = nil
rows = newDriver():execute("CREATE TABLE t (id INT)", {})
assert_eq(type(rows), "table", "execute returns a table when oxmysql returns nil")

reset()
results.query = { error = "Table 'x' doesn't exist" }
assert_error(function() newDriver():execute("SELECT * FROM x", {}) end,
    "doesn't exist", "SQL error raised by .await propagates instead of hanging")

-- ─── scalar ────────────────────────────────────────────────────────

print("\n== oxmysql_global: scalar ==")

reset()
results.insert = 42
assert_eq(newDriver():scalar("INSERT INTO users (name) VALUES (?)", { "a" }), 42, "INSERT returns insertId")
assert_eq(calls[1].fn .. ":" .. calls[1].style, "insert:await", "INSERT -> MySQL.insert.await")

reset()
results.update = 3
assert_eq(newDriver():scalar("UPDATE users SET a = ?", { 1 }), 3, "UPDATE returns affectedRows")
assert_eq(calls[1].fn .. ":" .. calls[1].style, "update:await", "UPDATE -> MySQL.update.await")

reset()
results.update = 2
newDriver():scalar("DELETE FROM users WHERE id = ?", { 1 })
assert_eq(calls[1].fn, "update", "DELETE -> MySQL.update")

reset()
results.query = { { n = 5 } }
newDriver():scalar("SELECT COUNT(*) AS n FROM users", {})
assert_eq(calls[1].fn, "query", "SELECT scalar -> MySQL.query")

-- ─── transaction ───────────────────────────────────────────────────

print("\n== oxmysql_global: transaction ==")

local queries = { { query = "INSERT INTO a VALUES (?)", values = { 1 } } }

reset()
results.transaction = true
assert_eq(newDriver():transaction(queries), true, "successful transaction -> true")
assert_eq(calls[1].fn .. ":" .. calls[1].style, "transaction:await", "uses MySQL.transaction.await")
assert_eq(calls[1].sql, queries, "queries are passed through unchanged")

reset()
results.transaction = false
assert_eq(newDriver():transaction(queries), false, "failed transaction -> false")

-- ─── Prepared statements are not used ─────────────────────────────

print("\n== oxmysql_global: no prepared statements ==")

local usedPrepare = false
for _, c in ipairs(calls) do
    if c.fn == "prepare" then usedPrepare = true end
end
assert_eq(usedPrepare, false, "MySQL.prepare is never used (it flattens single-row results)")

-- ─── Legacy lib without .await ─────────────────────────────────────

print("\n== oxmysql_global: callback-only lib ==")

reset()
local savedQuery = MySQL.query
MySQL.query = function(query, params, cb)
    calls[#calls + 1] = { fn = "query", style = "callback", sql = query, params = params }
    cb({ { id = 7 } })
end
rows = newDriver():execute("SELECT * FROM users", {})
assert_eq(rows[1] and rows[1].id, 7, "falls back to the callback form when .await is missing")
MySQL.query = savedQuery

-- ─── Thread requirement ────────────────────────────────────────────

print("\n== oxmysql_global: thread requirement ==")

local pendingCb
MySQL.query = function(_, _, cb) pendingCb = cb end

assert_error(function() newDriver():execute("SELECT 1", {}) end,
    "Citizen.CreateThread", "outside a thread -> clear error naming Citizen.CreateThread")

local threadRows
local thread = coroutine.create(function()
    threadRows = newDriver():execute("SELECT 1", {})
end)
coroutine.resume(thread)
pendingCb({ { one = 1 } })
coroutine.resume(thread)
assert_eq(threadRows and threadRows[1].one, 1, "inside a thread the call yields then resumes with rows")
MySQL.query = savedQuery

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
