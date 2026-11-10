-- tests/test_security_hardening.lua
-- Regression tests for the hardening items: fail-closed field types, bulk
-- inserts with different key sets, paginate overflow, chunk limits,
-- whereColumn operators, identifier segments, json decoding and
-- belongsToMany definitions.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_security_hardening.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults, txLog = Mock.log, Mock.results, Mock.txLog
local reset = Mock.reset

local ORM = require("core.orm")
local Query = require("core.query")
local Helpers = require("utils.helpers")
local Validator = require("utils.validator")
local Serializer = require("utils.serializer")

-- ─── Field types ───────────────────────────────────────────────────

T.section("Unknown field types fail closed")

T.raises(function() ORM.model("typos", { id = "number", level = "int" }) end,
    "an unknown type name raises at definition", "unknown type 'int'")
T.raises(function() ORM.model("typos", { id = "number", level = { type = "string" } }) end,
    "a table-form column definition raises", "unknown type")
T.check(pcall(ORM.model, "every_type", {
    a = "string", b = "number", c = "boolean", d = "json",
    e = "auto", f = "date", g = "datetime", h = "timestamp",
}), "every documented type is accepted")

local ok, err = Validator.checkType("level", 3, "int")
T.eq(ok, false, "checkType rejects an unknown type")
T.match(err, "unknown type", "checkType names the problem")
T.check(Validator.checkType("meta", { 1 }, "auto"), "checkType keeps 'auto' as any type")

-- ─── Bulk inserts ──────────────────────────────────────────────────

T.section("createMany groups rows by key set")

local Item = ORM.model("items", { id = "number", name = "string", qty = "number" })

reset()
Item.createMany({ { name = "a", qty = 1 }, { name = "b" }, { name = "c", qty = 3 } })
T.eq(#txLog, 1, "rows with different key sets are inserted in one transaction")
local batch = txLog[1] or {}
T.eq(#batch, 2, "one INSERT per key set")
T.eq((batch[1] or {}).query, "INSERT INTO `items` (`name`, `qty`) VALUES (?, ?), (?, ?)", "first key set keeps every column")
T.eq((batch[2] or {}).query, "INSERT INTO `items` (`name`) VALUES (?)", "second key set")
local values = (batch[1] or {}).values or {}
T.eq(values[3], "c", "rows of a key set stay together")
T.eq(#values, 4, "no nil holes in the bound values")

reset()
Item.createMany({ { name = "a", qty = 1 }, { name = "b", qty = 2 } })
T.eq(#txLog, 0, "a single key set needs no transaction")
T.eq(#dbLog, 1, "a single key set is one INSERT")

T.raises(function() Query.insertMany("items", { { name = "a", qty = 1 }, { name = "b" } }) end,
    "Query.insertMany refuses rows with different key sets", "key set")

-- ─── Paging and scans ──────────────────────────────────────────────

T.section("paginate and chunk bounds")

reset()
T.raises(function() Item.query():paginate(math.maxinteger, 1000) end,
    "paginate refuses an offset that overflows", "too large")
T.eq(#dbLog, 0, "the overflow is caught before any query")

reset()
mockResults[1] = { { id = 1 }, { id = 2 } }
mockResults[2] = { { id = 3 }, { id = 4 } }
mockResults[3] = { { id = 5 } }
local seen = 0
Item.query():limit(5):chunk(2, function(rows) seen = seen + #rows end)
T.eq(seen, 5, "chunk stops at the builder's limit")
T.eq(#dbLog, 3, "chunk runs no query past the limit")
T.match((dbLog[3] or {}).sql, "LIMIT 1 OFFSET 4$", "the last chunk is trimmed to the limit")

reset()
mockResults[1] = { { id = 1 }, { id = 2 } }
mockResults[2] = { { id = 3 } }
seen = 0
Item.query():limit(3):chunkById(2, function(rows) seen = seen + #rows end)
T.eq(seen, 3, "chunkById stops at the builder's limit")
T.eq(#dbLog, 2, "chunkById runs no query past the limit")
T.match((dbLog[2] or {}).sql, "LIMIT 1$", "the last keyset page is trimmed to the limit")

T.raises(function() Item.query():offset(10):chunkById(2, function() end) end,
    "chunkById refuses an offset", "offset")

-- ─── whereColumn ───────────────────────────────────────────────────

T.section("whereColumn operators")

T.raises(function() Item.query():whereColumn("qty", "IN", "id") end, "whereColumn refuses IN", "comparison")
T.raises(function() Item.query():whereColumn("qty", "BETWEEN", "id") end, "whereColumn refuses BETWEEN", "comparison")
T.raises(function() Item.query():whereColumn("qty", "IS", "id") end, "whereColumn refuses IS", "comparison")
local sql = Item.query():whereColumn("qty", ">=", "id"):toSQL()
T.match(sql, "`qty` >= `id`", "whereColumn keeps comparison operators")

-- ─── Identifiers ───────────────────────────────────────────────────

T.section("Identifier segments")

for _, name in ipairs({ "a..b", ".", ".a", "a.", "" }) do
    T.raises(function() Helpers.assertSafeIdentifier(name) end,
        ("'%s' is rejected"):format(name), "Invalid SQL identifier")
end
T.check(pcall(Helpers.assertSafeIdentifier, "users.id"), "table.column is accepted")
T.check(pcall(Helpers.assertSafeIdentifier, "db.users.id"), "db.table.column is accepted")

-- ─── JSON decoding ─────────────────────────────────────────────────

T.section("Malformed json columns")

local warnings = {}
local originalWarn = OrvexLogger.warn
OrvexLogger.warn = function(message, context) warnings[#warnings + 1] = { message = message, context = context } end
local decoded
T.check(pcall(function() decoded = Serializer.decode("{broken", "json", "meta") end), "a malformed json value does not raise")
T.eq(decoded, "{broken", "the raw string is returned")
T.eq(#warnings, 1, "a warning is logged")
T.eq(((warnings[1] or {}).context or {}).field, "meta", "the warning names the field")
OrvexLogger.warn = originalWarn

local Doc = ORM.model("docs", { id = "number", meta = "json" })
reset()
mockResults[1] = { { id = 1, meta = "{broken" } }
OrvexLogger.warn = function() end
local doc = Doc.find({ id = 1 })
OrvexLogger.warn = originalWarn
T.eq(doc and doc.meta, "{broken", "reading a row with a malformed json column still works")

-- ─── belongsToMany ─────────────────────────────────────────────────

T.section("belongsToMany definition")

local Role = ORM.model("roles", { id = "number", name = "string" })
T.raises(function() Item.belongsToMany("roles", Role, { pivot = "item_roles", otherKey = "role_id" }) end,
    "belongsToMany requires a foreignKey", "foreignKey")
T.raises(function() Item.belongsToMany("roles", Role, { pivot = "item_roles", foreignKey = "item_id" }) end,
    "belongsToMany requires an otherKey", "otherKey")
T.raises(function() Item.belongsToMany("roles", Role, { pivot = "item_roles", foreignKey = "x;y", otherKey = "role_id" }) end,
    "belongsToMany keys must be safe identifiers", "Invalid SQL identifier")

T.finish()
