-- tests/test_fivem_globals.lua
-- Simulates FiveM loading order (no require, globals only)
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.3 lua tests/test_fivem_globals.lua

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = {
    encode = function(t)
        if type(t) ~= "table" then return tostring(t) end
        local isArray = #t > 0
        if isArray then
            local parts = {}
            for _, v in ipairs(t) do
                if type(v) == "string" then parts[#parts + 1] = '"' .. v .. '"'
                elseif type(v) == "table" then parts[#parts + 1] = json.encode(v)
                else parts[#parts + 1] = tostring(v) end
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
        if s:sub(1, 1) == "{" then
            local t = {}
            for k, v in s:gmatch('"([^"]+)":([^,}]+)') do
                if v:sub(1, 1) == '"' then t[k] = v:sub(2, -2)
                elseif v == "true" then t[k] = true
                elseif v == "false" then t[k] = false
                else t[k] = tonumber(v) or v end
            end
            return t
        elseif s:sub(1, 1) == "[" then
            return { s }
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
        if result then cb(result)
        elseif query:match("^INSERT") then cb(1)
        elseif query:match("^SELECT") then cb({})
        else cb(1) end
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

-- Mock FiveM exports function
exports = setmetatable({}, {
    __call = function(_, name, fn)
        -- store export
    end,
    __index = function(_, name)
        return setmetatable({}, {
            __index = function(_, method)
                return function() return nil end
            end,
        })
    end,
})

-- ─── Simulate FiveM loading order (dofile, NO require) ─────────────

print("\n== Loading OrvexORM via globals (FiveM mode) ==")

dofile("utils/helpers.lua")
dofile("utils/serializer.lua")
dofile("utils/validator.lua")
dofile("utils/cache.lua")
dofile("utils/logger.lua")

dofile("database/mysql.lua")
dofile("database/adapter.lua")

dofile("core/schema.lua")
dofile("core/query.lua")
dofile("core/relations.lua")
dofile("core/builder.lua")
dofile("core/transaction.lua")
dofile("core/migration.lua")
dofile("core/model.lua")
dofile("core/orm.lua")
dofile("lib/export.lua")

-- ─── Test: Globals exist ────────────────────────────────────────────

print("\n== Globals loaded ==")

assert_eq(type(OrvexHelpers), "table", "OrvexHelpers is a table")
assert_eq(type(OrvexSerializer), "table", "OrvexSerializer is a table")
assert_eq(type(OrvexValidator), "table", "OrvexValidator is a table")
assert_eq(type(OrvexCache), "table", "OrvexCache is a table")
assert_eq(type(OrvexLogger), "table", "OrvexLogger is a table")
assert_eq(type(OrvexMySQLDriver), "table", "OrvexMySQLDriver is a table")
assert_eq(type(OrvexAdapter), "table", "OrvexAdapter is a table")
assert_eq(type(OrvexSchema), "table", "OrvexSchema is a table")
assert_eq(type(OrvexQuery), "table", "OrvexQuery is a table")
assert_eq(type(OrvexRelations), "table", "OrvexRelations is a table")
assert_eq(type(OrvexBuilder), "table", "OrvexBuilder is a table")
assert_eq(type(OrvexTransaction), "table", "OrvexTransaction is a table")
assert_eq(type(OrvexMigration), "table", "OrvexMigration is a table")
assert_eq(type(OrvexModelFactory), "table", "OrvexModelFactory is a table")
assert_eq(type(OrvexORM), "table", "OrvexORM is global")

-- ─── Test: ORM works via globals ────────────────────────────────────

print("\n== ORM CRUD via globals ==")

reset()
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

local player = User.create({ identifier = "license:abc", money = 500, job = "police" })
assert_eq(player.identifier, "license:abc", "create works")
assert_eq(player.money, 500, "create has correct money")

reset()
_mock_results[1] = { { identifier = "license:abc", money = 500, job = "police" } }
local found = User.find({ identifier = "license:abc" })
assert_eq(found.money, 500, "find works")

reset()
found:update({ money = 1000 })
assert_eq(found.money, 1000, "update works")

-- ─── Test: Query builder via globals ────────────────────────────────

print("\n== Query Builder via globals ==")

local sql, params = User.query()
    :where("job", "police")
    :where("money", ">", 500)
    :orderBy("money", "DESC")
    :limit(10)
    :toSQL()

assert_match(sql, "job = %?", "where 2-arg works")
assert_match(sql, "money > %?", "where 3-arg works")
assert_match(sql, "ORDER BY money DESC", "orderBy works")
assert_match(sql, "LIMIT 10", "limit works")

-- ─── Test: Transaction callback via globals ─────────────────────────

print("\n== Transaction callback via globals ==")

reset()
local txResult = OrvexORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:tx", money = 100 })
end)
assert_eq(txResult, true, "transaction callback works")
assert_eq(#_tx_log, 1, "transaction committed")

-- ─── Test: Scopes via globals ───────────────────────────────────────

print("\n== Scopes via globals ==")

User.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

local scopeSQL = User.rich():toSQL()
assert_match(scopeSQL, "money > %?", "scope as method works")

-- ─── Test: Inline opts via globals ──────────────────────────────────

print("\n== Inline opts via globals ==")

local hookFired = false
local InlineUser = OrvexORM.model("inline_users", {
    id    = "number",
    name  = "string",
}, {
    hooks = {
        beforeCreate = function(data) hookFired = true end,
    },
    scopes = {
        active = function(b) b:where({ name = { "!=", "deleted" } }) end,
    },
})

reset()
InlineUser.create({ id = 1, name = "test" })
assert_eq(hookFired, true, "inline hook works")

local activeSQL = InlineUser.active():toSQL()
assert_match(activeSQL, "name != %?", "inline scope works")

-- ─── Test: Paginate via globals ─────────────────────────────────────

print("\n== Paginate via globals ==")

reset()
_mock_results[1] = { { cnt = 30 } }
_mock_results[2] = {}
for i = 1, 10 do
    _mock_results[2][i] = { identifier = "license:" .. i, money = i * 100, job = "test" }
end

local page = User.query():where("job", "test"):paginate(2, 10)
assert_eq(page.total, 30, "paginate total correct")
assert_eq(page.page, 2, "paginate page correct")
assert_eq(page.lastPage, 3, "paginate lastPage correct")
assert_eq(#page.data, 10, "paginate data count correct")

-- ─── Test: ORM.unpack via globals ───────────────────────────────────

print("\n== ORM.unpack via globals ==")

local model, raw, migrate, transaction = OrvexORM.unpack()
assert_eq(type(model), "function", "unpack model works")
assert_eq(type(transaction), "function", "unpack transaction works")

-- ─── Test: sync() with timestamps via globals ────────────────────────

print("\n== sync() with timestamps via globals ==")

reset()
local TsUser = OrvexORM.model("ts_fivem_users", {
    id   = "number",
    name = "string",
}, { timestamps = true })

TsUser.sync()
assert_match(_db_log[1].sql, "CREATE TABLE", "sync timestamps: CREATE TABLE")
assert_match(_db_log[1].sql, "created_at", "sync timestamps: has created_at")
assert_match(_db_log[1].sql, "updated_at", "sync timestamps: has updated_at")

-- ─── Test: sync() with softDelete via globals ────────────────────────

print("\n== sync() with softDelete via globals ==")

reset()
local SdUser = OrvexORM.model("sd_fivem_users", {
    id   = "number",
    name = "string",
}, { softDelete = true })

SdUser.sync()
assert_match(_db_log[1].sql, "CREATE TABLE", "sync softDelete: CREATE TABLE")
assert_match(_db_log[1].sql, "deleted_at", "sync softDelete: has deleted_at")

-- ─── Test: SchemaBuilder multiple create via globals ─────────────────

print("\n== SchemaBuilder multiple create via globals ==")

do
    local sb = OrvexMigration.SchemaBuilder.new()
    sb:create("gbl_table_a", function(t)
        t:id()
        t:string("label")
    end)
    sb:create("gbl_table_b", function(t)
        t:id()
        t:integer("qty")
    end)
    local stmts = sb:toSQL()
    assert_eq(#stmts, 2, "multi-create globals: 2 statements")
    assert_match(stmts[1], "gbl_table_a", "multi-create globals: first table")
    assert_match(stmts[2], "gbl_table_b", "multi-create globals: second table")
end

-- ─── Test: Date types in serializer via globals ──────────────────────

print("\n== Date types in serializer via globals ==")

do
    local dateVal = OrvexSerializer.decode(806716800, "date")
    assert_eq(type(dateVal), "string", "globals date decode: returns string")
    assert_match(dateVal, "^%d%d%d%d%-%d%d%-%d%d$", "globals date decode: YYYY-MM-DD format")

    local dtVal = OrvexSerializer.decode(1710000000, "datetime")
    assert_eq(type(dtVal), "string", "globals datetime decode: returns string")
    assert_match(dtVal, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$", "globals datetime decode: YYYY-MM-DD HH:MM:SS")
end

-- ─── Test: Builder aggregates return numbers via globals ─────────────

print("\n== Builder aggregates return numbers via globals ==")

reset()
_mock_results[1] = { { val = "999" } }
local sumVal = User.query():sum("money")
assert_eq(type(sumVal), "number", "globals sum: returns number")
assert_eq(sumVal, 999, "globals sum: correct value")

reset()
_mock_results[1] = { { cnt = "7" } }
local cntVal = User.query():count()
assert_eq(type(cntVal), "number", "globals count: returns number")
assert_eq(cntVal, 7, "globals count: correct value")

reset()
_mock_results[1] = { { val = "33.3" } }
local avgVal = User.query():avg("money")
assert_eq(type(avgVal), "number", "globals avg: returns number")
assert_eq(avgVal, 33.3, "globals avg: correct value")

-- ─── Test: Sync exports driver via globals ───────────────────────────

print("\n== Sync exports driver via globals ==")

assert_eq(type(OrvexORM.model), "function", "ORM.model is a function via globals")
assert_eq(type(OrvexORM.transaction), "function", "ORM.transaction is a function via globals")
assert_eq(type(OrvexORM.schema), "function", "ORM.schema is a function via globals")
assert_eq(type(OrvexORM.migrate), "function", "ORM.migrate is a function via globals")
assert_eq(type(OrvexORM.rollback), "function", "ORM.rollback is a function via globals")
assert_eq(type(OrvexORM.raw), "function", "ORM.raw is a function via globals")
assert_eq(type(OrvexORM.rawExec), "function", "ORM.rawExec is a function via globals")
assert_eq(type(OrvexORM.seed), "function", "ORM.seed is a function via globals")
assert_eq(type(OrvexORM.debug), "function", "ORM.debug is a function via globals")
assert_eq(type(OrvexORM.enableCache), "function", "ORM.enableCache is a function via globals")
assert_eq(type(OrvexORM.disableCache), "function", "ORM.disableCache is a function via globals")
assert_eq(type(OrvexORM.unpack), "function", "ORM.unpack is a function via globals")

-- ─── Summary ────────────────────────────────────────────────────────

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
