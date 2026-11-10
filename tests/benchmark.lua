-- tests/benchmark.lua
-- Performance benchmark for OrvexORM
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/benchmark.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = {
    encode = function(t)
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            local val
            if type(v) == "string" then val = '"' .. v .. '"'
            elseif type(v) == "table" then val = json.encode(v)
            else val = tostring(v) end
            parts[#parts + 1] = '"' .. k .. '":' .. val
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    decode = function(s)
        if type(s) ~= "string" then return s end
        if s:sub(1, 1) == "{" then
            local t = {}
            for k, v in s:gmatch('"([^"]+)":([^,}]+)') do
                if v:sub(1, 1) == '"' then t[k] = v:sub(2, -2)
                elseif v == "true" then t[k] = true
                elseif v == "false" then t[k] = false
                else t[k] = tonumber(v) or v end
            end
            return t
        end
        return s
    end,
}

promise = {
    new = function()
        local p = { _value = nil }
        function p:resolve(v) self._value = v end
        return p
    end,
}
Citizen = { Await = function(p) return p._value end }

-- ─── Mock database ─────────────────────────────────────────────────
-- Every query returns fresh copies of the configured rows, like a real
-- driver would: wrapRow decodes and decorates rows in place, so sharing
-- one table between calls would skip that work after the first call.

local MockDB = { rows = {}, queries = 0 }

local function copyRow(row)
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    return copy
end

function MockDB.returns(rows)
    MockDB.rows = rows
end

function MockDB.freshResult()
    local result = {}
    for i, row in ipairs(MockDB.rows) do result[i] = copyRow(row) end
    return result
end

local function mockQuery(_, _, cb)
    MockDB.queries = MockDB.queries + 1
    cb(MockDB.freshResult())
end

MySQL = {
    prepare = mockQuery,
    query = mockQuery,
    insert = mockQuery,
    update = mockQuery,
    transaction = function(_, cb)
        MockDB.queries = MockDB.queries + 1
        cb(true)
    end,
}

-- ─── Load ORM ──────────────────────────────────────────────────────

local ORM       = require("core.orm")
local Query     = require("core.query")
local Validator = require("utils.validator")
local CacheLib  = require("utils.cache")

-- ─── Benchmark helper ──────────────────────────────────────────────

local clock = os.clock
local DEFAULT_TARGET_MS = 0.01
local WARMUP_ITERATIONS = 100

local function statusFor(perOp, target)
    if perOp < target then return "OK" end
    if perOp < target * 5 then return "WARN" end
    return "SLOW"
end

--- Runs `fn` `iterations` times and prints ms/op and DB round trips per op.
---@param target? number ms/op under which the scenario is considered OK
local function bench(name, iterations, fn, target)
    for _ = 1, WARMUP_ITERATIONS do fn() end

    local queriesBefore = MockDB.queries
    local start = clock()
    for _ = 1, iterations do fn() end
    local elapsed = clock() - start
    local perOp = (elapsed / iterations) * 1000
    local queriesPerOp = (MockDB.queries - queriesBefore) / iterations

    print(("  [%-4s] %-52s %9.4f ms/op  %5.1f queries/op  (%d ops in %.3fs)"):format(
        statusFor(perOp, target or DEFAULT_TARGET_MS), name, perOp, queriesPerOp, iterations, elapsed
    ))
    return perOp
end

local function section(title)
    print("\n-- " .. title .. " --")
end

-- ─── Fixtures ──────────────────────────────────────────────────────

local mockRow = { identifier = "license:abc", money = 500, job = "police" }
local mockJsonRow = {
    identifier = "license:abc", money = 500,
    position = '{"x":100,"y":200}', inventory = '{"items":"test"}',
}

local function rowsOf(count, build)
    local rows = {}
    for i = 1, count do rows[i] = build(i) end
    return rows
end

local function policeRow(i)
    return { identifier = "license:" .. i, money = i * 100, job = "police" }
end

-- Shape shared by owners and their items so one mock result serves both queries.
local function ownerItemRow(i)
    return { id = i, owner_id = i, name = "item" .. i }
end

-- Fills a cache with `count` entries depending on tables other than the model's.
local function populateCache(cache, count)
    for i = 1, count do
        local tableName = "other_" .. (i % 50)
        local key = CacheLib.makeKey("SELECT * FROM `" .. tableName .. "` WHERE id = ?", { i })
        cache:set(key, { { id = i } }, nil, tableName)
    end
end

local function newCache(entries)
    local cache = CacheLib.new({ ttl = 60, enabled = true, maxEntries = entries * 2 })
    populateCache(cache, entries)
    return cache
end

-- ─── Models ────────────────────────────────────────────────────────

local userFields = { identifier = "string", money = "number", job = "string" }

local User = ORM.model("users", userFields, { primaryKey = "identifier" })

local PlayerJSON = ORM.model("players_json", {
    identifier = "string",
    money      = "number",
    position   = "json",
    inventory  = "json",
}, { primaryKey = "identifier" })

local TSUser = ORM.model("ts_users_bench", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier", timestamps = true })

User.scope("rich", function(b) b:where("money", ">", 10000) end)
User.scope("cops", function(b) b:where({ job = "police" }) end)

local CACHED_ENTRIES = 10000
local CachedUser = ORM.model("cached_users", userFields, {
    primaryKey = "identifier",
    cache = newCache(CACHED_ENTRIES),
})

local Item = ORM.model("items", { id = "number", owner_id = "number", name = "string" })
local Owner = ORM.model("owners", { id = "number", owner_id = "number", name = "string" })
Owner.hasMany("items", Item, { foreignKey = "owner_id" })

-- ─── Sanity check ──────────────────────────────────────────────────
-- Guards the benchmark itself: if rows were shared between queries,
-- JSON fields would be decoded once and the decode scenario would lie.

local function assertRowsAreFreshPerQuery()
    MockDB.returns({ mockJsonRow })
    local realDecode, decodes = json.decode, 0
    json.decode = function(v) decodes = decodes + 1; return realDecode(v) end
    for _ = 1, 10 do PlayerJSON.find({ identifier = "license:abc" }) end
    json.decode = realDecode
    assert(decodes >= 20, ("mock rows are shared between queries: %d JSON decodes for 10 finds of 2 JSON fields")
        :format(decodes))
end

assertRowsAreFreshPerQuery()

-- ─── Benchmarks ────────────────────────────────────────────────────

print("\n========================================")
print("  OrvexORM Performance Benchmark")
print("========================================")

local N = 10000

section("SQL Generation (no DB)")

bench("Query.insert (3 fields)", N, function()
    Query.insert("users", { identifier = "license:abc", money = 500, job = "police" })
end)

bench("Query.select (1 where)", N, function()
    Query.select("users", { identifier = "license:abc" })
end)

bench("Query.update (2 set, 1 where)", N, function()
    Query.update("users", { money = 1000, job = "medic" }, { identifier = "license:abc" })
end)

bench("Query.delete (1 where)", N, function()
    Query.delete("users", { identifier = "license:abc" })
end)

bench("Query.upsert (3 fields)", N, function()
    Query.upsert("users", { identifier = "license:abc", money = 500, job = "police" })
end)

section("Builder chain")

bench("Builder: where + orderBy + limit", N, function()
    User.query():where({ job = "police" }):where("money", ">", 1000):orderBy("money", "DESC"):limit(10):toSQL()
end)

bench("Builder: where 2-arg shortcut", N, function()
    User.query():where("job", "police"):where("money", ">", 500):toSQL()
end)

bench("Builder: complex (3 where + join + order + limit)", N, function()
    User.query()
        :where({ job = "police" })
        :where("money", ">", 1000)
        :where({ identifier = ORM.op("LIKE", "%abc%") })
        :leftJoin("profiles", "profiles.user_id", "users.identifier")
        :orderBy("money", "DESC")
        :limit(10)
        :toSQL()
end)

bench("Scope: User.rich() chain", N, function()
    User.rich():limit(10):toSQL()
end)

section("Model CRUD (mock DB, cache disabled)")

MockDB.returns({})

bench("Model.create (3 fields)", N, function()
    User.create({ identifier = "license:bench", money = 500, job = "police" })
end)

bench("Model.create with timestamps", N, function()
    TSUser.create({ identifier = "license:tsbench", money = 500 })
end)

bench("Model.create with JSON fields", N, function()
    PlayerJSON.create({
        identifier = "license:json",
        money = 500,
        position = { x = 100, y = 200 },
        inventory = { sword = 1 },
    })
end)

MockDB.returns({ mockRow })
bench("Model.find (1 where)", N, function()
    User.find({ identifier = "license:abc" })
end)

MockDB.returns({ mockJsonRow })
bench("Model.find with JSON decode (2 fields)", N, function()
    PlayerJSON.find({ identifier = "license:abc" })
end)

MockDB.returns(rowsOf(10, policeRow))
bench("Model.findAll (10 rows)", N, function()
    User.findAll({ job = "police" })
end)

MockDB.returns(rowsOf(1000, policeRow))
bench("Model.findAll (1000 rows)", N / 100, function()
    User.findAll({ job = "police" })
end, 2)

MockDB.returns(rowsOf(1000, ownerItemRow))
bench("Model.findAll (1000 rows + hasMany eager load)", N / 100, function()
    Owner.findAll({ name = "owner" }, { include = { "items" } })
end, 4)

MockDB.returns({ mockRow })
bench("Model.update (class, 1 field)", N, function()
    User.update({ money = 1000 }, { identifier = "license:abc" })
end)

bench("Model.delete (1 where)", N, function()
    User.delete({ identifier = "license:abc" })
end)

bench("Model.upsert (3 fields)", N, function()
    User.upsert({ identifier = "license:abc", money = 500, job = "police" })
end)

section(("Model with cache enabled (%d entries on other tables)"):format(CACHED_ENTRIES))

MockDB.returns({ mockRow })
CachedUser.find({ identifier = "license:hit" })
bench("Model.find (cache hit)", N, function()
    CachedUser.find({ identifier = "license:hit" })
end)

local missCounter = 0
bench("Model.find (cache miss, then stored)", N, function()
    missCounter = missCounter + 1
    CachedUser.find({ identifier = "license:miss" .. missCounter })
end)

MockDB.returns({})
bench("Model.create (pays invalidateTable)", N, function()
    CachedUser.create({ identifier = "license:cached", money = 500, job = "police" })
end)

bench("Model.update (pays invalidateTable)", N, function()
    CachedUser.update({ money = 1000 }, { identifier = "license:cached" })
end)

section("Instance operations")

MockDB.returns({ mockRow })
local inst = User.find({ identifier = "license:abc" })
MockDB.returns({})

bench("instance:update (1 field)", N, function()
    inst:update({ money = 999 })
end)

bench("instance:increment", N, function()
    inst:increment("money", 100)
end)

bench("instance:decrement", N, function()
    inst:decrement("money", 50)
end)

section("Validator")

bench("Validator.validate (3 fields, valid)", N * 5, function()
    Validator.validate(
        { identifier = "license:abc", money = 500, job = "police" },
        userFields
    )
end)

section("Cache")

local testCache = CacheLib.new({ ttl = 60, enabled = true })

bench("Cache.makeKey (1 param)", N * 5, function()
    CacheLib.makeKey("SELECT * FROM users WHERE id = ?", { 1 })
end)

bench("Cache.makeKey (3 params)", N * 5, function()
    CacheLib.makeKey("SELECT * FROM users WHERE a = ? AND b = ? AND c = ?", { 1, "test", 42 })
end)

testCache:set("bench_key", { { id = 1 } })
bench("Cache:get (hit)", N * 5, function()
    testCache:get("bench_key")
end)

bench("Cache:get (miss)", N * 5, function()
    testCache:get("nonexistent_key")
end)

local bigCache = newCache(CACHED_ENTRIES)
bench(("Cache:invalidateTable (%d entries, other tables)"):format(CACHED_ENTRIES), N, function()
    bigCache:invalidateTable("users")
end)

section("Transaction")

bench("Transaction callback (2 ops)", N, function()
    ORM.transaction(function(tx)
        tx:insert("users", { identifier = "license:tx", money = 100 })
        tx:update("users", { money = 200 }, { identifier = "license:tx" })
    end)
end)

print("\n========================================")
print(("  Target: < %.2f ms/op unless stated otherwise"):format(DEFAULT_TARGET_MS))
print("  queries/op = DB round trips, the real cost under oxmysql")
print("========================================\n")
