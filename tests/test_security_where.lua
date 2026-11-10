-- tests/test_security_where.lua
-- Regression tests for the where-value hardening: operator conditions only
-- through ORM.op markers, scalar-only bound values (where, IN, cursors,
-- pivot keys, relation keys, instance identity) and the identity of
-- instances read through joins.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_security_where.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults = Mock.log, Mock.results
local reset = Mock.reset

local ORM = require("core.orm")
local Builder = require("core.builder")

-- ─── Fixtures ──────────────────────────────────────────────────────

local Account = ORM.model("accounts", {
    identifier = "string", pin = "string", money = "number",
}, { primaryKey = "identifier" })

local Trashable = ORM.model("trashables", {
    id = "number", name = "string",
}, { softDelete = true })

local User = ORM.model("users", {
    id = "number", identifier = "string", money = "number",
})

local Post = ORM.model("posts", {
    id = "number", user_id = "number", title = "string",
})

local Role = ORM.model("roles", { id = "number", name = "string" })

User.hasMany("posts", Post, { foreignKey = "user_id" })
User.belongsToMany("roles", Role, { pivot = "user_roles", foreignKey = "user_id", otherKey = "role_id" })
Post.belongsTo("author", User, { foreignKey = "user_id" })

local FORGED = { "LIKE", "%" }

