-- tests/test_orm_helpers.lua
-- ORM-level helpers: raw SQL, debug logger, seed, introspection, unpack.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_orm_helpers.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults = Mock.log, Mock.results
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

-- ─── Test: Raw SQL ────────────────────────────────────────────────

T.section("Raw SQL")

reset()
mockResults[1] = { { cnt = 42 } }
local rawResult = ORM.raw("SELECT COUNT(*) as cnt FROM users WHERE money > ?", { 1000 })
T.eq(rawResult[1].cnt, 42, "ORM.raw: returns correct result")
T.match(dbLog[1].sql, "SELECT COUNT", "ORM.raw: executes SQL")

reset()
ORM.rawExec("DELETE FROM logs WHERE age > ?", { 30 })
T.match(dbLog[1].sql, "DELETE FROM logs", "ORM.rawExec: executes SQL")

-- ─── Test: Debug / Logger ─────────────────────────────────────────

T.section("Debug / Logger")

local LoggerLib = require("utils.logger")
T.eq(LoggerLib._enabled, false, "logger: disabled by default")
ORM.debug(true)
T.eq(LoggerLib._enabled, true, "logger: ORM.debug(true) enables it")
ORM.debug(false)
T.eq(LoggerLib._enabled, false, "logger: ORM.debug(false) disables it")

-- ─── Test: Seed ───────────────────────────────────────────────────

T.section("Seed")

local seedRan = false
ORM.seed(function(orm)
    seedRan = true
end)
T.eq(seedRan, true, "ORM.seed: callback executed")

-- ─── Test: Introspection ─────────────────────────────────────────

T.section("Introspection")

reset()
mockResults[1] = {
    { Field = "id",        Type = "int(11)",       Null = "NO",  Key = "PRI", Default = nil,    Extra = "auto_increment" },
    { Field = "name",      Type = "varchar(255)",   Null = "YES", Key = "",    Default = nil,    Extra = "" },
    { Field = "money",     Type = "float",          Null = "YES", Key = "",    Default = "0",    Extra = "" },
    { Field = "is_active", Type = "tinyint(1)",     Null = "YES", Key = "",    Default = "1",    Extra = "" },
    { Field = "metadata",  Type = "json",           Null = "YES", Key = "",    Default = nil,    Extra = "" },
    { Field = "created_at",Type = "datetime",       Null = "YES", Key = "",    Default = nil,    Extra = "" },
}
local fields, pk = ORM.introspect("test_table")
T.eq(pk, "id", "introspect: primary key detected")
T.eq(fields.id, "number", "introspect: int → number")
T.eq(fields.name, "string", "introspect: varchar → string")
T.eq(fields.money, "number", "introspect: float → number")
T.eq(fields.is_active, "boolean", "introspect: tinyint(1) → boolean")
T.eq(fields.metadata, "json", "introspect: json → json")
T.eq(fields.created_at, "datetime", "introspect: datetime → datetime")
T.match(dbLog[1].sql, "DESCRIBE", "introspect: uses DESCRIBE query")

-- ─── Test: ORM.unpack() ─────────────────────────────────────────

T.section("ORM.unpack")

local model, raw, migrate, transaction = ORM.unpack()
T.eq(type(model), "function", "unpack: model is a function")
T.eq(type(raw), "function", "unpack: raw is a function")
T.eq(type(migrate), "function", "unpack: migrate is a function")
T.eq(type(transaction), "function", "unpack: transaction is a function")

T.finish()
