-- tests/test_model_cache.lua
-- Query cache: basic operations, statistics and integration with models.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_model_cache.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults = Mock.log, Mock.results
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

-- ─── Test: Cache ───────────────────────────────────────────────────

T.section("Cache")

local CacheLib = require("utils.cache")

-- Basic cache operations
local cache = CacheLib.new({ ttl = 60, enabled = true })

cache:set("key1", { "data" })
local val, hit = cache:get("key1")
T.eq(hit, true, "cache hit on existing key")
T.eq(val[1], "data", "cache returns correct value")

local val2, hit2 = cache:get("nonexistent")
T.eq(hit2, false, "cache miss on unknown key")

-- Cache size
cache:set("key2", "other")
T.eq(cache:size(), 2, "cache size is 2")

-- Invalidate single key
cache:invalidate("key1")
local _, hit3 = cache:get("key1")
T.eq(hit3, false, "invalidate removes key")

-- Invalidate by table name
cache:set("SELECT * FROM users:1", "r1")
cache:set("SELECT * FROM users:2", "r2")
cache:set("SELECT * FROM vehicles:1", "r3")
cache:invalidateTable("users")
local _, hitU = cache:get("SELECT * FROM users:1")
local _, hitV = cache:get("SELECT * FROM vehicles:1")
T.eq(hitU, false, "invalidateTable removes matching keys")
T.eq(hitV, true, "invalidateTable keeps non-matching keys")

-- Flush
cache:flush()
T.eq(cache:size(), 0, "flush clears all entries")

-- Disabled cache
local disabledCache = CacheLib.new({ enabled = false })
disabledCache:set("key", "val")
local _, hitD = disabledCache:get("key")
T.eq(hitD, false, "disabled cache always misses")

-- Cache key generation
local cacheKey = CacheLib.makeKey("SELECT * FROM users WHERE id = ?", { 1 })
T.match(cacheKey, "SELECT %* FROM users WHERE id = %?:1", "makeKey generates correct key")

-- TTL expiration
local shortCache = CacheLib.new({ ttl = 0, enabled = true })
shortCache:set("expire", "data")
local _, hitE = shortCache:get("expire")
T.eq(hitE, false, "expired entry returns miss")

-- ─── Test: Cache integration with Model ────────────────────────────

T.section("Cache Integration")

reset()
ORM.enableCache({ ttl = 60 })

local CachedUser = ORM.model("cached_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

-- First find → cache miss → DB query
mockResults[1] = { { identifier = "license:abc", money = 500 } }
local p1 = CachedUser.find({ identifier = "license:abc" })
T.eq(p1.money, 500, "cache: first find returns DB data")
T.eq(#dbLog, 1, "cache: first find hits DB")

-- Second find → cache hit → no DB query
local p2 = CachedUser.find({ identifier = "license:abc" })
T.eq(p2.money, 500, "cache: second find returns cached data")
T.eq(#dbLog, 1, "cache: second find does NOT hit DB")

-- Write invalidates cache
CachedUser.update({ money = 1000 }, { identifier = "license:abc" })
mockResults[3] = { { identifier = "license:abc", money = 1000 } }
local p3 = CachedUser.find({ identifier = "license:abc" })
T.eq(#dbLog, 3, "cache: find after update hits DB again")

ORM.disableCache()

-- cache stats
T.section("Cache stats")

local statCache = CacheLib.new({ ttl = 60, enabled = true })
statCache:set("k", { 1 })
statCache:get("k")
statCache:get("missing")
local stats = statCache:stats()
T.eq(stats.hits, 1, "stats: hits counted")
T.eq(stats.misses, 1, "stats: misses counted")
T.eq(stats.entries, 1, "stats: entries counted")

-- cache does not get corrupted by wrapping (mutation bug fix)
T.section("Cache integrity")

reset()
local CIUser = ORM.model("ci_users", {
    id       = "number",
    position = "json",
}, { primaryKey = "id", cache = CacheLib.new({ ttl = 60, enabled = true }) })

mockResults[1] = { { id = 1, position = '{"x":1}' } }
local first = CIUser.find({ id = 1 })
T.eq(type(first.position), "table", "cache integrity: 1st read decodes json")
-- Second read comes from cache; must decode again from the raw cached row
local second = CIUser.find({ id = 1 })
T.eq(#dbLog, 1, "cache integrity: 2nd read served from cache")
T.eq(type(second.position), "table", "cache integrity: cached read decodes json")
T.eq(second.position.x, 1, "cache integrity: cached json value intact")
T.eq(second._tableName ~= nil, true, "cache integrity: cached read is a full instance")

T.finish()