--- Runs `fn`, expects an error containing `fragment`, and checks that no
--- statement reached the driver.
local function rejects(fn, message, fragment)
    reset()
    T.raises(fn, message, fragment)
    T.eq(#dbLog, 0, message .. " (no driver call)")
end

-- ─── ORM.op markers ────────────────────────────────────────────────

T.section("ORM.op markers")

T.eq(type(ORM.op), "function", "ORM.op is exposed")
T.eq(Builder.op, ORM.op, "Builder.op is the same constructor")
T.raises(function() ORM.op("DROP", 1) end, "ORM.op rejects an unknown operator", "Invalid SQL operator")
T.raises(function() ORM.op(">", nil) end, "ORM.op rejects a nil value", "nil")
T.match(tostring(ORM.op(">", 5)), "ORM%.op", "an ORM.op marker prints readably")

local sql, params = Account.query():where({ money = ORM.op(">", 100) }):toSQL()
T.match(sql, "WHERE `money` > %?", "table-form where honours an ORM.op marker")
T.eq(params[1], 100, "the marker value is bound")

sql, params = Account.query():where({ money = ORM.op("IN", { 1, 2, 3 }) }):toSQL()
T.match(sql, "`money` IN %(%?, %?, %?%)", "ORM.op IN marker")
T.eq(#params, 3, "IN marker binds every element")

sql = Account.query():where("money", ORM.op(">=", 7)):toSQL()
T.match(sql, "`money` >= %?", "where(field, ORM.op(...)) uses the marker operator")

reset()
Account.findAll({ money = ORM.op(">", 1000), pin = "1234" })
T.match(dbLog[1].sql, "`money` > %?", "findAll accepts ORM.op markers")

-- ─── Plain tables are not operators ────────────────────────────────

T.section("Plain table where values are rejected")

local entries = {
    { "find", function() Account.find({ identifier = "a", pin = FORGED }) end },
    { "findAll", function() Account.findAll({ pin = FORGED }) end },
    { "findOrFail", function() Account.findOrFail({ pin = FORGED }) end },
    { "findOrCreate", function() Account.findOrCreate({ pin = FORGED }) end },
    { "updateOrCreate", function() Account.updateOrCreate({ pin = FORGED }, { money = 1 }) end },
    { "count", function() Account.count({ pin = FORGED }) end },
    { "first", function() Account.first({ pin = FORGED }) end },
    { "exists", function() Account.exists({ identifier = "a", pin = FORGED }) end },
    { "pluck", function() Account.pluck("money", { pin = FORGED }) end },
    { "sum", function() Account.sum("money", { pin = FORGED }) end },
    { "avg", function() Account.avg("money", { pin = FORGED }) end },
    { "min", function() Account.min("money", { pin = FORGED }) end },
    { "max", function() Account.max("money", { pin = FORGED }) end },
    { "countByRelation", function() User.countByRelation("posts", { identifier = FORGED }) end },
    { "Builder:where", function() Account.query():where({ pin = FORGED }):get() end },
    { "Builder:orWhere", function() Account.query():orWhere({ pin = FORGED }):get() end },
}
for _, entry in ipairs(entries) do
    rejects(entry[2], entry[1] .. "() rejects { op, value } tuples", "ORM.op")
end

rejects(function() Account.find({ identifier = { identifier = 1 } }) end,
    "find() rejects a map-shaped table value", "ORM.op")
rejects(function() Account.findOrCreate({ pin = ORM.op("!=", "") }) end,
    "findOrCreate() refuses ORM.op markers (the where is also the created row)", "findOrCreate")
rejects(function() Account.updateOrCreate({ pin = ORM.op("!=", "") }, { money = 1 }) end,
    "updateOrCreate() refuses ORM.op markers", "updateOrCreate")

-- ─── Non-scalar binds ──────────────────────────────────────────────

T.section("Non-scalar bound values are rejected")

local MAP = { identifier = 1 }
local function fn() end

rejects(function() Account.update({ money = 0 }, { identifier = MAP }) end, "class update", "string, number or boolean")
rejects(function() Account.updateWhere({ identifier = MAP }, { money = 0 }) end, "updateWhere", "string, number or boolean")
rejects(function() Account.delete({ identifier = MAP }) end, "class delete", "string, number or boolean")
rejects(function() Account.deleteWhere({ identifier = fn }) end, "deleteWhere with a function", "string, number or boolean")
rejects(function() Trashable.delete({ id = MAP }) end, "soft delete", "string, number or boolean")
rejects(function() Trashable.forceDelete({ id = MAP }) end, "forceDelete", "string, number or boolean")
rejects(function() Trashable.restore({ id = MAP }) end, "restore", "string, number or boolean")
rejects(function() Account.increment("money", 1, { identifier = MAP }) end, "class increment", "string, number or boolean")
rejects(function() Account.decrement("money", 1, { identifier = MAP }) end, "class decrement", "string, number or boolean")
rejects(function() Account.update({ money = 0 }, { identifier = ORM.op("!=", "") }) end,
    "class update refuses ORM.op markers (equality only)", "equality")

rejects(function() Account.find({ identifier = fn }) end, "find fast path rejects a function", "string, number or boolean")
rejects(function() Account.find({ money = 0 / 0 }) end, "find rejects NaN", "finite")
rejects(function() Account.find({ money = math.huge }) end, "find rejects infinity", "finite")

rejects(function() ORM.transaction(function(tx) tx:update("accounts", { money = 0 }, { identifier = MAP }) end) end,
    "Transaction:update", "string, number or boolean")
rejects(function() ORM.transaction(function(tx) tx:delete("accounts", { identifier = MAP }) end) end,
    "Transaction:delete", "string, number or boolean")

rejects(function() Account.query():where("identifier", MAP):get() end, "where(field, table)", "ORM.op")
rejects(function() Account.query():where("identifier", "=", MAP):get() end, "where(field, op, table)", "string, number or boolean")
rejects(function() Account.query():whereIn("money", { 1, MAP }):get() end, "whereIn element", "string, number or boolean")
rejects(function() Account.query():whereIn("money", { 1, nil, 3 }):get() end, "whereIn with a nil hole", "hole")
rejects(function() Account.query():whereNotIn("money", { fn }):get() end, "whereNotIn element", "string, number or boolean")
rejects(function() Account.query():whereBetween("money", MAP, 5):get() end, "whereBetween bound", "string, number or boolean")
rejects(function() Account.query():where({ money = ORM.op("BETWEEN", { 1, MAP }) }):get() end,
    "BETWEEN element", "string, number or boolean")
rejects(function() Account.query():whereLike("pin", MAP):get() end, "whereLike pattern", "string, number or boolean")
rejects(function() Account.query():after("money", MAP):get() end, "after cursor", "string, number or boolean")
rejects(function() Account.query():before("money", fn):get() end, "before cursor", "string, number or boolean")

rejects(function() Account.increment("money", "5", { identifier = "a" }) end, "class increment amount must be a number", "amount")
rejects(function() Account.decrement("money", 0 / 0, { identifier = "a" }) end, "class decrement rejects NaN", "amount")

reset()
mockResults[1] = { { identifier = "a", money = 5 } }
local acc = Account.find({ identifier = "a" })
rejects(function() acc:increment("money", math.huge) end, "instance increment rejects infinity", "amount")
rejects(function() acc:decrement("money", MAP) end, "instance decrement rejects a table", "amount")

-- ─── Pivot and relation keys ───────────────────────────────────────

T.section("Pivot and relation keys")

reset()
mockResults[1] = { { id = 1, identifier = "u1", money = 0 } }
local user = User.find({ id = 1 })

rejects(function() user:attach("roles", { id = MAP }) end, "attach rejects a table related key", "string, number or boolean")
rejects(function() user:detach("roles", { id = MAP }) end, "detach rejects a table related key", "string, number or boolean")

local forged = User._wrapRow({ id = MAP })
rejects(function() forged:detach("roles", { id = 1 }) end, "detach rejects a table parent key", "string, number or boolean")

local mutated = User._wrapRow({ id = 1 })
mutated.id = ORM.op("!=", 0)
rejects(function() mutated:get("posts") end, "hasMany fetch refuses a marker key", "string, number or boolean")
rejects(function() mutated:get("roles") end, "belongsToMany fetch refuses a marker key", "string, number or boolean")
local post = Post._wrapRow({ id = 1, user_id = MAP })
rejects(function() post:get("author") end, "belongsTo fetch refuses a table key", "string, number or boolean")

-- ─── Instance identity ─────────────────────────────────────────────

T.section("Instance identity")

local badIdentity = User._wrapRow({ id = MAP, money = 1 })
rejects(function() badIdentity:update({ money = 2 }) end, "instance update refuses a table identity", "string, number or boolean")
rejects(function() badIdentity:delete() end, "instance delete refuses a table identity", "string, number or boolean")

local noIdentity = User._wrapRow({ money = 1 })
rejects(function() noIdentity:update({ money = 2 }) end, "instance update refuses a missing identity", "'id'")
rejects(function() noIdentity:delete() end, "instance delete refuses a missing identity", "'id'")
rejects(function() noIdentity:increment("money") end, "instance increment refuses a missing identity", "'id'")

-- ─── Joined rows ───────────────────────────────────────────────────

T.section("Joined model queries select the model's own columns")

sql = User.query():innerJoin("vehicles", "vehicles.owner", "users.identifier"):toSQL()
T.match(sql, "^SELECT `users`%.%* FROM `users` INNER JOIN", "joined default select becomes `users`.*")

sql = User.query():leftJoin("vehicles", "vehicles.owner", "users.identifier")
    :select("users.id, vehicles.plate"):toSQL()
T.match(sql, "^SELECT `users`%.`id`, `vehicles`%.`plate` FROM", "an explicit select is untouched")

sql = User.query():toSQL()
T.match(sql, "^SELECT %* FROM `users`", "no join keeps SELECT *")

reset()
mockResults[1] = { { id = 2, money = 500 } }
local joined = User.query():innerJoin("vehicles", "vehicles.owner", "users.identifier"):first()
T.match(dbLog[1].sql, "^SELECT `users`%.%*", "first() over a join emits `users`.*")
T.eq(joined.id, 2, "the instance is built from the main table's row")

T.finish()
