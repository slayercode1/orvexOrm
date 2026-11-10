-- tests/test_model_crud.lua
-- Model CRUD: create, find, update, delete, upsert, JSON columns, soft delete, timestamps, shortcuts, instances.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_model_crud.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults = Mock.log, Mock.results
local reset = Mock.reset

-- ─── Test: ORM CRUD ────────────────────────────────────────────────

T.section("ORM CRUD")

reset()
local ORM = require("core.orm")

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

local player = User.create({ identifier = "license:abc", money = 500, job = "unemployed" })
T.eq(player.identifier, "license:abc", "create returns instance")
T.match(dbLog[1].sql, "INSERT INTO `users`", "create runs INSERT")

reset()
mockResults[1] = { { identifier = "license:abc", money = 500, job = "unemployed" } }
local found = User.find({ identifier = "license:abc" })
T.eq(found.money, 500, "find returns correct data")

reset()
found:update({ money = 1000 })
T.eq(found.money, 1000, "instance update changes local object")
T.match(dbLog[1].sql, "UPDATE `users` SET", "instance update runs UPDATE")

reset()
User.update({ money = 9999 }, { identifier = "license:abc" })
T.match(dbLog[1].sql, "UPDATE `users` SET", "class update runs UPDATE")

reset()
found:delete()
T.match(dbLog[1].sql, "DELETE FROM `users`", "delete runs DELETE")

reset()
User.upsert({ identifier = "license:abc", money = 2000 })
T.match(dbLog[1].sql, "ON DUPLICATE KEY UPDATE", "upsert runs UPSERT")

-- Model with auto type
reset()
local Player = ORM.model("players", {
    identifier = "string",
    position   = "auto",
    inventory  = "auto",
}, { primaryKey = "identifier" })

-- Create with auto JSON
local pp = Player.create({
    identifier = "license:json",
    position   = { x = 100, y = 200 },
    inventory  = { { item = "bread", count = 5 } },
})
T.eq(type(dbLog[1].params[2]), "string", "auto: table encoded to string on INSERT")

-- Find with auto JSON decode
reset()
mockResults[1] = { {
    identifier = "license:json",
    position = '{"x":100,"y":200}',
    inventory = '[{"item":"bread","count":5}]',
} }
local pp2 = Player.find({ identifier = "license:json" })
T.eq(type(pp2.position), "table", "auto: JSON string decoded to table on SELECT")
T.eq(pp2.position.x, 100, "auto: decoded JSON has correct values")

-- ─── Test: Soft Delete ────────────────────────────────────────────

T.section("Soft Delete")

reset()
local SoftUser = ORM.model("soft_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier", softDelete = true })

-- Create works normally
local su = SoftUser.create({ identifier = "license:soft1", money = 100 })
T.eq(su.identifier, "license:soft1", "soft delete: create works")

-- Delete sets deleted_at instead of DELETE FROM
reset()
mockResults[1] = { { identifier = "license:soft1", money = 100, deleted_at = nil } }
local su2 = SoftUser.find({ identifier = "license:soft1" })
reset()
su2:delete()
T.match(dbLog[1].sql, "UPDATE `soft_users` SET", "soft delete: delete uses UPDATE")
T.match(dbLog[1].sql, "deleted_at", "soft delete: delete sets deleted_at")

-- forceDelete uses real DELETE
reset()
su2:forceDelete()
T.match(dbLog[1].sql, "DELETE FROM `soft_users`", "soft delete: forceDelete uses DELETE")

-- Class-level delete also uses UPDATE
reset()
SoftUser.delete({ identifier = "license:soft1" })
T.match(dbLog[1].sql, "UPDATE `soft_users` SET", "soft delete: class delete uses UPDATE")

-- Class-level forceDelete uses real DELETE
reset()
SoftUser.forceDelete({ identifier = "license:soft1" })
T.match(dbLog[1].sql, "DELETE FROM `soft_users`", "soft delete: class forceDelete uses DELETE")

-- query() auto-adds IS NULL filter
local b_soft = SoftUser.query()
local sql_soft = b_soft:toSQL()
T.match(sql_soft, "`deleted_at` IS NULL", "soft delete: query auto-filters")

