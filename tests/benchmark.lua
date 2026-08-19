-- tests/benchmark.lua
-- Performance benchmark for OrvexORM
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.3 lua tests/benchmark.lua

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

local _noop_result = {}
promise = {
    new = function()
        local p = { _value = nil }
        function p:resolve(v) self._value = v end
        return p
    end,
}
Citizen = { Await = function(p) return p._value end }
local function _mock_query(query, params, cb)
    cb(_noop_result)
end

MySQL = {
    prepare = _mock_query,
    query = _mock_query,
    insert = _mock_query,
    update = _mock_query,
    transaction = function(queries, cb)
        cb(true)
    end,
}

-- ─── Load ORM ──────────────────────────────────────────────────────

local ORM = require("core.orm")

-- ─── Benchmark helper ──────────────────────────────────────────────

local clock = os.clock

local function bench(name, iterations, fn)
    -- Warmup
    for i = 1, 100 do fn() end

    local start = clock()
    for i = 1, iterations do
        fn()
    end
    local elapsed = clock() - start
    local perOp = (elapsed / iterations) * 1000 -- ms

    local status = perOp < 0.01 and "OK" or (perOp < 0.05 and "WARN" or "SLOW")
    print(("  [%s] %-45s %8.4f ms/op  (%d ops in %.3fs)"):format(
        status, name, perOp, iterations, elapsed
    ))
    return perOp
end

-- ─── Setup models ──────────────────────────────────────────────────

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

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

-- Mock find results
local mockRow = { identifier = "license:abc", money = 500, job = "police" }
local mockJsonRow = {
    identifier = "license:abc", money = 500,
    position = '{"x":100,"y":200}', inventory = '{"items":"test"}',
}

-- ─── Benchmarks ────────────────────────────────────────────────────

print("\n========================================")
print("  OrvexORM Performance Benchmark")
print("========================================\n")

local N = 10000

print("-- SQL Generation (no DB) --")

bench("Query.insert (3 fields)", N, function()
    local Query = require("core.query")
    Query.insert("users", { identifier = "license:abc", money = 500, job = "police" })
end)

bench("Query.select (1 where)", N, function()
    local Query = require("core.query")
    Query.select("users", { identifier = "license:abc" })
end)

bench("Query.update (2 set, 1 where)", N, function()
    local Query = require("core.query")
    Query.update("users", { money = 1000, job = "medic" }, { identifier = "license:abc" })
end)

bench("Query.delete (1 where)", N, function()
    local Query = require("core.query")
    Query.delete("users", { identifier = "license:abc" })
end)

bench("Query.upsert (3 fields)", N, function()
    local Query = require("core.query")
    Query.upsert("users", { identifier = "license:abc", money = 500, job = "police" })
end)

print("\n-- Builder chain --")

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
        :where({ identifier = { "LIKE", "%abc%" } })
        :leftJoin("profiles", "profiles.user_id", "users.identifier")
        :orderBy("money", "DESC")
        :limit(10)
        :toSQL()
end)

bench("Scope: User.rich() chain", N, function()
    User.rich():limit(10):toSQL()
end)

print("\n-- Model CRUD (with mock DB) --")

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

_noop_result = { mockRow }
bench("Model.find (1 where)", N, function()
    User.find({ identifier = "license:abc" })
end)

_noop_result = { mockJsonRow }
bench("Model.find with JSON decode", N, function()
    PlayerJSON.find({ identifier = "license:abc" })
end)

_noop_result = {}
for i = 1, 10 do
    _noop_result[i] = { identifier = "license:" .. i, money = i * 100, job = "police" }
end
bench("Model.findAll (10 rows)", N, function()
    User.findAll({ job = "police" })
end)

_noop_result = { mockRow }
bench("Model.update (class, 1 field)", N, function()
    User.update({ money = 1000 }, { identifier = "license:abc" })
end)

bench("Model.delete (1 where)", N, function()
    User.delete({ identifier = "license:abc" })
end)

bench("Model.upsert (3 fields)", N, function()
    User.upsert({ identifier = "license:abc", money = 500, job = "police" })
end)

print("\n-- Instance operations --")

_noop_result = { mockRow }
local inst = User.find({ identifier = "license:abc" })
_noop_result = {}

bench("instance:update (1 field)", N, function()
    inst:update({ money = 999 })
end)

bench("instance:increment", N, function()
    inst:increment("money", 100)
end)

bench("instance:decrement", N, function()
    inst:decrement("money", 50)
end)

print("\n-- Validator --")

bench("Validator.validate (3 fields, valid)", N * 5, function()
    local Validator = require("utils.validator")
    Validator.validate(
        { identifier = "license:abc", money = 500, job = "police" },
        { identifier = "string", money = "number", job = "string" }
    )
end)

print("\n-- Cache --")

local CacheLib = require("utils.cache")
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

print("\n-- Transaction --")

bench("Transaction callback (2 ops)", N, function()
    ORM.transaction(function(tx)
        tx:insert("users", { identifier = "license:tx", money = 100 })
        tx:update("users", { money = 200 }, { identifier = "license:tx" })
    end)
end)

print("\n========================================")
print("  Target: < 0.01 ms/op for all ops")
print("========================================\n")
