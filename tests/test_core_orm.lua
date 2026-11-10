-- tests/test_core_orm.lua
-- Tests for the ORM facade (core/orm.lua): setAdapter, fromTable, the
-- shared cache controls (enableCache, disableCache, cacheStats, flushCache),
-- Model.flushCache, and cache invalidation by raw SQL.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_core_orm.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = require("tests.support.json")

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

local T = require("tests.support.harness")

--- Adapter double: logs every statement and answers SELECT / DESCRIBE
--- statements from `rowsFor(sql)`, which defaults to one row per query.
local function fakeAdapter(name)
    local adapter = { name = name, log = {} }
    function adapter.rowsFor(_) return { { id = 1, name = "row" } } end
    function adapter:execute(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        return self.rowsFor(sql)
    end
    function adapter:scalar(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        return 1
    end
    function adapter:transaction() return true end
    function adapter:reset() self.log = {} end
    return adapter
end

local ORM = require("core.orm")

-- ─── ORM.setAdapter ─────────────────────────────────────────────────

T.section("ORM.setAdapter")

local first = fakeAdapter("first")
local second = fakeAdapter("second")

ORM.setAdapter(first)
local BuiltBefore = ORM.model("orm_before", { id = "number" })
ORM.setAdapter(second)
local BuiltAfter = ORM.model("orm_after", { id = "number" })

BuiltAfter.find({ id = 1 })
T.eq(#second.log, 1, "a model built after setAdapter queries the new adapter")
T.eq(#first.log, 0, "the previous adapter receives nothing from that model")

BuiltBefore.find({ id = 1 })
T.eq(#first.log, 1, "a model keeps the adapter it was built with")

second:reset()
ORM.raw("SELECT 1")
ORM.rawExec("UPDATE orm_after SET id = 2")
T.eq(#second.log, 2, "ORM.raw and ORM.rawExec use the adapter set last")

local explicit = fakeAdapter("explicit")
ORM.model("orm_explicit", { id = "number" }, { adapter = explicit }).find({ id = 1 })
T.eq(#explicit.log, 1, "opts.adapter still wins over the default adapter")

-- ─── ORM.fromTable ──────────────────────────────────────────────────

T.section("ORM.fromTable")

local describeRows = {
    orm_players = {
        { Field = "citizenid", Type = "varchar(50)",  Key = "PRI" },
        { Field = "money",     Type = "int(11)",      Key = "" },
        { Field = "is_admin",  Type = "tinyint(1)",   Key = "" },
        { Field = "position",  Type = "json",         Key = "" },
    },
    orm_vehicles = {
        { Field = "plate", Type = "varchar(8)", Key = "PRI" },
    },
}

local introspected = fakeAdapter("introspected")
function introspected.rowsFor(sql)
    local described = sql:match("^DESCRIBE `([%w_]+)`$")
    if described then return describeRows[described] or {} end
    return { { citizenid = "ABC", money = 5, is_admin = 1, position = '{"x":1.5,"y":[1,2]}' } }
end

local Player = ORM.fromTable("orm_players", { adapter = introspected })
T.eq(introspected.log[1].sql, "DESCRIBE `orm_players`", "fromTable describes the table through opts.adapter")
T.eq(Player._primaryKey, "citizenid", "fromTable uses the PRI column as primary key")

introspected:reset()
local player = Player.find({ citizenid = "ABC" })
T.eq(introspected.log[1].sql, "SELECT * FROM `orm_players` WHERE `citizenid` = ? LIMIT 1",
    "the introspected model builds queries for its table")
T.eq(player.money, 5, "number columns are read back")
T.eq(type(player.position), "table", "json columns are decoded")
T.eq(player.position.y[2], 2, "json arrays inside a column round-trip")

local Override = ORM.fromTable("orm_players", { adapter = introspected, primaryKey = "money" })
T.eq(Override._primaryKey, "money", "an explicit opts.primaryKey overrides the PRI column")

local sharedOpts = { adapter = introspected }
ORM.fromTable("orm_players", sharedOpts)
local Vehicle = ORM.fromTable("orm_vehicles", sharedOpts)
T.eq(Vehicle._primaryKey, "plate", "reusing one opts table does not leak the previous table's primary key")
T.eq(sharedOpts.primaryKey, nil, "fromTable leaves the caller's opts untouched")

T.raises(function() ORM.fromTable("orm_missing", { adapter = introspected }) end,
    "fromTable raises for a table that does not exist", "orm_missing")
T.raises(function() ORM.fromTable("bad name; DROP", { adapter = introspected }) end,
    "fromTable rejects an unsafe table name")

-- ─── Shared cache: enableCache / cacheStats / flushCache ────────────

T.section("Shared cache controls")

local cached = fakeAdapter("cached")
local Cached = ORM.model("orm_cached", { id = "number", name = "string" }, { adapter = cached })
local Other = ORM.model("orm_other", { id = "number" }, { adapter = cached })

ORM.flushCache()
local baseline = ORM.cacheStats()
Cached.find({ id = 1 })
Cached.find({ id = 1 })
T.eq(#cached.log, 2, "the shared cache is disabled by default")

ORM.enableCache({ ttl = 30 })
cached:reset()
Cached.find({ id = 1 })
Cached.find({ id = 1 })
T.eq(#cached.log, 1, "enableCache serves the second identical find from the cache")

local stats = ORM.cacheStats()
T.eq(stats.hits - baseline.hits, 1, "cacheStats counts the hit")
T.eq(stats.misses - baseline.misses, 1, "cacheStats counts the miss")
T.eq(stats.entries, 1, "cacheStats reports the stored entry")
T.check(stats.hitRate > 0 and stats.hitRate <= 1, "cacheStats reports a hit rate between 0 and 1")

ORM.flushCache()
T.eq(ORM.cacheStats().entries, 0, "flushCache empties the shared cache")
Cached.find({ id = 1 })
T.eq(#cached.log, 2, "a find after flushCache goes back to the database")

-- ─── TTL set through enableCache ────────────────────────────────────

T.section("enableCache ttl")

local realTime = os.time
local now = realTime()
os.time = function(t) if t then return realTime(t) end return now end

ORM.flushCache()
ORM.enableCache({ ttl = 5 })
cached:reset()
Cached.find({ id = 2 })
now = now + 4
Cached.find({ id = 2 })
T.eq(#cached.log, 1, "an entry younger than the ttl is served from the cache")
now = now + 2
Cached.find({ id = 2 })
T.eq(#cached.log, 2, "an entry older than the ttl is fetched again")

os.time = realTime

-- ─── Model.flushCache ───────────────────────────────────────────────

T.section("Model.flushCache")

ORM.flushCache()
cached:reset()
Cached.find({ id = 1 })
Other.find({ id = 1 })
Cached.flushCache()
Cached.find({ id = 1 })
Other.find({ id = 1 })
T.eq(#cached.log, 3, "Model.flushCache drops only that model's table")
T.eq(cached.log[3].sql:find("orm_cached", 1, true) ~= nil, true, "the flushed model queries again")

local Cache = require("utils.cache")
local ownCache = Cache.new({ ttl = 60, enabled = true })
local Private = ORM.model("orm_private", { id = "number" }, { adapter = cached, cache = ownCache })
cached:reset()
Private.find({ id = 1 })
ORM.flushCache()
Private.find({ id = 1 })
T.eq(#cached.log, 1, "ORM.flushCache does not touch a model's own opts.cache")
Private.flushCache()
Private.find({ id = 1 })
T.eq(#cached.log, 2, "Model.flushCache clears a model's own opts.cache")

-- ─── Raw SQL invalidation ───────────────────────────────────────────

T.section("Raw SQL invalidates the shared cache")

ORM.setAdapter(cached)
ORM.flushCache()
cached:reset()
Cached.find({ id = 1 })
Other.find({ id = 1 })
ORM.rawExec("UPDATE `orm_cached` SET name = ? WHERE id = ?", { "x", 1 })
Cached.find({ id = 1 })
Other.find({ id = 1 })
T.eq(#cached.log, 4, "a raw UPDATE drops the written table and keeps the others")

cached:reset()
ORM.raw("CALL refresh_everything()")
Cached.find({ id = 1 })
Other.find({ id = 1 })
T.eq(#cached.log, 3, "a raw statement whose table cannot be told flushes everything")

-- ─── disableCache ───────────────────────────────────────────────────

T.section("ORM.disableCache")

ORM.disableCache()
cached:reset()
Cached.find({ id = 1 })
Cached.find({ id = 1 })
T.eq(#cached.log, 2, "disableCache sends every find to the database again")

T.finish()
