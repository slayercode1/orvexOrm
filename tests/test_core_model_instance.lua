-- tests/test_core_model_instance.lua
-- Instance layout: one metatable per model, row columns only on the
-- instance, and columns named like an instance method (update, get...)
-- that no longer shadow the method.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_core_model_instance.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

json = {
    encode = function(t) return tostring(t) end,
    decode = function(s) return s end,
}

-- ─── Test helpers ──────────────────────────────────────────────────

local passed, failed = 0, 0

local function report(ok, msg, detail)
    if ok then
        passed = passed + 1
        print(("  ✓ %s"):format(msg))
    else
        failed = failed + 1
        print(("  ✗ %s — %s"):format(msg, detail))
    end
end

local function assertEq(got, expected, msg)
    report(got == expected, msg, ("expected: %s, got: %s"):format(tostring(expected), tostring(got)))
end

--- Runs fn in protected mode so a broken method call fails one assertion
--- instead of the whole suite.
local function attempt(fn)
    local ok, result = pcall(fn)
    if not ok then return nil, tostring(result) end
    return result
end

--- Adapter double: logs every statement and replays queued SELECT results.
local function fakeAdapter()
    local adapter = { log = {}, queue = {}, nextId = 1 }
    function adapter:execute(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        return table.remove(self.queue, 1) or {}
    end
    function adapter:scalar(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        if sql:match("^INSERT") then
            local id = self.nextId
            self.nextId = id + 1
            return id
        end
        return 1
    end
    function adapter:lastSql() return self.log[#self.log].sql end
    return adapter
end

local Model   = require("core.model")
local Helpers = require("utils.helpers")

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ─── Instances carry only their columns ────────────────────────────

print("\n== Instance layout ==")

local adapter = fakeAdapter()
local User = Model.new("users", { id = "number", name = "string" }, adapter)
local alice = User._wrapRow({ id = 1, name = "alice" })
local bob   = User._wrapRow({ id = 2, name = "bob" })

assertEq(countKeys(alice), 2, "an instance holds only its row columns")
assertEq(rawget(alice, "_tableName"), nil, "the model context is not copied onto the instance")
assertEq(alice._tableName, "users", "the model context stays readable through the metatable")
assertEq(getmetatable(alice), getmetatable(bob), "instances of one model share one metatable")

local Post = Model.new("posts", { id = "number" }, adapter)
assertEq(getmetatable(Post._wrapRow({ id = 1 })) ~= getmetatable(alice), true, "each model has its own metatable")

local plain = alice:toTable()
assertEq(countKeys(plain), 2, "toTable copies the columns only")
assertEq(getmetatable(plain), nil, "toTable returns a plain table")

-- ─── Row identity survives a key change ────────────────────────────

print("\n== Row identity ==")

alice:update({ id = 10 })
assertEq(adapter:lastSql():match("WHERE `id` = %?") ~= nil, true, "update targets the row by its key")
assertEq(adapter.log[#adapter.log].params[2], 1, "the first update targets the original key")
alice:update({ name = "alicia" })
assertEq(adapter.log[#adapter.log].params[2], 10, "the next update targets the new key")
assertEq(countKeys(alice), 2, "an update keeps only columns on the instance")

-- ─── Columns named like a method ───────────────────────────────────

print("\n== Columns named like a method ==")

local Task = Model.new("tasks", {
    id     = "number",
    update = "string",
    get    = "string",
}, adapter)

local task = Task._wrapRow({ id = 7, update = "weekly", get = "auto" })

assertEq(type(task.update), "function", "a column named 'update' does not shadow Instance:update")
assertEq(type(task.get), "function", "a column named 'get' does not shadow Instance:get")
assertEq(task:getAttribute("update"), "weekly", "getAttribute reads the 'update' column")
assertEq(task:getAttribute("get"), "auto", "getAttribute reads the 'get' column")
assertEq(task:getAttribute("id"), 7, "getAttribute reads ordinary columns too")

local affected, err = attempt(function() return task:update({ update = "daily" }) end)
assertEq(affected, 1, "Instance:update still works on a model with an 'update' column " .. tostring(err or ""))
assertEq(task:getAttribute("update"), "daily", "the 'update' column takes the new value")
assertEq(type(task.update), "function", "assigning the column does not clobber the method")
assertEq(adapter.log[#adapter.log].params[1], "daily", "the column value is written to the database")

task.get = "manual"
assertEq(type(task.get), "function", "a direct assignment does not clobber Instance:get")
assertEq(task:getAttribute("get"), "manual", "a direct assignment sets the 'get' column")

local snapshot = task:toTable()
assertEq(snapshot.update, "daily", "toTable includes the 'update' column")
assertEq(snapshot.get, "manual", "toTable includes the 'get' column")
assertEq(snapshot.id, 7, "toTable includes the other columns")

adapter.queue[1] = { { id = 7, update = "never", get = "auto" } }
local found = attempt(function() return task:refresh() end)
assertEq(found, true, "refresh still works on a model with method-named columns")
assertEq(task:getAttribute("update"), "never", "refresh reloads the 'update' column")
assertEq(type(task.update), "function", "refresh does not clobber the method")

adapter.queue[1] = { { id = 8, update = "x", get = "y" } }
local loaded = Task.find({ id = 8 })
assertEq(type(loaded.update), "function", "found instances keep their methods")
assertEq(loaded:toTable().update, "x", "found instances keep the column value")

-- ─── Shared time format ────────────────────────────────────────────

print("\n== nowUtc ==")

assertEq(type(Helpers.nowUtc), "function", "Helpers.nowUtc exists")
assertEq(tostring(Helpers.nowUtc and Helpers.nowUtc()):match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") ~= nil, true,
    "nowUtc returns a UTC DATETIME string")

print(("\n== Results: %d passed, %d failed =="):format(passed, failed))
if failed > 0 then os.exit(1) end
