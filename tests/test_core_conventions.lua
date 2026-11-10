-- tests/test_core_conventions.lua
-- Regression tests for the public API conventions: write results, error
-- positions, lifecycle hooks, cache invalidation after transactions and raw
-- SQL, the resource version and the ORM-managed columns.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_core_conventions.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = {
    encode = function(t) return tostring(t) end,
    decode = function(s) return s end,
}

MySQL = {}

promise = {
    new = function()
        local p = {}
        function p:resolve(v) self._value = v end
        return p
    end,
}

Citizen = { Await = function(p) return p._value end }

exports = setmetatable({}, {
    __index = function()
        return setmetatable({}, { __index = function() return function() return nil end end })
    end,
})

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

local function assertContains(str, fragment, msg)
    str = tostring(str)
    report(str:find(fragment, 1, true) ~= nil, msg, ("'%s' does not contain '%s'"):format(str, fragment))
end

local function assertNotContains(str, fragment, msg)
    str = tostring(str)
    report(str:find(fragment, 1, true) == nil, msg, ("'%s' unexpectedly contains '%s'"):format(str, fragment))
end

--- Runs fn, expects it to raise, and returns the error message.
local function errorOf(fn)
    local ok, err = pcall(fn)
    if ok then return "<no error raised>" end
    return tostring(err)
end

local THIS_FILE = "test_core_conventions.lua:"

