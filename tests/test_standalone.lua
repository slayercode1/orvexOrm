-- tests/test_standalone.lua
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.3 lua tests/test_standalone.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = {
    encode = function(t)
        -- Simple JSON encoder for testing
        if type(t) ~= "table" then return tostring(t) end
        local isArray = #t > 0
        if isArray then
            local parts = {}
            for _, v in ipairs(t) do
                if type(v) == "string" then
                    parts[#parts + 1] = '"' .. v .. '"'
                elseif type(v) == "table" then
                    parts[#parts + 1] = json.encode(v)
                else
                    parts[#parts + 1] = tostring(v)
                end
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
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
        end
    end,
    decode = function(s)
        -- Minimal JSON decoder for testing: handles our own output
        if s:sub(1, 1) == "{" then
            local t = {}
            for k, v in s:gmatch('"([^"]+)":([^,}]+)') do
                if v:sub(1, 1) == '"' then
                    t[k] = v:sub(2, -2)
                elseif v == "true" then t[k] = true
                elseif v == "false" then t[k] = false
                else t[k] = tonumber(v) or v end
            end
            return t
        elseif s:sub(1, 1) == "[" then
            return { s } -- simplified
        end
        return s
    end,
}

local _db_log = {}
local _mock_results = {}
local _tx_log = {}

promise = {
    new = function()
        local p = { _value = nil }
        function p:resolve(v) self._value = v end
        return p
    end,
}

Citizen = { Await = function(p) return p._value end }

MySQL = {
    prepare = function(query, params, cb)
        _db_log[#_db_log + 1] = { sql = query, params = params }
        local result = _mock_results[#_db_log]
        if result then
            cb(result)
        else
            if query:match("^INSERT") then cb(1)
            elseif query:match("^SELECT") then cb({})
            else cb(1) end
        end
    end,
    transaction = function(queries, cb)
        _tx_log[#_tx_log + 1] = queries
        cb(true)
    end,
}

-- ─── Test helpers ──────────────────────────────────────────────────

local passed, failed = 0, 0

local function assert_eq(got, expected, msg)
    if got == expected then
        passed = passed + 1
        print(("  ✓ %s"):format(msg))
    else
        failed = failed + 1
        print(("  ✗ %s — expected: %s, got: %s"):format(msg, tostring(expected), tostring(got)))
    end
end

local function assert_match(str, pattern, msg)
    if str:match(pattern) then
        passed = passed + 1
        print(("  ✓ %s"):format(msg))
    else
        failed = failed + 1
        print(("  ✗ %s — '%s' doesn't match '%s'"):format(msg, str, pattern))
    end
end

local function reset()
    _db_log = {}
    _mock_results = {}
    _tx_log = {}
end

-- ─── Test: Query Builder ───────────────────────────────────────────

print("\n== Query Builder ==")

local Query = require("core.query")

local q = Query.insert("users", { identifier = "license:abc", money = 500 })
assert_match(q.sql, "INSERT INTO `users`", "INSERT SQL generated")
assert_eq(#q.params, 2, "INSERT has 2 params")

q = Query.select("users", { identifier = "license:abc" })
assert_match(q.sql, "SELECT %* FROM `users` WHERE", "SELECT SQL generated")

q = Query.update("users", { money = 1000 }, { identifier = "license:abc" })
assert_match(q.sql, "UPDATE `users` SET", "UPDATE SQL generated")

q = Query.delete("users", { identifier = "license:abc" })
assert_match(q.sql, "DELETE FROM `users` WHERE", "DELETE SQL generated")

q = Query.upsert("users", { identifier = "license:abc", money = 500 })
assert_match(q.sql, "ON DUPLICATE KEY UPDATE", "UPSERT SQL generated")

q = Query.selectJoin("roles", "user_roles", "role_id", "id", "user_id", 1)
assert_match(q.sql, "INNER JOIN user_roles", "selectJoin has INNER JOIN")

-- ─── Test: Validator ───────────────────────────────────────────────

print("\n== Validator ==")

local Validator = require("utils.validator")

local ok, err = Validator.validate(
    { identifier = "license:abc", money = 500 },
    { identifier = "string", money = "number" }
)
assert_eq(ok, true, "valid data passes")

ok, err = Validator.validate({ identifier = 123 }, { identifier = "string" })
assert_eq(ok, false, "wrong type fails")

-- ─── Test: ORM CRUD ────────────────────────────────────────────────

print("\n== ORM CRUD ==")

reset()
local ORM = require("core.orm")

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

local player = User.create({ identifier = "license:abc", money = 500, job = "unemployed" })
assert_eq(player.identifier, "license:abc", "create returns instance")
assert_match(_db_log[1].sql, "INSERT INTO `users`", "create runs INSERT")

reset()
_mock_results[1] = { { identifier = "license:abc", money = 500, job = "unemployed" } }
local found = User.find({ identifier = "license:abc" })
assert_eq(found.money, 500, "find returns correct data")

reset()
found:update({ money = 1000 })
assert_eq(found.money, 1000, "instance update changes local object")
assert_match(_db_log[1].sql, "UPDATE `users` SET", "instance update runs UPDATE")

reset()
User.update({ money = 9999 }, { identifier = "license:abc" })
assert_match(_db_log[1].sql, "UPDATE `users` SET", "class update runs UPDATE")

reset()
found:delete()
assert_match(_db_log[1].sql, "DELETE FROM `users`", "delete runs DELETE")

reset()
User.upsert({ identifier = "license:abc", money = 2000 })
assert_match(_db_log[1].sql, "ON DUPLICATE KEY UPDATE", "upsert runs UPSERT")

-- ─── Test: Relations ───────────────────────────────────────────────

print("\n== Relations ==")

reset()
local Profile = ORM.model("profiles", {
    id = "number", user_id = "string", bio = "string",
}, { primaryKey = "id" })

local Vehicle = ORM.model("vehicles", {
    id = "number", owner_id = "string", plate = "string",
}, { primaryKey = "id" })

local Role = ORM.model("roles", {
    id = "number", name = "string",
}, { primaryKey = "id" })

User.hasOne("profile", Profile, { foreignKey = "user_id" })
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
User.belongsToMany("roles", Role, {
    pivot = "user_roles", foreignKey = "user_id", otherKey = "role_id",
})

-- hasOne
reset()
_mock_results[1] = { { identifier = "license:abc", money = 500, job = "police" } }
_mock_results[2] = { { id = 1, user_id = "license:abc", bio = "Hello" } }
local u = User.find({ identifier = "license:abc" })
local profile = u:get("profile")
assert_eq(profile.bio, "Hello", "hasOne returns correct data")

-- hasMany
reset()
_mock_results[1] = { { identifier = "license:abc", money = 500, job = "police" } }
_mock_results[2] = {
    { id = 1, owner_id = "license:abc", plate = "ABC123" },
    { id = 2, owner_id = "license:abc", plate = "XYZ789" },
}
u = User.find({ identifier = "license:abc" })
local vehicles = u:get("vehicles")
assert_eq(#vehicles, 2, "hasMany returns multiple instances")

-- belongsTo
reset()
_mock_results[1] = { { id = 1, owner_id = "license:abc", plate = "ABC123" } }
_mock_results[2] = { { identifier = "license:abc", money = 500, job = "police" } }
local car = Vehicle.find({ plate = "ABC123" })
local owner = car:get("owner")
assert_eq(owner.identifier, "license:abc", "belongsTo returns correct owner")

-- belongsToMany
reset()
_mock_results[1] = { { identifier = "license:abc", money = 500, job = "police" } }
_mock_results[2] = { { id = 1, name = "admin" }, { id = 2, name = "mod" } }
u = User.find({ identifier = "license:abc" })
local roles = u:get("roles")
assert_eq(#roles, 2, "belongsToMany returns multiple")
assert_match(_db_log[2].sql, "INNER JOIN user_roles", "belongsToMany uses JOIN")

-- attach / detach
reset()
_mock_results[1] = { { identifier = "license:abc", money = 500, job = "police" } }
u = User.find({ identifier = "license:abc" })
reset()
u:attach("roles", { id = 5, name = "vip" })
assert_match(_db_log[1].sql, "INSERT INTO `user_roles`", "attach inserts pivot")
reset()
u:detach("roles", { id = 5, name = "vip" })
assert_match(_db_log[1].sql, "DELETE FROM `user_roles`", "detach deletes pivot")

-- ─── Test: Chainable Query Builder ─────────────────────────────────

print("\n== Chainable Query Builder ==")

local BuilderLib = require("core.builder")

local b = BuilderLib.new("users", nil, nil)
local sql, params = b
    :where({ job = "police" })
    :where("money", ">", 100)
    :orderBy("money", "DESC")
    :limit(10)
    :offset(5)
    :toSQL()

assert_match(sql, "SELECT %* FROM users", "builder base SELECT")
assert_match(sql, "WHERE job = %?", "builder WHERE equality")
assert_match(sql, "AND money > %?", "builder WHERE operator")
assert_match(sql, "ORDER BY money DESC", "builder ORDER BY")
assert_match(sql, "LIMIT 10", "builder LIMIT")
assert_match(sql, "OFFSET 5", "builder OFFSET")

b = BuilderLib.new("users", nil, nil)
sql = b:leftJoin("profiles", "profiles.user_id", "users.identifier"):where({ job = "police" }):toSQL()
assert_match(sql, "LEFT JOIN profiles", "builder LEFT JOIN")

b = BuilderLib.new("users", nil, nil)
sql = b:innerJoin("departments", "departments.id", "users.dept_id"):toSQL()
assert_match(sql, "INNER JOIN departments", "builder INNER JOIN")

b = BuilderLib.new("users", nil, nil)
sql = b:rightJoin("logs", "logs.user_id", "users.id"):toSQL()
assert_match(sql, "RIGHT JOIN logs", "builder RIGHT JOIN")

b = BuilderLib.new("users", nil, nil)
sql = b:select("job, COUNT(*) as cnt"):groupBy("job"):toSQL()
assert_match(sql, "GROUP BY job", "builder GROUP BY")

b = BuilderLib.new("users", nil, nil)
sql, params = b:select("job, COUNT(*) as cnt"):groupBy("job"):having("COUNT(*) > ?", 5):toSQL()
assert_match(sql, "HAVING COUNT", "builder HAVING clause")
assert_eq(params[1], 5, "builder HAVING param correct")

b = BuilderLib.new("users", nil, nil)
sql, params = b:where({ id = { "IN", { 1, 2, 3 } } }):toSQL()
assert_match(sql, "id IN %(%?, %?, %?%)", "builder WHERE IN")

b = BuilderLib.new("users", nil, nil)
sql, params = b:where({ money = { "BETWEEN", { 100, 1000 } } }):toSQL()
assert_match(sql, "money BETWEEN %? AND %?", "builder WHERE BETWEEN")

b = BuilderLib.new("users", nil, nil)
sql = b:where({ name = { "LIKE", "%john%" } }):toSQL()
assert_match(sql, "name LIKE %?", "builder WHERE LIKE")

b = BuilderLib.new("users", nil, nil)
sql, params = b:where({ deleted_at = { "IS", "NULL" } }):toSQL()
assert_match(sql, "deleted_at IS NULL", "builder WHERE IS NULL")
assert_eq(#params, 0, "builder IS NULL has no params")

b = BuilderLib.new("users", nil, nil)
sql = b:where({ status = { "!=", "banned" } }):toSQL()
assert_match(sql, "status != %?", "builder WHERE !=")

b = BuilderLib.new("users", nil, nil)
sql, params = b:where({ job = "police" }):orWhere({ job = "medic" }):toSQL()
assert_match(sql, "OR job = %?", "builder OR WHERE")

-- ─── Test: Builder Terminal Methods ────────────────────────────────

print("\n== Builder Terminal Methods ==")

reset()
_mock_results[1] = { { cnt = 42 } }
local cnt = User.count({ job = "police" })
assert_eq(cnt, 42, "Model.count returns correct value")
assert_match(_db_log[1].sql, "SELECT COUNT", "count generates COUNT SQL")

reset()
_mock_results[1] = { { val = 15000 } }
local total = User.sum("money", { job = "police" })
assert_eq(total, 15000, "Model.sum returns correct value")

reset()
_mock_results[1] = { { val = 750 } }
local average = User.avg("money", { job = "police" })
assert_eq(average, 750, "Model.avg returns correct value")

reset()
_mock_results[1] = { { val = 100 } }
local minimum = User.min("money", { job = "police" })
assert_eq(minimum, 100, "Model.min returns correct value")

reset()
_mock_results[1] = { { val = 9999 } }
local maximum = User.max("money", { job = "police" })
assert_eq(maximum, 9999, "Model.max returns correct value")

reset()
_mock_results[1] = {
    { identifier = "license:a", money = 900, job = "police" },
    { identifier = "license:b", money = 800, job = "police" },
}
local results = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :orderBy("money", "DESC")
    :limit(2)
    :get()
assert_eq(#results, 2, "query chain returns correct count")
assert_match(_db_log[1].sql, "ORDER BY money DESC", "query chain has ORDER BY")

reset()
_mock_results[1] = { { identifier = "license:a", money = 900, job = "police" } }
local first = User.query():where({ job = "police" }):first()
assert_eq(first.identifier, "license:a", "query first returns single instance")
assert_match(_db_log[1].sql, "LIMIT 1", "first adds LIMIT 1")

-- ─── Test: Transactions ────────────────────────────────────────────

print("\n== Transactions ==")

reset()
local Transaction = require("core.transaction")
local Adapter     = require("database.adapter")
local MySQLDriver = require("database.mysql")

local testAdapter = Adapter.new(MySQLDriver.new())

-- Transaction via module
local tx = Transaction.new(testAdapter)
tx:insert("users", { identifier = "license:tx1", money = 500 })
tx:update("users", { money = 1000 }, { identifier = "license:tx1" })
tx:delete("vehicles", { owner = "license:tx1" })

local queries = tx:getQueries()
assert_eq(#queries, 3, "transaction has 3 queries")
assert_match(queries[1].query, "INSERT INTO `users`", "tx query 1 is INSERT")
assert_match(queries[2].query, "UPDATE `users` SET", "tx query 2 is UPDATE")
assert_match(queries[3].query, "DELETE FROM `vehicles`", "tx query 3 is DELETE")

-- Commit
reset()
local success = tx:commit()
assert_eq(success, true, "transaction commit returns true")
assert_eq(#_tx_log, 1, "transaction sent to MySQL.transaction")
assert_eq(#_tx_log[1], 3, "transaction has 3 queries in batch")

-- Transaction via ORM.transaction()
reset()
local tx2 = ORM.transaction()
tx2:insert("users", { identifier = "license:tx2", money = 100 })
tx2:upsert("users", { identifier = "license:tx2", money = 200 })
local success2 = tx2:commit()
assert_eq(success2, true, "ORM.transaction commit works")
assert_eq(#_tx_log[1], 2, "ORM.transaction has 2 queries")

-- Empty transaction
reset()
local tx3 = ORM.transaction()
assert_eq(tx3:commit(), true, "empty transaction returns true")

-- Transaction with addRaw
reset()
local tx4 = ORM.transaction()
tx4:addRaw("ALTER TABLE users ADD COLUMN test INT", {})
tx4:insert("users", { identifier = "license:raw", money = 0 })
assert_eq(#tx4:getQueries(), 2, "addRaw + insert = 2 queries")

-- ─── Test: Cache ───────────────────────────────────────────────────

print("\n== Cache ==")

local CacheLib = require("utils.cache")

-- Basic cache operations
local cache = CacheLib.new({ ttl = 60, enabled = true })

cache:set("key1", { "data" })
local val, hit = cache:get("key1")
assert_eq(hit, true, "cache hit on existing key")
assert_eq(val[1], "data", "cache returns correct value")

local val2, hit2 = cache:get("nonexistent")
assert_eq(hit2, false, "cache miss on unknown key")

-- Cache size
cache:set("key2", "other")
assert_eq(cache:size(), 2, "cache size is 2")

-- Invalidate single key
cache:invalidate("key1")
local _, hit3 = cache:get("key1")
assert_eq(hit3, false, "invalidate removes key")

-- Invalidate by table name
cache:set("SELECT * FROM users:1", "r1")
cache:set("SELECT * FROM users:2", "r2")
cache:set("SELECT * FROM vehicles:1", "r3")
cache:invalidateTable("users")
local _, hitU = cache:get("SELECT * FROM users:1")
local _, hitV = cache:get("SELECT * FROM vehicles:1")
assert_eq(hitU, false, "invalidateTable removes matching keys")
assert_eq(hitV, true, "invalidateTable keeps non-matching keys")

-- Flush
cache:flush()
assert_eq(cache:size(), 0, "flush clears all entries")

-- Disabled cache
local disabledCache = CacheLib.new({ enabled = false })
disabledCache:set("key", "val")
local _, hitD = disabledCache:get("key")
assert_eq(hitD, false, "disabled cache always misses")

-- Cache key generation
local cacheKey = CacheLib.makeKey("SELECT * FROM users WHERE id = ?", { 1 })
assert_match(cacheKey, "SELECT %* FROM users WHERE id = %?:1", "makeKey generates correct key")

-- TTL expiration
local shortCache = CacheLib.new({ ttl = 0, enabled = true })
shortCache:set("expire", "data")
local _, hitE = shortCache:get("expire")
assert_eq(hitE, false, "expired entry returns miss")

-- ─── Test: Cache integration with Model ────────────────────────────

print("\n== Cache Integration ==")

reset()
ORM.enableCache({ ttl = 60 })

local CachedUser = ORM.model("cached_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

-- First find → cache miss → DB query
_mock_results[1] = { { identifier = "license:abc", money = 500 } }
local p1 = CachedUser.find({ identifier = "license:abc" })
assert_eq(p1.money, 500, "cache: first find returns DB data")
assert_eq(#_db_log, 1, "cache: first find hits DB")

-- Second find → cache hit → no DB query
local p2 = CachedUser.find({ identifier = "license:abc" })
assert_eq(p2.money, 500, "cache: second find returns cached data")
assert_eq(#_db_log, 1, "cache: second find does NOT hit DB")

-- Write invalidates cache
CachedUser.update({ money = 1000 }, { identifier = "license:abc" })
_mock_results[3] = { { identifier = "license:abc", money = 1000 } }
local p3 = CachedUser.find({ identifier = "license:abc" })
assert_eq(#_db_log, 3, "cache: find after update hits DB again")

ORM.disableCache()

-- ─── Test: Automatic JSON columns ──────────────────────────────────

print("\n== Automatic JSON Columns ==")

local Serializer = require("utils.serializer")

-- Explicit json type
local encoded = Serializer.encode({ x = 1, y = 2 }, "json")
assert_eq(type(encoded), "string", "json encode: table → string")
local decoded = Serializer.decode(encoded, "json")
assert_eq(type(decoded), "table", "json decode: string → table")
assert_eq(decoded.x, 1, "json decode: correct value")

-- Auto type: table → JSON
local autoEncoded = Serializer.encode({ a = 1 }, "auto")
assert_eq(type(autoEncoded), "string", "auto encode: table → string")

-- Auto type: JSON string → table
local autoDecoded = Serializer.decode('{"a":1,"b":2}', "auto")
assert_eq(type(autoDecoded), "table", "auto decode: JSON string → table")
assert_eq(autoDecoded.a, 1, "auto decode: correct value a")
assert_eq(autoDecoded.b, 2, "auto decode: correct value b")

-- Auto type: non-JSON string stays string
local plainDecoded = Serializer.decode("hello world", "auto")
assert_eq(type(plainDecoded), "string", "auto decode: plain string stays string")
assert_eq(plainDecoded, "hello world", "auto decode: plain string unchanged")

-- Auto type: number stays number
local numDecoded = Serializer.decode(42, "auto")
assert_eq(numDecoded, 42, "auto decode: number stays number")

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
assert_eq(type(_db_log[1].params[2]), "string", "auto: table encoded to string on INSERT")

-- Find with auto JSON decode
reset()
_mock_results[1] = { {
    identifier = "license:json",
    position = '{"x":100,"y":200}',
    inventory = '[{"item":"bread","count":5}]',
} }
local pp2 = Player.find({ identifier = "license:json" })
assert_eq(type(pp2.position), "table", "auto: JSON string decoded to table on SELECT")
assert_eq(pp2.position.x, 100, "auto: decoded JSON has correct values")

-- ─── Test: Migrations ─────────────────────────────────────────────

print("\n== Migrations ==")

local MigrationLib = require("core.migration")

-- Test type mapping
assert_eq(MigrationLib.TYPE_MAP["string"], "VARCHAR(255)", "type map: string → VARCHAR(255)")
assert_eq(MigrationLib.TYPE_MAP["number"], "INT", "type map: number → INT")
assert_eq(MigrationLib.TYPE_MAP["boolean"], "TINYINT(1)", "type map: boolean → TINYINT(1)")
assert_eq(MigrationLib.TYPE_MAP["json"], "JSON", "type map: json → JSON")
assert_eq(MigrationLib.TYPE_MAP["auto"], "TEXT", "type map: auto → TEXT")

-- Test columnToSQL
local colSQL = MigrationLib.columnToSQL("name", "string", false)
assert_match(colSQL, "`name` VARCHAR%(255%)", "columnToSQL: string column")
assert_match(colSQL, "NULL", "columnToSQL: nullable by default")

local pkSQL = MigrationLib.columnToSQL("id", "number", true)
assert_match(pkSQL, "`id` INT", "columnToSQL: number PK")
assert_match(pkSQL, "NOT NULL", "columnToSQL: PK is NOT NULL")
assert_match(pkSQL, "AUTO_INCREMENT", "columnToSQL: number PK has AUTO_INCREMENT")

-- Test extended column definition
local extSQL = MigrationLib.columnToSQL("identifier", { type = "string", length = 60 }, true)
assert_match(extSQL, "VARCHAR%(60%)", "columnToSQL: extended with custom length")
assert_match(extSQL, "NOT NULL", "columnToSQL: extended PK is NOT NULL")

-- Test generateCreateSQL
local createSQL = MigrationLib.generateCreateSQL("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, "identifier")
assert_match(createSQL, "CREATE TABLE IF NOT EXISTS `users`", "generateCreateSQL: has CREATE TABLE")
assert_match(createSQL, "PRIMARY KEY %(`identifier`%)", "generateCreateSQL: has PRIMARY KEY")
assert_match(createSQL, "`money` INT", "generateCreateSQL: number column")
assert_match(createSQL, "`job` VARCHAR%(255%)", "generateCreateSQL: string column")

-- Test SchemaBuilder - create table
local sb = MigrationLib.SchemaBuilder.new()
sb:create("players", function(t)
    t:id()
    t:string("name", 100)
    t:integer("money")
    t:boolean("vip")
    t:json("position")
    t:timestamp("created_at")
end)
local stmts = sb:toSQL()
assert_eq(#stmts, 1, "SchemaBuilder create: 1 statement")
assert_match(stmts[1], "CREATE TABLE IF NOT EXISTS `players`", "SchemaBuilder create: CREATE TABLE")
assert_match(stmts[1], "`id` INT UNSIGNED NOT NULL AUTO_INCREMENT", "SchemaBuilder create: id column")
assert_match(stmts[1], "`name` VARCHAR%(100%)", "SchemaBuilder create: string with length")
assert_match(stmts[1], "PRIMARY KEY %(`id`%)", "SchemaBuilder create: PRIMARY KEY")

-- Test SchemaBuilder - drop table
local sb2 = MigrationLib.SchemaBuilder.new()
sb2:drop("old_table")
local stmts2 = sb2:toSQL()
assert_eq(#stmts2, 1, "SchemaBuilder drop: 1 statement")
assert_match(stmts2[1], "DROP TABLE `old_table`", "SchemaBuilder drop: DROP TABLE")

-- Test SchemaBuilder - dropIfExists
local sb3 = MigrationLib.SchemaBuilder.new()
sb3:dropIfExists("maybe_table")
local stmts3 = sb3:toSQL()
assert_match(stmts3[1], "DROP TABLE IF EXISTS `maybe_table`", "SchemaBuilder dropIfExists")

-- Test SchemaBuilder - alter table
local sb4 = MigrationLib.SchemaBuilder.new()
sb4:table("users", function(t)
    t:string("email", 255)
    t:dropColumn("old_col")
    t:renameColumn("name", "full_name")
end)
local stmts4 = sb4:toSQL()
assert_eq(#stmts4, 3, "SchemaBuilder alter: 3 statements (add + drop + rename)")
assert_match(stmts4[1], "ALTER TABLE `users` ADD COLUMN", "SchemaBuilder alter: ADD COLUMN")
assert_match(stmts4[2], "DROP COLUMN `old_col`", "SchemaBuilder alter: DROP COLUMN")
assert_match(stmts4[3], "RENAME COLUMN `name` TO `full_name`", "SchemaBuilder alter: RENAME COLUMN")

-- Test Model.sync()
reset()
local SyncUser = ORM.model("sync_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })
SyncUser.sync()
assert_eq(#_db_log, 1, "Model.sync: executes 1 SQL query")
assert_match(_db_log[1].sql, "CREATE TABLE IF NOT EXISTS `sync_users`", "Model.sync: runs CREATE TABLE")

-- Test ORM.migrate() and ORM.rollback()
reset()
_mock_results[1] = {} -- ensureTrackingTable (CREATE TABLE)
_mock_results[2] = {} -- getApplied (SELECT migrations) → empty
_mock_results[3] = { { batch = 0 } } -- getCurrentBatch

ORM.migrations({
    {
        name = "001_create_items",
        up = function(schema)
            schema:create("items", function(t)
                t:id()
                t:string("name")
                t:integer("quantity")
            end)
        end,
        down = function(schema)
            schema:drop("items")
        end,
    },
})

local migCount = ORM.migrate()
-- Should have run: ensureTrackingTable, getApplied, getCurrentBatch, CREATE TABLE, INSERT migration record
assert_eq(migCount, 1, "ORM.migrate: ran 1 migration")
-- Find the CREATE TABLE statement in logs
local foundCreate = false
for _, entry in ipairs(_db_log) do
    if entry.sql:match("CREATE TABLE IF NOT EXISTS `items`") then
        foundCreate = true
        break
    end
end
assert_eq(foundCreate, true, "ORM.migrate: executed CREATE TABLE for items")

-- Find the INSERT into tracking table
local foundInsert = false
for _, entry in ipairs(_db_log) do
    if entry.sql:match("INSERT INTO orvex_migrations") then
        foundInsert = true
        break
    end
end
assert_eq(foundInsert, true, "ORM.migrate: recorded migration in tracking table")

-- Test TableBuilder column types
local tb = MigrationLib.TableBuilder.new()
tb:float("price")
tb:double("coordinates")
tb:text("description")
tb:bigInteger("big_num")
tb:datetime("event_date")
tb:primaryString("code", 30)

assert_eq(#tb._columns, 6, "TableBuilder: all 6 columns created")
assert_match(tb._columns[1].sql, "FLOAT", "TableBuilder: float column")
assert_match(tb._columns[2].sql, "DOUBLE", "TableBuilder: double column")
assert_match(tb._columns[3].sql, "TEXT", "TableBuilder: text column")
assert_match(tb._columns[4].sql, "BIGINT", "TableBuilder: bigInteger column")
assert_match(tb._columns[5].sql, "DATETIME", "TableBuilder: datetime column")
assert_match(tb._columns[6].sql, "VARCHAR%(30%)", "TableBuilder: primaryString with length")
assert_eq(tb._columns[6].primary, true, "TableBuilder: primaryString is primary")

-- Test TableBuilder new column types
local tb2 = MigrationLib.TableBuilder.new()
tb2:enum("status", {"active", "banned", "suspended"})
tb2:softDeletes()
tb2:timestamps()
tb2:unique("email")
tb2:index({"job", "money"})
tb2:foreignKey("owner_id", "users", "identifier", { onDelete = "SET NULL" })

assert_match(tb2._columns[1].sql, "ENUM", "TableBuilder: enum column")
assert_match(tb2._columns[1].sql, "'active'", "TableBuilder: enum values")
assert_match(tb2._columns[2].sql, "deleted_at", "TableBuilder: softDeletes")
assert_match(tb2._columns[3].sql, "created_at", "TableBuilder: timestamps created_at")
assert_match(tb2._columns[4].sql, "updated_at", "TableBuilder: timestamps updated_at")
assert_eq(#tb2._indexes, 2, "TableBuilder: 2 indexes")
assert_eq(tb2._indexes[1].unique, true, "TableBuilder: unique index")
assert_eq(tb2._indexes[2].unique, false, "TableBuilder: non-unique index")
assert_eq(#tb2._foreignKeys, 1, "TableBuilder: 1 foreign key")
assert_eq(tb2._foreignKeys[1].refTable, "users", "TableBuilder: FK references users")

-- Test SchemaBuilder with indexes and foreign keys
local sb5 = MigrationLib.SchemaBuilder.new()
sb5:create("orders", function(t)
    t:id()
    t:string("user_id", 60)
    t:integer("total")
    t:unique("user_id")
    t:index("total")
    t:foreignKey("user_id", "users", "identifier")
end)
local stmts5 = sb5:toSQL()
assert_match(stmts5[1], "UNIQUE KEY", "SchemaBuilder: UNIQUE KEY in CREATE TABLE")
assert_match(stmts5[1], "FOREIGN KEY", "SchemaBuilder: FOREIGN KEY in CREATE TABLE")
assert_match(stmts5[1], "REFERENCES `users`", "SchemaBuilder: FK REFERENCES")

-- Wrap remaining tests in a function to avoid Lua 200 local variable limit
local function runExtendedTests()

-- ─── Test: Soft Delete ────────────────────────────────────────────

print("\n== Soft Delete ==")

reset()
local SoftUser = ORM.model("soft_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier", softDelete = true })

-- Create works normally
local su = SoftUser.create({ identifier = "license:soft1", money = 100 })
assert_eq(su.identifier, "license:soft1", "soft delete: create works")

-- Delete sets deleted_at instead of DELETE FROM
reset()
_mock_results[1] = { { identifier = "license:soft1", money = 100, deleted_at = nil } }
local su2 = SoftUser.find({ identifier = "license:soft1" })
reset()
su2:delete()
assert_match(_db_log[1].sql, "UPDATE `soft_users` SET", "soft delete: delete uses UPDATE")
assert_match(_db_log[1].sql, "deleted_at", "soft delete: delete sets deleted_at")

-- forceDelete uses real DELETE
reset()
su2:forceDelete()
assert_match(_db_log[1].sql, "DELETE FROM `soft_users`", "soft delete: forceDelete uses DELETE")

-- Class-level delete also uses UPDATE
reset()
SoftUser.delete({ identifier = "license:soft1" })
assert_match(_db_log[1].sql, "UPDATE `soft_users` SET", "soft delete: class delete uses UPDATE")

-- Class-level forceDelete uses real DELETE
reset()
SoftUser.forceDelete({ identifier = "license:soft1" })
assert_match(_db_log[1].sql, "DELETE FROM `soft_users`", "soft delete: class forceDelete uses DELETE")

-- query() auto-adds IS NULL filter
local b_soft = SoftUser.query()
local sql_soft = b_soft:toSQL()
assert_match(sql_soft, "deleted_at IS NULL", "soft delete: query auto-filters")

-- withTrashed() does not filter
local b_trashed = SoftUser.withTrashed()
local sql_trashed = b_trashed:toSQL()
-- Should NOT have deleted_at filter
local has_filter = sql_trashed:match("deleted_at")
assert_eq(has_filter, nil, "soft delete: withTrashed has no filter")

-- onlyTrashed() filters for deleted
local b_only = SoftUser.onlyTrashed()
local sql_only = b_only:toSQL()
assert_match(sql_only, "deleted_at IS NOT NULL", "soft delete: onlyTrashed filters deleted")

-- ─── Test: Hooks ──────────────────────────────────────────────────

print("\n== Hooks ==")

reset()
local hookLog = {}
local HookUser = ORM.model("hook_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

HookUser.beforeCreate(function(data)
    hookLog[#hookLog + 1] = "beforeCreate"
end)
HookUser.afterCreate(function(instance)
    hookLog[#hookLog + 1] = "afterCreate:" .. instance.identifier
end)

local hu = HookUser.create({ identifier = "license:hook1", money = 100 })
assert_eq(hookLog[1], "beforeCreate", "hooks: beforeCreate fired")
assert_eq(hookLog[2], "afterCreate:license:hook1", "hooks: afterCreate fired with instance")

-- Test update hooks
HookUser.beforeUpdate(function(instance, data)
    hookLog[#hookLog + 1] = "beforeUpdate"
end)
HookUser.afterUpdate(function(instance)
    hookLog[#hookLog + 1] = "afterUpdate"
end)

reset()
hu:update({ money = 200 })
assert_eq(hookLog[3], "beforeUpdate", "hooks: beforeUpdate fired")
assert_eq(hookLog[4], "afterUpdate", "hooks: afterUpdate fired")

-- Test delete hooks
HookUser.beforeDelete(function(instance)
    hookLog[#hookLog + 1] = "beforeDelete"
end)
HookUser.afterDelete(function(instance)
    hookLog[#hookLog + 1] = "afterDelete"
end)

reset()
hu:delete()
assert_eq(hookLog[5], "beforeDelete", "hooks: beforeDelete fired")
assert_eq(hookLog[6], "afterDelete", "hooks: afterDelete fired")

-- ─── Test: Scopes ──────────────────────────────────────────────────

print("\n== Scopes ==")

local ScopeUser = ORM.model("scope_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

ScopeUser.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

ScopeUser.scope("cops", function(b)
    b:where({ job = "police" })
end)

local scopeSQL = ScopeUser.scoped("rich"):toSQL()
assert_match(scopeSQL, "money > %?", "scopes: rich scope applies WHERE")

local scopeSQL2 = ScopeUser.scoped("cops"):toSQL()
assert_match(scopeSQL2, "job = %?", "scopes: cops scope applies WHERE")

-- ─── Test: findOrCreate / updateOrCreate ──────────────────────────

print("\n== findOrCreate / updateOrCreate ==")

reset()
-- findOrCreate: not found → creates
_mock_results[1] = {} -- find returns empty
local foc, created = ScopeUser.findOrCreate(
    { identifier = "license:new" },
    { money = 500, job = "unemployed" }
)
assert_eq(created, true, "findOrCreate: returns created=true when new")
assert_eq(foc.identifier, "license:new", "findOrCreate: instance has correct id")

-- findOrCreate: found → returns existing
reset()
_mock_results[1] = { { identifier = "license:existing", money = 999, job = "police" } }
local foc2, created2 = ScopeUser.findOrCreate(
    { identifier = "license:existing" },
    { money = 0, job = "none" }
)
assert_eq(created2, false, "findOrCreate: returns created=false when found")
assert_eq(foc2.money, 999, "findOrCreate: returns existing data")

-- updateOrCreate: not found → creates
reset()
_mock_results[1] = {} -- find returns empty
local uoc, uCreated = ScopeUser.updateOrCreate(
    { identifier = "license:uoc" },
    { money = 300, job = "medic" }
)
assert_eq(uCreated, true, "updateOrCreate: returns created=true when new")
assert_eq(uoc.job, "medic", "updateOrCreate: has correct data")

-- updateOrCreate: found → updates
reset()
_mock_results[1] = { { identifier = "license:uoc2", money = 100, job = "unemployed" } }
local uoc2, uCreated2 = ScopeUser.updateOrCreate(
    { identifier = "license:uoc2" },
    { money = 5000, job = "ceo" }
)
assert_eq(uCreated2, false, "updateOrCreate: returns created=false when found")
assert_eq(uoc2.money, 5000, "updateOrCreate: updated data locally")

-- ─── Test: createMany ─────────────────────────────────────────────

print("\n== createMany ==")

reset()
ScopeUser.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
assert_eq(#_db_log, 1, "createMany: single SQL query")
assert_match(_db_log[1].sql, "INSERT INTO `scope_users`", "createMany: INSERT query")
assert_match(_db_log[1].sql, "VALUES %(", "createMany: has VALUES")

-- ─── Test: Increment / Decrement ──────────────────────────────────

print("\n== Increment / Decrement ==")

-- Class-level increment
reset()
ScopeUser.increment("money", 500, { identifier = "license:a" })
assert_match(_db_log[1].sql, "money = money %+ %?", "class increment: SQL correct")
assert_eq(_db_log[1].params[1], 500, "class increment: amount param correct")

-- Class-level decrement
reset()
ScopeUser.decrement("money", 100, { identifier = "license:a" })
assert_match(_db_log[1].sql, "money = money %- %?", "class decrement: SQL correct")

-- Instance increment
reset()
_mock_results[1] = { { identifier = "license:inc", money = 1000, job = "test" } }
local incUser = ScopeUser.find({ identifier = "license:inc" })
reset()
incUser:increment("money", 250)
assert_eq(incUser.money, 1250, "instance increment: local value updated")
assert_match(_db_log[1].sql, "money = money %+ %?", "instance increment: SQL correct")

-- Instance decrement
reset()
incUser:decrement("money", 50)
assert_eq(incUser.money, 1200, "instance decrement: local value updated")

-- Instance increment with default amount
reset()
incUser:increment("money")
assert_eq(incUser.money, 1201, "instance increment: default amount is 1")

-- ─── Test: Select partial ─────────────────────────────────────────

print("\n== Select Partial ==")

reset()
_mock_results[1] = { { identifier = "license:sel", money = 500 } }
local partial = ScopeUser.find({ identifier = "license:sel" }, { select = { "money" } })
assert_match(_db_log[1].sql, "SELECT money, identifier FROM", "select partial: correct columns (with PK)")

-- ─── Test: Raw SQL ────────────────────────────────────────────────

print("\n== Raw SQL ==")

reset()
_mock_results[1] = { { cnt = 42 } }
local rawResult = ORM.raw("SELECT COUNT(*) as cnt FROM users WHERE money > ?", { 1000 })
assert_eq(rawResult[1].cnt, 42, "ORM.raw: returns correct result")
assert_match(_db_log[1].sql, "SELECT COUNT", "ORM.raw: executes SQL")

reset()
ORM.rawExec("DELETE FROM logs WHERE age > ?", { 30 })
assert_match(_db_log[1].sql, "DELETE FROM logs", "ORM.rawExec: executes SQL")

-- ─── Test: Debug / Logger ─────────────────────────────────────────

print("\n== Debug / Logger ==")

local LoggerLib = require("utils.logger")
assert_eq(LoggerLib._enabled, false, "logger: disabled by default")
ORM.debug(true)
assert_eq(LoggerLib._enabled, true, "logger: ORM.debug(true) enables it")
ORM.debug(false)
assert_eq(LoggerLib._enabled, false, "logger: ORM.debug(false) disables it")

-- ─── Test: Builder new features ───────────────────────────────────

print("\n== Builder New Features ==")

local BuilderLib = require("core.builder")

-- DISTINCT
b = BuilderLib.new("users", nil, nil)
sql = b:distinct():where({ job = "police" }):toSQL()
assert_match(sql, "SELECT DISTINCT %*", "builder: SELECT DISTINCT")

-- whereNull / whereNotNull
b = BuilderLib.new("users", nil, nil)
sql = b:whereNull("deleted_at"):toSQL()
assert_match(sql, "deleted_at IS NULL", "builder: whereNull")

b = BuilderLib.new("users", nil, nil)
sql = b:whereNotNull("email"):toSQL()
assert_match(sql, "email IS NOT NULL", "builder: whereNotNull")

-- whereIn with subquery
b = BuilderLib.new("users", nil, nil)
sql, params = b:whereIn("id", "SELECT user_id FROM active_users WHERE score > ?", { 100 }):toSQL()
assert_match(sql, "id IN %(SELECT user_id FROM active_users", "builder: whereIn subquery")
assert_eq(params[1], 100, "builder: whereIn subquery params")

-- whereNotIn with subquery
b = BuilderLib.new("users", nil, nil)
sql = b:whereNotIn("id", "SELECT user_id FROM banned"):toSQL()
assert_match(sql, "id NOT IN %(SELECT user_id FROM banned%)", "builder: whereNotIn subquery")

-- NOT IN operator in where
b = BuilderLib.new("users", nil, nil)
sql, params = b:where({ id = { "NOT IN", { 1, 2, 3 } } }):toSQL()
assert_match(sql, "id NOT IN %(", "builder: NOT IN operator")

-- Cursor pagination: after
b = BuilderLib.new("users", nil, nil)
sql, params = b:after("id", 50):limit(10):toSQL()
assert_match(sql, "id > %?", "builder: after cursor")
assert_match(sql, "ORDER BY id ASC", "builder: after sets ORDER BY")
assert_eq(params[1], 50, "builder: after cursor value")

-- Cursor pagination: before
b = BuilderLib.new("users", nil, nil)
sql, params = b:before("id", 50):limit(10):toSQL()
assert_match(sql, "id < %?", "builder: before cursor")

-- Cursor DESC
b = BuilderLib.new("users", nil, nil)
sql = b:after("id", 50, "DESC"):toSQL()
assert_match(sql, "id < %?", "builder: after DESC uses <")
assert_match(sql, "ORDER BY id DESC", "builder: after DESC order")

-- ─── Test: Query.insertMany ──────────────────────────────────────

print("\n== Query.insertMany ==")

local qm = Query.insertMany("users", {
    { identifier = "a", money = 1 },
    { identifier = "b", money = 2 },
})
assert_match(qm.sql, "INSERT INTO `users`", "insertMany: INSERT")
assert_match(qm.sql, "VALUES %(", "insertMany: VALUES")
assert_eq(#qm.params, 4, "insertMany: 4 params for 2 rows x 2 cols")

-- ─── Test: Query.increment / decrement ───────────────────────────

print("\n== Query.increment / decrement ==")

local qi = Query.increment("users", "money", 500, { identifier = "abc" })
assert_match(qi.sql, "money = money %+ %?", "Query.increment: SQL")
assert_eq(qi.params[1], 500, "Query.increment: amount param")

local qd = Query.decrement("users", "money", 100, { identifier = "abc" })
assert_match(qd.sql, "money = money %- %?", "Query.decrement: SQL")

-- ─── Test: Timestamps ─────────────────────────────────────────────

print("\n== Timestamps ==")

reset()
local TSUser = ORM.model("ts_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier", timestamps = true })

local ts = TSUser.create({ identifier = "license:ts1", money = 100 })
assert_eq(type(ts.created_at), "string", "timestamps: created_at auto-set")
assert_eq(type(ts.updated_at), "string", "timestamps: updated_at auto-set")

-- Update should set updated_at
reset()
_mock_results[1] = { { identifier = "license:ts2", money = 100, created_at = "2025-01-01", updated_at = "2025-01-01" } }
local ts2 = TSUser.find({ identifier = "license:ts2" })
reset()
ts2:update({ money = 200 })
assert_match(_db_log[1].sql, "updated_at", "timestamps: update sets updated_at")

-- ─── Test: Seed ───────────────────────────────────────────────────

print("\n== Seed ==")

local seedRan = false
ORM.seed(function(orm)
    seedRan = true
end)
assert_eq(seedRan, true, "ORM.seed: callback executed")

-- ─── Test: Eager Loading ──────────────────────────────────────────

print("\n== Eager Loading ==")

reset()
-- Setup models with relations (reuse existing)
local EUser = ORM.model("eusers", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

local EProfile = ORM.model("eprofiles", {
    id = "number", user_id = "string", bio = "string",
}, { primaryKey = "id" })

EUser.hasOne("profile", EProfile, { foreignKey = "user_id" })

reset()
_mock_results[1] = { { identifier = "license:eager", money = 500 } }
_mock_results[2] = { { id = 1, user_id = "license:eager", bio = "Hello" } }
local eager = EUser.find({ identifier = "license:eager" }, { include = { "profile" } })
assert_eq(eager.profile.bio, "Hello", "eager loading: profile loaded automatically")

-- ─── Test: whereHas ──────────────────────────────────────────────

print("\n== whereHas ==")

reset()
local WHUser = ORM.model("wh_users", {
    id         = "number",
    identifier = "string",
    money      = "number",
}, { primaryKey = "id" })

local WHVehicle = ORM.model("wh_vehicles", {
    id       = "number",
    owner_id = "number",
    plate    = "string",
}, { primaryKey = "id" })

WHUser.hasMany("vehicles", WHVehicle, { foreignKey = "owner_id" })

reset()
_mock_results[1] = { { id = 1, identifier = "license:wh1", money = 500 } }
local whBuilder = WHUser.whereHas("vehicles")
local whResults = whBuilder:get()
assert_eq(#whResults, 1, "whereHas: returns users with vehicles")
assert_match(_db_log[1].sql, "EXISTS", "whereHas: SQL contains EXISTS")
assert_match(_db_log[1].sql, "wh_vehicles", "whereHas: SQL references related table")

-- whereHas with callback
reset()
_mock_results[1] = { { id = 2, identifier = "license:wh2", money = 300 } }
local whBuilder2 = WHUser.whereHas("vehicles", function(b)
    b:where({ plate = "ABC123" })
end)
local whResults2 = whBuilder2:get()
assert_eq(#whResults2, 1, "whereHas with callback: returns filtered results")
assert_match(_db_log[1].sql, "plate", "whereHas with callback: SQL contains filter column")

-- ─── Test: countByRelation ──────────────────────────────────────

print("\n== countByRelation ==")

reset()
_mock_results[1] = { { id = 1, identifier = "license:cr1", money = 100 } }
_mock_results[2] = { { cnt = 3 } }
local crResults = WHUser.countByRelation("vehicles", { id = 1 })
assert_eq(#crResults, 1, "countByRelation: returns result entries")
assert_eq(crResults[1].count, 3, "countByRelation: count is correct")
assert_eq(crResults[1].instance._count_vehicles, 3, "countByRelation: _count_ field set on instance")

-- ─── Test: Nested Writes (createWith) ────────────────────────────

print("\n== Nested Writes ==")

reset()
local NWUser = ORM.model("nw_users", {
    id   = "number",
    name = "string",
}, { primaryKey = "id" })

local NWProfile = ORM.model("nw_profiles", {
    id      = "number",
    user_id = "number",
    bio     = "string",
}, { primaryKey = "id" })

local NWPost = ORM.model("nw_posts", {
    id      = "number",
    user_id = "number",
    title   = "string",
}, { primaryKey = "id" })

NWUser.hasOne("profile", NWProfile, { foreignKey = "user_id" })
NWUser.hasMany("posts", NWPost, { foreignKey = "user_id" })

-- Test hasOne nested write
reset()
_mock_results[1] = 1     -- insert user → id=1
_mock_results[2] = 10    -- insert profile → id=10
local nwUser = NWUser.createWith({
    name = "Alice",
    profile = { bio = "Hello World" },
})
assert_eq(nwUser.name, "Alice", "nested write hasOne: parent created")
assert_eq(#_db_log, 2, "nested write hasOne: 2 SQL queries (user + profile)")
assert_match(_db_log[2].sql, "nw_profiles", "nested write hasOne: profile INSERT references correct table")
assert_match(_db_log[2].sql, "user_id", "nested write hasOne: profile INSERT includes FK")

-- Test hasMany nested write
reset()
_mock_results[1] = 2     -- insert user → id=2
_mock_results[2] = 20    -- insert post 1
_mock_results[3] = 21    -- insert post 2
local nwUser2 = NWUser.createWith({
    name = "Bob",
    posts = {
        { title = "Post 1" },
        { title = "Post 2" },
    },
})
assert_eq(nwUser2.name, "Bob", "nested write hasMany: parent created")
assert_eq(#_db_log, 3, "nested write hasMany: 3 SQL queries (user + 2 posts)")

-- ─── Test: Introspection ─────────────────────────────────────────

print("\n== Introspection ==")

reset()
_mock_results[1] = {
    { Field = "id",        Type = "int(11)",       Null = "NO",  Key = "PRI", Default = nil,    Extra = "auto_increment" },
    { Field = "name",      Type = "varchar(255)",   Null = "YES", Key = "",    Default = nil,    Extra = "" },
    { Field = "money",     Type = "float",          Null = "YES", Key = "",    Default = "0",    Extra = "" },
    { Field = "is_active", Type = "tinyint(1)",     Null = "YES", Key = "",    Default = "1",    Extra = "" },
    { Field = "metadata",  Type = "json",           Null = "YES", Key = "",    Default = nil,    Extra = "" },
    { Field = "created_at",Type = "datetime",       Null = "YES", Key = "",    Default = nil,    Extra = "" },
}
local fields, pk = ORM.introspect("test_table")
assert_eq(pk, "id", "introspect: primary key detected")
assert_eq(fields.id, "number", "introspect: int → number")
assert_eq(fields.name, "string", "introspect: varchar → string")
assert_eq(fields.money, "number", "introspect: float → number")
assert_eq(fields.is_active, "boolean", "introspect: tinyint(1) → boolean")
assert_eq(fields.metadata, "json", "introspect: json → json")
assert_eq(fields.created_at, "datetime", "introspect: datetime → datetime")
assert_match(_db_log[1].sql, "DESCRIBE", "introspect: uses DESCRIBE query")

-- ─── Test: whereExists on Builder ────────────────────────────────

print("\n== Builder whereExists ==")

reset()
local Builder = require("core.builder")
local Adapter = require("database.adapter")
local MySQLDriver = require("database.mysql")
local testAdapter = Adapter.new(MySQLDriver.new())

_mock_results[1] = { { id = 1, name = "test" } }
local b = Builder.new("users", testAdapter)
b:whereExists("SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.id")
local sql, params = b:toSQL()
assert_match(sql, "EXISTS", "whereExists: SQL contains EXISTS")
assert_match(sql, "SELECT 1 FROM vehicles", "whereExists: contains subquery")

-- ─── Test: where() 2-arg shortcut ────────────────────────────────

print("\n== where() 2-arg shortcut ==")

local BuilderLib2 = require("core.builder")

b = BuilderLib2.new("users", nil, nil)
sql, params = b:where("job", "police"):toSQL()
assert_match(sql, "job = %?", "where 2-arg: implicit = operator")
assert_eq(params[1], "police", "where 2-arg: correct param value")

b = BuilderLib2.new("users", nil, nil)
sql, params = b:where("money", 1000):toSQL()
assert_match(sql, "money = %?", "where 2-arg: works with numbers")
assert_eq(params[1], 1000, "where 2-arg: number param correct")

-- orWhere 2-arg shortcut
b = BuilderLib2.new("users", nil, nil)
sql, params = b:where("job", "police"):orWhere("job", "medic"):toSQL()
assert_match(sql, "OR job = %?", "orWhere 2-arg: implicit = operator")
assert_eq(params[2], "medic", "orWhere 2-arg: correct param")

-- ─── Test: findAll with operators ────────────────────────────────

print("\n== findAll with operators ==")

reset()
_mock_results[1] = {
    { identifier = "license:rich1", money = 5000, job = "police" },
    { identifier = "license:rich2", money = 8000, job = "police" },
}
local richCops = User.findAll({ money = { ">", 1000 }, job = "police" })
assert_eq(#richCops, 2, "findAll operators: returns results")
assert_match(_db_log[1].sql, "money > %?", "findAll operators: has > operator in SQL")
assert_match(_db_log[1].sql, "job = %?", "findAll operators: has equality in SQL")

-- ─── Test: Transaction callback ─────────────────────────────────

print("\n== Transaction callback ==")

reset()
local txResult = ORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:cb1", money = 100 })
    tx:update("users", { money = 200 }, { identifier = "license:cb1" })
end)
assert_eq(txResult, true, "tx callback: returns true on success")
assert_eq(#_tx_log, 1, "tx callback: committed 1 transaction")
assert_eq(#_tx_log[1], 2, "tx callback: has 2 queries")

-- Transaction callback with custom adapter
reset()
local txResult2 = ORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:cb2", money = 500 })
end, testAdapter)
assert_eq(txResult2, true, "tx callback with adapter: returns true")

-- Builder mode still works
reset()
local txBuilder = ORM.transaction()
txBuilder:insert("users", { identifier = "license:builder", money = 0 })
local txCommit = txBuilder:commit()
assert_eq(txCommit, true, "tx builder mode: still works")

-- ─── Test: Scopes as direct methods ─────────────────────────────

print("\n== Scopes as direct methods ==")

local ScopedModel = ORM.model("scoped_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

ScopedModel.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

ScopedModel.scope("cops", function(b)
    b:where({ job = "police" })
end)

-- Direct method call
local richSQL = ScopedModel.rich():toSQL()
assert_match(richSQL, "money > %?", "scope method: rich() works directly")

local copsSQL = ScopedModel.cops():toSQL()
assert_match(copsSQL, "job = %?", "scope method: cops() works directly")

-- Chain scoped builder
local chainSQL = ScopedModel.rich():where({ job = "police" }):toSQL()
assert_match(chainSQL, "money > %?", "scope method: chainable with where")
assert_match(chainSQL, "job = %?", "scope method: has chained where")

-- ─── Test: Inline hooks ─────────────────────────────────────────

print("\n== Inline hooks ==")

reset()
local inlineHookLog = {}
local InlineHookUser = ORM.model("inline_hook_users", {
    identifier = "string",
    money      = "number",
}, {
    primaryKey = "identifier",
    hooks = {
        beforeCreate = function(data)
            inlineHookLog[#inlineHookLog + 1] = "inline_beforeCreate"
        end,
        afterCreate = function(instance)
            inlineHookLog[#inlineHookLog + 1] = "inline_afterCreate"
        end,
    },
})

InlineHookUser.create({ identifier = "license:inline1", money = 100 })
assert_eq(inlineHookLog[1], "inline_beforeCreate", "inline hooks: beforeCreate fired")
assert_eq(inlineHookLog[2], "inline_afterCreate", "inline hooks: afterCreate fired")

-- ─── Test: Inline scopes ────────────────────────────────────────

print("\n== Inline scopes ==")

local InlineScopeUser = ORM.model("inline_scope_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, {
    primaryKey = "identifier",
    scopes = {
        wealthy = function(b) b:where("money", ">", 50000) end,
        active = function(b) b:where({ job = { "!=", "unemployed" } }) end,
    },
})

local wealthySQL = InlineScopeUser.wealthy():toSQL()
assert_match(wealthySQL, "money > %?", "inline scopes: wealthy() works")

local activeSQL = InlineScopeUser.active():toSQL()
assert_match(activeSQL, "job != %?", "inline scopes: active() works")

-- Also accessible via scoped()
local scopedSQL = InlineScopeUser.scoped("wealthy"):toSQL()
assert_match(scopedSQL, "money > %?", "inline scopes: scoped() also works")

-- ─── Test: Paginate ─────────────────────────────────────────────

print("\n== Paginate ==")

reset()
-- Mock: count returns 25, data returns 10 items
_mock_results[1] = { { cnt = 25 } }
_mock_results[2] = {}
for i = 1, 10 do
    _mock_results[2][i] = { identifier = "license:" .. i, money = i * 100, job = "test" }
end

local page = ScopedModel.query():where({ job = "test" }):paginate(2, 10)
assert_eq(page.total, 25, "paginate: total is correct")
assert_eq(page.page, 2, "paginate: page is correct")
assert_eq(page.perPage, 10, "paginate: perPage is correct")
assert_eq(page.lastPage, 3, "paginate: lastPage is ceil(25/10) = 3")
assert_eq(#page.data, 10, "paginate: returns 10 items")

-- Paginate page 1 with default perPage
reset()
_mock_results[1] = { { cnt = 5 } }
_mock_results[2] = {}
for i = 1, 5 do
    _mock_results[2][i] = { identifier = "license:" .. i, money = i * 100, job = "test" }
end
local page2 = ScopedModel.query():paginate(1)
assert_eq(page2.perPage, 15, "paginate: default perPage is 15")
assert_eq(page2.lastPage, 1, "paginate: lastPage for 5 items / 15 per page = 1")

-- ─── Test: ORM.unpack() ─────────────────────────────────────────

print("\n== ORM.unpack ==")

local model, raw, migrate, transaction = ORM.unpack()
assert_eq(type(model), "function", "unpack: model is a function")
assert_eq(type(raw), "function", "unpack: raw is a function")
assert_eq(type(migrate), "function", "unpack: migrate is a function")
assert_eq(type(transaction), "function", "unpack: transaction is a function")

-- ─── Test: Inline relations ─────────────────────────────────────

print("\n== Inline relations ==")

reset()
local IRUser = ORM.model("ir_users", {
    identifier = "string",
    money      = "number",
}, {
    primaryKey = "identifier",
    relations = function(M)
        local IRProfile = ORM.model("ir_profiles", {
            id = "number", user_id = "string", bio = "string",
        }, { primaryKey = "id" })
        M.hasOne("profile", IRProfile, { foreignKey = "user_id" })
    end,
})

-- Apply relations
IRUser.applyRelations()

-- Test the relation works
reset()
_mock_results[1] = { { identifier = "license:ir1", money = 500 } }
_mock_results[2] = { { id = 1, user_id = "license:ir1", bio = "Inline!" } }
local irUser = IRUser.find({ identifier = "license:ir1" })
local irProfile = irUser:get("profile")
assert_eq(irProfile.bio, "Inline!", "inline relations: hasOne works after applyRelations")

-- ─── Test: Builder shortcuts ─────────────────────────────────────

print("\n== Builder shortcuts ==")

local BLib = require("core.builder")

-- whereIn with array
b = BLib.new("users", nil, nil)
sql, params = b:whereIn("job", { "police", "medic", "fire" }):toSQL()
assert_match(sql, "job IN %(%?, %?, %?%)", "whereIn array: SQL correct")
assert_eq(params[1], "police", "whereIn array: param 1")
assert_eq(params[3], "fire", "whereIn array: param 3")

-- whereNotIn with array
b = BLib.new("users", nil, nil)
sql, params = b:whereNotIn("id", { 1, 2, 3 }):toSQL()
assert_match(sql, "id NOT IN %(%?, %?, %?%)", "whereNotIn array: SQL correct")

-- whereBetween
b = BLib.new("users", nil, nil)
sql, params = b:whereBetween("money", 100, 5000):toSQL()
assert_match(sql, "money BETWEEN %? AND %?", "whereBetween: SQL correct")
assert_eq(params[1], 100, "whereBetween: min param")
assert_eq(params[2], 5000, "whereBetween: max param")

-- whereNotBetween
b = BLib.new("users", nil, nil)
sql = b:whereNotBetween("money", 0, 100):toSQL()
assert_match(sql, "money NOT BETWEEN %? AND %?", "whereNotBetween: SQL correct")

-- whereLike
b = BLib.new("users", nil, nil)
sql, params = b:whereLike("name", "%john%"):toSQL()
assert_match(sql, "name LIKE %?", "whereLike: SQL correct")
assert_eq(params[1], "%john%", "whereLike: param correct")

-- orderByDesc
b = BLib.new("users", nil, nil)
sql = b:orderByDesc("money"):toSQL()
assert_match(sql, "ORDER BY money DESC", "orderByDesc: SQL correct")

-- orderByAsc
b = BLib.new("users", nil, nil)
sql = b:orderByAsc("name"):toSQL()
assert_match(sql, "ORDER BY name ASC", "orderByAsc: SQL correct")

-- latest
b = BLib.new("users", nil, nil)
sql = b:latest():toSQL()
assert_match(sql, "ORDER BY created_at DESC", "latest: default column")

b = BLib.new("users", nil, nil)
sql = b:latest("updated_at"):toSQL()
assert_match(sql, "ORDER BY updated_at DESC", "latest: custom column")

-- oldest
b = BLib.new("users", nil, nil)
sql = b:oldest():toSQL()
assert_match(sql, "ORDER BY created_at ASC", "oldest: default column")

-- pluck
reset()
_mock_results[1] = {
    { job = "police" },
    { job = "medic" },
    { job = "fire" },
}
local jobs = User.query():pluck("job")
assert_eq(#jobs, 3, "pluck: returns 3 values")
assert_eq(jobs[1], "police", "pluck: value 1 correct")
assert_eq(jobs[2], "medic", "pluck: value 2 correct")

-- exists (true)
reset()
_mock_results[1] = { { ["1"] = 1 } }
local doesExist = User.query():where("job", "police"):exists()
assert_eq(doesExist, true, "exists: returns true when found")

-- exists (false)
reset()
_mock_results[1] = {}
local doesNotExist = User.query():where("job", "unicorn"):exists()
assert_eq(doesNotExist, false, "exists: returns false when not found")

-- chunk
reset()
local chunkResults = {}
local chunkAdapter = require("database.adapter").new(require("database.mysql").new())
local ChunkUser = ORM.model("chunk_users", {
    id = "number", name = "string",
}, { primaryKey = "id" })

-- Mock: first chunk has 2, second chunk has 1
local chunkCall = 0
_mock_results[1] = { { id = 1, name = "a" }, { id = 2, name = "b" } }
_mock_results[2] = { { id = 3, name = "c" } }
ChunkUser.query():chunk(2, function(rows, idx)
    chunkResults[idx] = #rows
end)
assert_eq(chunkResults[1], 2, "chunk: first chunk has 2 items")
assert_eq(chunkResults[2], 1, "chunk: second chunk has 1 item")

-- ─── Test: Model shortcuts ──────────────────────────────────────

print("\n== Model shortcuts ==")

-- findOrFail: found
reset()
_mock_results[1] = { { identifier = "license:exists", money = 500, job = "test" } }
local fof = User.findOrFail({ identifier = "license:exists" })
assert_eq(fof.identifier, "license:exists", "findOrFail: returns instance when found")

-- findOrFail: not found → error
reset()
_mock_results[1] = {}
local fofOk, fofErr = pcall(function()
    User.findOrFail({ identifier = "license:nope" })
end)
assert_eq(fofOk, false, "findOrFail: throws error when not found")
assert_match(fofErr, "Record not found", "findOrFail: error message correct")

-- Model.first
reset()
_mock_results[1] = { { identifier = "license:first", money = 100, job = "test" } }
local firstUser = User.first({ job = "test" })
assert_eq(firstUser.identifier, "license:first", "Model.first: returns first match")
assert_match(_db_log[1].sql, "LIMIT 1", "Model.first: adds LIMIT 1")

-- Model.first without where
reset()
_mock_results[1] = { { identifier = "license:any", money = 100, job = "test" } }
local anyUser = User.first()
assert_eq(anyUser.identifier, "license:any", "Model.first: works without where")

-- Model.exists (true)
reset()
_mock_results[1] = { { ["1"] = 1 } }
local ex = User.exists({ job = "police" })
assert_eq(ex, true, "Model.exists: returns true")

-- Model.exists (false)
reset()
_mock_results[1] = {}
local nex = User.exists({ job = "unicorn" })
assert_eq(nex, false, "Model.exists: returns false")

-- Model.pluck
reset()
_mock_results[1] = { { money = 100 }, { money = 200 }, { money = 300 } }
local moneys = User.pluck("money", { job = "police" })
assert_eq(#moneys, 3, "Model.pluck: returns 3 values")
assert_eq(moneys[1], 100, "Model.pluck: value correct")

-- Model.updateWhere
reset()
User.updateWhere({ identifier = "license:uw" }, { money = 9999 })
assert_match(_db_log[1].sql, "UPDATE", "updateWhere: runs UPDATE")
assert_match(_db_log[1].sql, "money = %?", "updateWhere: sets money")

-- Model.deleteWhere
reset()
User.deleteWhere({ identifier = "license:dw" })
assert_match(_db_log[1].sql, "DELETE", "deleteWhere: runs DELETE")

end -- end runExtendedTests

runExtendedTests()

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