-- withTrashed() does not filter
local b_trashed = SoftUser.withTrashed()
local sql_trashed = b_trashed:toSQL()
-- Should NOT have deleted_at filter
local has_filter = sql_trashed:match("deleted_at")
T.eq(has_filter, nil, "soft delete: withTrashed has no filter")

-- onlyTrashed() filters for deleted
local b_only = SoftUser.onlyTrashed()
local sql_only = b_only:toSQL()
T.match(sql_only, "`deleted_at` IS NOT NULL", "soft delete: onlyTrashed filters deleted")

-- ─── Test: Timestamps ─────────────────────────────────────────────

T.section("Timestamps")

reset()
local TSUser = ORM.model("ts_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier", timestamps = true })

local ts = TSUser.create({ identifier = "license:ts1", money = 100 })
T.eq(type(ts.created_at), "string", "timestamps: created_at auto-set")
T.eq(type(ts.updated_at), "string", "timestamps: updated_at auto-set")

-- Update should set updated_at
reset()
mockResults[1] = { { identifier = "license:ts2", money = 100, created_at = "2025-01-01", updated_at = "2025-01-01" } }
local ts2 = TSUser.find({ identifier = "license:ts2" })
reset()
ts2:update({ money = 200 })
T.match(dbLog[1].sql, "updated_at", "timestamps: update sets updated_at")