--- Adapter double: logs every statement, replays queued SELECT results and
--- returns `writeResult` for UPDATE / DELETE statements.
local function fakeAdapter()
    local adapter = { log = {}, queue = {}, transactions = {}, nextId = 1, writeResult = 1, transactionResult = true }
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
        return self.writeResult
    end
    function adapter:transaction(queries)
        self.transactions[#self.transactions + 1] = queries
        return self.transactionResult
    end
    function adapter:reset()
        self.log, self.queue, self.transactions = {}, {}, {}
        self.writeResult, self.transactionResult = 1, true
    end
    return adapter
end

local Helpers     = require("utils.helpers")
local Validator   = require("utils.validator")
local Errors      = require("utils.errors")
local SchemaLib   = require("core.schema")
local Query       = require("core.query")
local Transaction = require("core.transaction")
local Model       = require("core.model")
local ORM         = require("core.orm")

local db = fakeAdapter()

local User = ORM.model("conv_users", {
    id = "number", name = "string", money = "number",
}, { adapter = db })

-- ─── #38 / #50: write methods return the affected row count ────────

print("\n== Write methods return the affected row count ==")

db:reset()
db.writeResult = 3
assertEq(User.update({ money = 1 }, { name = "x" }), 3, "M.update returns the driver's affected rows")
assertEq(User.updateWhere({ name = "x" }, { money = 1 }), 3, "M.updateWhere returns the affected rows")
assertEq(User.delete({ name = "x" }), 3, "M.delete returns the affected rows")
assertEq(User.deleteWhere({ name = "x" }), 3, "M.deleteWhere returns the affected rows")
assertEq(User.forceDelete({ name = "x" }), 3, "M.forceDelete returns the affected rows")
assertEq(User.increment("money", 5, { name = "x" }), 3, "M.increment returns the affected rows")
assertEq(User.decrement("money", 5, { name = "x" }), 3, "M.decrement returns the affected rows")

db.writeResult = 0
assertEq(User.update({ money = 1 }, { name = "nobody" }), 0, "M.update returns 0 when nothing matched")

db.writeResult = nil
assertEq(User.delete({ name = "nobody" }), 0, "a nil driver result counts as 0 rows")

db.writeResult = { affectedRows = 2 }
assertEq(User.update({ money = 1 }, { name = "x" }), 2, "a result table's affectedRows is used")

db:reset()
db.queue = { { { id = 7, name = "ann", money = 10 } } }
local ann = User.find({ id = 7 })
db.writeResult = 1
assertEq(ann:update({ money = 20 }), 1, "Instance:update returns the affected rows")
assertEq(ann:increment("money"), 1, "Instance:increment returns the affected rows")
assertEq(ann:decrement("money"), 1, "Instance:decrement returns the affected rows")
db.writeResult = 0
assertEq(ann:delete(), 0, "Instance:delete returns 0 when the row was already gone")
assertEq(ann:forceDelete(), 0, "Instance:forceDelete returns the affected rows")

local SoftUser = ORM.model("conv_soft", { id = "number", name = "string" }, { adapter = db, softDelete = true })
db:reset()
db.writeResult = 4
assertEq(SoftUser.restore({ name = "x" }), 4, "M.restore returns the affected rows")
assertEq(SoftUser.delete({ name = "x" }), 4, "soft M.delete returns the affected rows")

-- ─── #50: misuse errors point at the caller ────────────────────────

print("\n== Misuse errors point at the caller ==")

local err = errorOf(function() User.update({ money = 1 }, {}) end)
assertContains(err, THIS_FILE, "update() without where reports the caller's line")
assertContains(err, "update() requires a where clause", "update() without where keeps its message")

err = errorOf(function() User.create({ bogus = 1 }) end)
assertContains(err, THIS_FILE, "create() validation error reports the caller's line")
assertNotContains(err, "core/model.lua", "create() validation error does not point into the library")

err = errorOf(function() User.createMany({ { bogus = 1 } }) end)
assertContains(err, THIS_FILE, "createMany() validation error reports the caller's line")

err = errorOf(function() User.update({ money = "lots" }, { id = 1 }) end)
assertContains(err, THIS_FILE, "update() type error reports the caller's line")

db.queue = { { { id = 8, name = "bob", money = 1 } } }
local bob = User.find({ id = 8 })
err = errorOf(function() bob:update({ money = "lots" }) end)
assertContains(err, THIS_FILE, "Instance:update validation error reports the caller's line")

err = errorOf(function() User.findOrFail({ id = 999 }) end)
assertContains(err, THIS_FILE, "findOrFail() reports the caller's line")

err = errorOf(function() SoftUser.restore({}) end)
assertContains(err, THIS_FILE, "restore() without where reports the caller's line")

err = errorOf(function() User.restore({ id = 1 }) end)
assertContains(err, THIS_FILE, "restore() on a model without soft delete reports the caller's line")

-- ─── #50: validation reports the first field in sorted order ───────

print("\n== Validation is deterministic ==")

local unknownKeys = {}
for i = 1, 12 do unknownKeys[#unknownKeys + 1] = ("field_%02d"):format(i) end

local allFirst = true
for shift = 0, 11 do
    local data = {}
    for i = 1, #unknownKeys do
        data[unknownKeys[(i + shift - 1) % #unknownKeys + 1]] = i
    end
    local _, firstError = Validator.validate(data, { id = "number" })
    if not tostring(firstError):find("field_01", 1, true) then allFirst = false end
end
assertEq(allFirst, true, "the reported field is always the first in sorted order")

local _, mixedError = Validator.validate({ zeta = 1, alpha = "x" }, { zeta = "string", alpha = "string" })
assertContains(mixedError, "zeta", "a type error is reported when it is the only one")

-- ─── #44: the validator has a single type check ────────────────────

print("\n== Validator.checkType is the single type check ==")

local checkOk, checkErr = Validator.checkType("money", "lots", "number")
local _, validateErr = Validator.validate({ money = "lots" }, { money = "number" })
assertEq(checkOk, false, "checkType rejects a wrong type")
assertEq(validateErr, checkErr, "validate reports exactly what checkType reports")

local originalCheck = Validator.checkType
local checkCalls = 0
Validator.checkType = function(...)
    checkCalls = checkCalls + 1
    return originalCheck(...)
end
Validator.validate({ money = 1, name = "x" }, { money = "number", name = "string" })
Validator.checkType = originalCheck
assertEq(checkCalls, 2, "validate delegates every field to checkType")

-- ─── #44: unused public helpers are gone ───────────────────────────

print("\n== Unused helpers removed ==")

local schema = SchemaLib.new({ id = "number" })
assertEq(schema.typeOf, nil, "Schema:typeOf is removed")
assertEq(schema.hasField, nil, "Schema:hasField is removed")
assertEq(schema.fieldNames, nil, "Schema.fieldNames is no longer built")
assertEq(Errors.definition, nil, "Errors.definition is removed")

-- ─── #24: sortedKeys returns a fresh sorted array ──────────────────

print("\n== Helpers.sortedKeys ==")

local keys = Helpers.sortedKeys({ b = 1, a = 2, c = 3 })
assertEq(table.concat(keys, ","), "a,b,c", "keys are sorted")
keys[1] = "mutated"
assertEq(Helpers.sortedKeys({ a = 1, b = 2, c = 3 })[1], "a", "mutating a result does not leak into later calls")
assertEq(table.concat(Helpers.sortedKeys({ only = 1 }), ","), "only", "a single key is returned as is")
assertEq(#Helpers.sortedKeys({}), 0, "an empty table has no keys")

-- ─── #49: class-level writes fire lifecycle hooks ──────────────────

print("\n== Class-level writes fire hooks ==")

local events = {}
local function record(name) return function(...) events[#events + 1] = { name = name, args = { ... } } end end

local Audited = ORM.model("conv_audited", { id = "number", name = "string", money = "number" }, { adapter = db })
for _, event in ipairs({
    "beforeCreate", "afterBulkCreate", "beforeBulkUpdate", "afterBulkUpdate",
    "beforeBulkDelete", "afterBulkDelete", "beforeUpsert", "afterUpsert",
}) do
    Audited[event](record(event))
end

local function eventNames()
    local names = {}
    for i, e in ipairs(events) do names[i] = e.name end
    return table.concat(names, ",")
end

db:reset()
db.writeResult = 2
events = {}
Audited.beforeBulkUpdate(function(data) data.money = 99 end)
local updateWhere = { name = "x" }
Audited.update({ money = 1 }, updateWhere)
assertEq(eventNames(), "beforeBulkUpdate,afterBulkUpdate", "M.update fires beforeBulkUpdate then afterBulkUpdate")
assertEq(events[1].args[2], updateWhere, "beforeBulkUpdate receives the where clause")
assertEq(events[2].args[3], 2, "afterBulkUpdate receives the affected rows")
assertEq(db.log[1].params[1], 99, "a beforeBulkUpdate hook can change the data written")

events = {}
Audited.updateWhere({ name = "x" }, { money = 1 })
assertEq(eventNames(), "beforeBulkUpdate,afterBulkUpdate", "updateWhere fires the bulk update hooks once")

events = {}
Audited.delete({ name = "x" })
assertEq(eventNames(), "beforeBulkDelete,afterBulkDelete", "M.delete fires the bulk delete hooks")
assertEq(events[2].args[2], 2, "afterBulkDelete receives the affected rows")

events = {}
Audited.deleteWhere({ name = "x" })
Audited.forceDelete({ name = "x" })
assertEq(eventNames(), "beforeBulkDelete,afterBulkDelete,beforeBulkDelete,afterBulkDelete",
    "deleteWhere and forceDelete fire the bulk delete hooks")

events = {}
Audited.upsert({ id = 1, name = "x" })
assertEq(eventNames(), "beforeUpsert,afterUpsert", "upsert fires beforeUpsert and afterUpsert")

events = {}
Audited.beforeCreate(function(data) data.money = 5 end)
local template = { name = "row" }
db:reset()
Audited.createMany({ template, { name = "row2" } })
assertEq(eventNames(), "beforeCreate,beforeCreate,afterBulkCreate", "createMany fires beforeCreate per row, then afterBulkCreate")
assertEq(template.money, nil, "createMany hooks receive copies, not the caller's rows")
assertContains(db.log[1].sql, "`money`", "a beforeCreate hook can add a column to createMany rows")
assertEq(#events[3].args[1], 2, "afterBulkCreate receives the inserted rows")

assertEq(type(Model.HOOK_EVENTS), "table", "the supported hook events are exposed")
local exposed = {}
for _, event in ipairs(Model.HOOK_EVENTS) do exposed[event] = true end
assertEq(exposed.beforeBulkUpdate and exposed.afterUpsert and exposed.beforeCreate, true, "HOOK_EVENTS lists bulk and instance hooks")

-- ─── #56: find / findAll without arguments ─────────────────────────

print("\n== find / findAll without arguments ==")

db:reset()
db.queue = { { { id = 1, name = "a" }, { id = 2, name = "b" } } }
local everyone = User.findAll()
assertEq(#everyone, 2, "findAll() with no arguments returns every row")
assertEq(db.log[1].sql, "SELECT * FROM `conv_users`", "findAll() builds a SELECT without WHERE")

db:reset()
db.queue = { { { id = 1, name = "a" } } }
local firstUser = User.find()
assertEq(firstUser and firstUser.id, 1, "find() with no arguments returns the first row")

-- ─── #52: ORM-managed columns pass validation ──────────────────────

print("\n== Timestamp and soft delete columns are allowed ==")

local stampedFields = { id = "number", name = "string" }
local Stamped = ORM.model("conv_stamped", stampedFields, { adapter = db, timestamps = true, softDelete = true })

db:reset()
local ok = pcall(Stamped.create, { name = "a", created_at = "2024-01-01 00:00:00", updated_at = "2024-01-01 00:00:00" })
assertEq(ok, true, "create accepts undeclared created_at / updated_at when timestamps are on")
ok = pcall(Stamped.update, { deleted_at = "2024-01-01 00:00:00" }, { id = 1 })
assertEq(ok, true, "update accepts an undeclared deleted_at when soft delete is on")

Stamped.beforeCreate(function(data) data.created_at = "2020-01-01 00:00:00" end)
ok = pcall(Stamped.create, { name = "b" })
assertEq(ok, true, "a beforeCreate hook may set created_at")
assertEq(stampedFields.created_at, nil, "the caller's fields table is not modified")

ok = pcall(User.create, { name = "a", updated_at = "2024-01-01 00:00:00" })
assertEq(ok, false, "updated_at stays unknown when timestamps are off")

-- ─── #5: transactions and raw SQL invalidate the cache ─────────────

print("\n== Transactions and raw SQL invalidate the cache ==")

ORM.setAdapter(db)
ORM.enableCache()

local function cachedFind()
    db.queue = { { { id = 1, name = "a", money = 5 } } }
    return User.find({ id = 1 })
end

local function selects()
    local n = 0
    for _, entry in ipairs(db.log) do
        if entry.sql:find("SELECT * FROM `conv_users`", 1, true) == 1 then n = n + 1 end
    end
    return n
end

db:reset()
cachedFind()
cachedFind()
assertEq(selects(), 1, "a repeated find is served from the cache")

ORM.transaction(function(tx) tx:update("conv_users", { money = 0 }, { id = 1 }) end)
cachedFind()
assertEq(selects(), 2, "ORM.transaction invalidates the tables it wrote")

cachedFind()
local tx = ORM.transaction()
tx:insert("conv_users", { name = "z" })
assertEq(tx:commit(), true, "a manual transaction still commits")
cachedFind()
assertEq(selects(), 3, "a manual ORM transaction invalidates on commit")

cachedFind()
db.transactionResult = false
ORM.transaction(function(t) t:update("conv_users", { money = 0 }, { id = 1 }) end)
db.transactionResult = true
cachedFind()
assertEq(selects(), 3, "a failed commit leaves the cache alone")

ORM.transaction(function(t) t:addRaw("CALL refresh_everything()") end)
cachedFind()
assertEq(selects(), 4, "an unparseable raw statement flushes the cache")

cachedFind()
ORM.rawExec("UPDATE `conv_users` SET money = 0")
cachedFind()
assertEq(selects(), 5, "ORM.rawExec invalidates the table it wrote")

cachedFind()
ORM.rawExec("SELECT 1")
cachedFind()
assertEq(selects(), 5, "a read through rawExec keeps the cache")

ORM.raw("DELETE FROM conv_users WHERE id = 3")
cachedFind()
assertEq(selects(), 6, "ORM.raw invalidates a write as well")

local plainTx = Transaction.new(db)
plainTx:insert("conv_users", { name = "q" })
assertEq(plainTx:commit(), true, "a transaction without a cache still commits")

ORM.disableCache()

print("\n== Query.writtenTables ==")

local function tables(sql)
    local list = Query.writtenTables(sql)
    return list and table.concat(list, ",") or "nil"
end

assertEq(tables("INSERT INTO `users` (`a`) VALUES (?)"), "users", "INSERT INTO")
assertEq(tables("INSERT IGNORE INTO users (a) VALUES (?)"), "users", "INSERT IGNORE INTO")
assertEq(tables("REPLACE INTO `db`.`users` (a) VALUES (?)"), "users", "REPLACE INTO a qualified table")
assertEq(tables("update `users` SET `a` = ?"), "users", "UPDATE, any case")
assertEq(tables("DELETE FROM users WHERE id = ?"), "users", "DELETE FROM")
assertEq(tables("TRUNCATE TABLE users"), "users", "TRUNCATE TABLE")
assertEq(tables("  SELECT * FROM users"), "", "a SELECT writes nothing")
assertEq(tables("SHOW TABLES"), "", "SHOW writes nothing")
assertEq(tables("UPDATE users u JOIN posts p ON p.uid = u.id SET u.a = 1"), "nil", "a multi-table UPDATE is unknown")
assertEq(tables("UPDATE users, posts SET users.a = 1"), "nil", "a comma-joined UPDATE is unknown")
assertEq(tables("DELETE u FROM users u JOIN posts p ON 1"), "nil", "a multi-table DELETE is unknown")
assertEq(tables("UPDATE users SET a = 1; DROP TABLE x"), "nil", "several statements are unknown")
assertEq(tables("ALTER TABLE users ADD c INT"), "nil", "DDL is unknown")

-- ─── #42: the version comes from fxmanifest.lua ────────────────────

print("\n== Version from the resource metadata ==")

assertEq(ORM.version, "dev", "outside FiveM the version falls back to 'dev'")

local metadataCalls = {}
function GetCurrentResourceName() return "orvexorm" end
function GetResourceMetadata(resource, key, index)
    metadataCalls[#metadataCalls + 1] = { resource, key, index }
    return "9.8.7"
end
package.loaded["core.orm"] = nil
OrvexORM = nil
local reloaded = require("core.orm")
assertEq(reloaded.version, "9.8.7", "ORM.version reads the fxmanifest version")
assertEq(metadataCalls[1] and metadataCalls[1][1] .. ":" .. metadataCalls[1][2] .. ":" .. metadataCalls[1][3],
    "orvexorm:version:0", "the metadata is read for the current resource")

function GetResourceMetadata() return nil end
package.loaded["core.orm"] = nil
OrvexORM = nil
assertEq(require("core.orm").version, "dev", "a missing version entry falls back to 'dev'")
GetResourceMetadata, GetCurrentResourceName = nil, nil

local manifest = io.open("fxmanifest.lua"):read("a")
local orm = io.open("core/orm.lua"):read("a")
assertEq(manifest:match("\nversion '([^']+)'") ~= nil, true, "fxmanifest.lua declares the version")
assertEq(orm:match('version%s*=%s*"%d') == nil, true, "core/orm.lua no longer hard-codes a version")

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
