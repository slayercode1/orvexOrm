-- tests/test_driver_mysql_async.lua
-- Driver mode "mysql-async": reached through exports['mysql-async'] (default fxmanifest)
-- or through the MySQL.Async global (when @mysql-async/lib/MySQL.lua is loaded).
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_driver_mysql_async.lua

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

local resourceStates = { ["mysql-async"] = "started" }
function GetResourceState(name)
    return resourceStates[name] or "missing"
end

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

local function record(name, query, params)
    calls[#calls + 1] = { fn = name, sql = query, params = params }
end

--- mysql-async API keyed by export name; `self` is dropped so it also backs MySQL.Async.
local api = {
    mysql_fetch_all = function(query, params, cb)
        record("mysql_fetch_all", query, params)
        if results.fetch_all_nil then cb(nil) else cb(results.fetch_all or {}) end
    end,
    mysql_execute = function(query, params, cb) record("mysql_execute", query, params); cb(results.execute or 0) end,
    mysql_insert = function(query, params, cb) record("mysql_insert", query, params); cb(results.insert) end,
    mysql_transaction = function(queries, params, cb)
        record("mysql_transaction", queries, params)
        cb(results.transaction)
    end,
}

local function asExports(fns)
    local t = {}
    for name, fn in pairs(fns) do
        t[name] = function(_, ...) return fn(...) end
    end
    return t
end

registered["mysql-async"] = asExports(api)

local Driver = require("database.mysql")

local function newDriver()
    Driver._mode = nil
    return Driver.new()
end

local function sentSQL()
    local list = {}
    for _, c in ipairs(calls) do
        if type(c.sql) == "string" then list[#list + 1] = c.sql:upper() end
    end
    return table.concat(list, ";")
end

local queries = {
    { query = "INSERT INTO a (v) VALUES (?)", values = { 1 } },
    { query = "UPDATE b SET v = ?", values = { 2 } },
}

local function runSuite(label)
    print(("\n== mysql-async (%s): routing =="):format(label))

    local driver = newDriver()
    driver:_detect()
    assert_eq(driver._mode, "mysql-async", "detected as mysql-async")

    reset()
    results.fetch_all = { { id = 1 }, { id = 2 } }
    local rows = newDriver():execute("SELECT * FROM users", {})
    assert_eq(#rows, 2, "execute SELECT returns rows")
    assert_eq(calls[1].fn, "mysql_fetch_all", "execute SELECT -> fetchAll")

    reset()
    newDriver():execute("UPDATE users SET a = 1", {})
    assert_eq(calls[1].fn, "mysql_execute", "execute UPDATE -> execute")

    for _, sql in ipairs({
        "DESC users", "describe users", "SHOW TABLES", "EXPLAIN SELECT 1",
        "WITH t AS (SELECT 1 AS n) SELECT n FROM t", "(SELECT 1) UNION (SELECT 2)", "  ( select 1 )",
    }) do
        reset()
        results.fetch_all = { { n = 1 } }
        local readRows = newDriver():execute(sql, {})
        assert_eq(calls[1].fn, "mysql_fetch_all", ("execute %q -> fetchAll"):format(sql))
        assert_eq(#readRows, 1, ("execute %q returns rows"):format(sql))
    end

    reset()
    results.fetch_all = {}
    local empty = newDriver():execute("SELECT * FROM users WHERE id = ?", { 404 })
    assert_eq(type(empty) == "table" and #empty, 0, "a genuine empty read stays an empty table")

    reset()
    results.fetch_all_nil = true
    assert_error(function() newDriver():execute("SELECT * FROM bans WHERE id = ?", { 1 }) end,
        "returned no result", "execute read with nil result -> error, not an empty table")
    assert_error(function() newDriver():scalar("SELECT COUNT(*) AS n FROM bans", {}) end,
        "returned no result", "scalar read with nil result -> error")

    reset()
    results.execute = nil
    local writeRows = newDriver():execute("UPDATE users SET a = 1", {})
    assert_eq(type(writeRows) == "table" and #writeRows, 0, "execute write keeps returning a table")

    reset()
    results.insert = 11
    assert_eq(newDriver():scalar("INSERT INTO users (a) VALUES (?)", { 1 }), 11, "scalar INSERT returns insertId")
    assert_eq(calls[1].fn, "mysql_insert", "scalar INSERT -> insert")

    reset()
    results.execute = 3
    assert_eq(newDriver():scalar("DELETE FROM users", {}), 3, "scalar DELETE returns affectedRows")

    reset()
    results.fetch_all = { { n = 5 } }
    local count = newDriver():scalar("SELECT COUNT(*) AS n FROM users", {})
    assert_eq(calls[1].fn, "mysql_fetch_all", "scalar SELECT -> fetchAll (rows, not affectedRows)")
    assert_eq(type(count) == "table" and count[1].n, 5, "scalar SELECT returns rows like other drivers")

    print(("\n== mysql-async (%s): transaction =="):format(label))

    reset()
    results.transaction = true
    assert_eq(newDriver():transaction(queries), true, "successful transaction -> true")
    assert_eq(#calls, 1, "a single native transaction call")
    assert_eq(calls[1].fn, "mysql_transaction", "uses mysql-async native transaction")
    local sent = calls[1].sql
    assert_eq(#sent, 2, "every query is sent")
    assert_eq(sent[1].query, queries[1].query, "query text kept")
    assert_eq(sent[2].values, queries[2].values, "values kept")
    assert_eq(sent[2].parameters, queries[2].values, "values also given as parameters (mysql-async naming)")
    check(not sentSQL():find("BEGIN", 1, true), "no manual BEGIN on a pooled connection")

    reset()
    results.transaction = false
    assert_eq(newDriver():transaction(queries), false, "failed transaction -> false (rollback reported)")
    check(not sentSQL():find("COMMIT", 1, true), "no manual COMMIT after a failure")
end

-- ─── Through exports['mysql-async'] ────────────────────────────────

runSuite("exports")

print("\n== mysql-async (exports): thread requirement ==")

local pendingCb
registered["mysql-async"].mysql_fetch_all = function(_, _, _, cb) pendingCb = cb end
assert_error(function() newDriver():execute("SELECT 1", {}) end,
    "Citizen.CreateThread", "outside a thread -> clear error naming Citizen.CreateThread")

local threadRows
local thread = coroutine.create(function() threadRows = newDriver():execute("SELECT 1", {}) end)
coroutine.resume(thread)
pendingCb({ { one = 1 } })
coroutine.resume(thread)
assert_eq(threadRows and threadRows[1].one, 1, "inside a thread the call yields then resumes")
registered["mysql-async"] = asExports(api)

-- ─── Through the MySQL.Async global ────────────────────────────────

resourceStates["mysql-async"] = nil
MySQL = {
    Async = {
        fetchAll = api.mysql_fetch_all,
        execute = api.mysql_execute,
        insert = api.mysql_insert,
        transaction = api.mysql_transaction,
    },
}

runSuite("MySQL.Async global")

print("\n== mysql-async: without native transaction ==")

MySQL.Async.transaction = nil
reset()
assert_error(function() newDriver():transaction(queries) end,
    "mysql-async >= 3.3", "old mysql-async without transaction -> clear error")
assert_eq(#calls, 0, "nothing is sent when transactions are unavailable")

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