local ScopeUser = ORM.model("scope_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- ─── Test: createMany ─────────────────────────────────────────────

T.section("createMany")

reset()
ScopeUser.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
T.eq(#dbLog, 1, "createMany: single SQL query")
T.match(dbLog[1].sql, "INSERT INTO `scope_users`", "createMany: INSERT query")
T.match(dbLog[1].sql, "VALUES %(", "createMany: has VALUES")

-- ─── Test: Increment / Decrement ──────────────────────────────────

T.section("Increment / Decrement")

-- Class-level increment
reset()
ScopeUser.increment("money", 500, { identifier = "license:a" })
T.match(dbLog[1].sql, "`money` = `money` %+ %?", "class increment: SQL correct")
T.eq(dbLog[1].params[1], 500, "class increment: amount param correct")

-- Class-level decrement
reset()
ScopeUser.decrement("money", 100, { identifier = "license:a" })
T.match(dbLog[1].sql, "`money` = `money` %- %?", "class decrement: SQL correct")

-- Instance increment
reset()
mockResults[1] = { { identifier = "license:inc", money = 1000, job = "test" } }
local incUser = ScopeUser.find({ identifier = "license:inc" })
reset()
incUser:increment("money", 250)
T.eq(incUser.money, 1250, "instance increment: local value updated")
T.match(dbLog[1].sql, "`money` = `money` %+ %?", "instance increment: SQL correct")

-- Instance decrement
reset()
incUser:decrement("money", 50)
T.eq(incUser.money, 1200, "instance decrement: local value updated")

-- Instance increment with default amount
reset()
incUser:increment("money")
T.eq(incUser.money, 1201, "instance increment: default amount is 1")

-- ─── Test: Select partial ─────────────────────────────────────────

T.section("Select Partial")

reset()
mockResults[1] = { { identifier = "license:sel", money = 500 } }
local partial = ScopeUser.find({ identifier = "license:sel" }, { select = { "money" } })
T.match(dbLog[1].sql, "SELECT `money`, `identifier` FROM", "select partial: correct columns (with PK)")

-- ─── Test: Model shortcuts ──────────────────────────────────────

T.section("Model shortcuts")

-- findOrFail: found
reset()
mockResults[1] = { { identifier = "license:exists", money = 500, job = "test" } }
local fof = User.findOrFail({ identifier = "license:exists" })
T.eq(fof.identifier, "license:exists", "findOrFail: returns instance when found")

-- findOrFail: not found → error
reset()
mockResults[1] = {}
local fofOk, fofErr = pcall(function()
    User.findOrFail({ identifier = "license:nope" })
end)
T.eq(fofOk, false, "findOrFail: throws error when not found")
T.match(fofErr, "Record not found", "findOrFail: error message correct")

-- Model.first
reset()
mockResults[1] = { { identifier = "license:first", money = 100, job = "test" } }
local firstUser = User.first({ job = "test" })
T.eq(firstUser.identifier, "license:first", "Model.first: returns first match")
T.match(dbLog[1].sql, "LIMIT 1", "Model.first: adds LIMIT 1")

-- Model.first without where
reset()
mockResults[1] = { { identifier = "license:any", money = 100, job = "test" } }
local anyUser = User.first()
T.eq(anyUser.identifier, "license:any", "Model.first: works without where")

-- Model.exists (true)
reset()
mockResults[1] = { { ["1"] = 1 } }
local ex = User.exists({ job = "police" })
T.eq(ex, true, "Model.exists: returns true")

-- Model.exists (false)
reset()
mockResults[1] = {}
local nex = User.exists({ job = "unicorn" })
T.eq(nex, false, "Model.exists: returns false")

-- Model.pluck
reset()
mockResults[1] = { { money = 100 }, { money = 200 }, { money = 300 } }
local moneys = User.pluck("money", { job = "police" })
T.eq(#moneys, 3, "Model.pluck: returns 3 values")
T.eq(moneys[1], 100, "Model.pluck: value correct")

-- Model.updateWhere
reset()
User.updateWhere({ identifier = "license:uw" }, { money = 9999 })
T.match(dbLog[1].sql, "UPDATE", "updateWhere: runs UPDATE")
T.match(dbLog[1].sql, "`money` = %?", "updateWhere: sets money")

-- Model.deleteWhere
reset()
User.deleteWhere({ identifier = "license:dw" })
T.match(dbLog[1].sql, "DELETE", "deleteWhere: runs DELETE")

-- upsert keeps created_at on duplicate
T.section("upsert timestamps")

reset()
local UPUser = ORM.model("up_users", {
    id         = "number",
    name       = "string",
    created_at = "datetime",
    updated_at = "datetime",
}, { primaryKey = "id", timestamps = true })
UPUser.upsert({ id = 1, name = "Bob" })
T.match(dbLog[1].sql, "ON DUPLICATE KEY UPDATE", "upsert: generates upsert SQL")
T.eq(dbLog[1].sql:find("`created_at` = VALUES", 1, true), nil, "upsert: created_at not overwritten on duplicate")
T.match(dbLog[1].sql, "`updated_at` = VALUES%(`updated_at`%)", "upsert: updated_at refreshed on duplicate")

-- toTable
T.section("Instance:toTable")

reset()
local TTUser = ORM.model("tt_users", {
    id       = "number",
    name     = "string",
    position = "json",
}, { primaryKey = "id" })

mockResults[1] = { { id = 1, name = "Bob", position = '{"x":10}' } }
local ttInst = TTUser.find({ id = 1 })
local plain = ttInst:toTable()
T.eq(plain.id, 1, "toTable: keeps public fields")
T.eq(plain.name, "Bob", "toTable: keeps name")
T.eq(plain._tableName, nil, "toTable: strips private fields")
T.eq(plain._adapter, nil, "toTable: strips adapter")
T.eq(getmetatable(plain), nil, "toTable: no metatable")
T.eq(type(plain.position), "table", "toTable: json field stays decoded")

-- refresh
T.section("Instance:refresh")

reset()
mockResults[1] = { { id = 2, name = "Old", position = nil } }
local rfInst = TTUser.find({ id = 2 })
mockResults[2] = { { id = 2, name = "New", position = nil } }
local refreshed = rfInst:refresh()
T.eq(refreshed, true, "refresh: returns true when row exists")
T.eq(rfInst.name, "New", "refresh: reloads fields from DB")

reset()
mockResults[1] = { { id = 3, name = "Ghost" } }
local ghost = TTUser.find({ id = 3 })
mockResults[2] = {}
T.eq(ghost:refresh(), false, "refresh: returns false when row is gone")

-- all()
T.section("Model.all")

reset()
mockResults[1] = { { id = 1, name = "A" }, { id = 2, name = "B" } }
local allRows = TTUser.all()
T.eq(#allRows, 2, "all: returns every row")

T.finish()
