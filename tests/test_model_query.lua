-- tests/test_model_query.lua
-- Model queries: terminal methods, aggregates, operators, pagination, pluck / exists / chunk, whereRaw.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_model_query.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults = Mock.log, Mock.results
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

local ScopedModel = ORM.model("scoped_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

local TTUser = ORM.model("tt_users", {
    id       = "number",
    name     = "string",
    position = "json",
}, { primaryKey = "id" })

-- ─── Test: Builder Terminal Methods ────────────────────────────────

T.section("Builder Terminal Methods")

reset()
mockResults[1] = { { cnt = 42 } }
local cnt = User.count({ job = "police" })
T.eq(cnt, 42, "Model.count returns correct value")
T.match(dbLog[1].sql, "SELECT COUNT", "count generates COUNT SQL")

reset()
mockResults[1] = { { val = 15000 } }
local total = User.sum("money", { job = "police" })
T.eq(total, 15000, "Model.sum returns correct value")

reset()
mockResults[1] = { { val = 750 } }
local average = User.avg("money", { job = "police" })
T.eq(average, 750, "Model.avg returns correct value")

reset()
mockResults[1] = { { val = 100 } }
local minimum = User.min("money", { job = "police" })
T.eq(minimum, 100, "Model.min returns correct value")

reset()
mockResults[1] = { { val = 9999 } }
local maximum = User.max("money", { job = "police" })
T.eq(maximum, 9999, "Model.max returns correct value")

reset()
mockResults[1] = {
    { identifier = "license:a", money = 900, job = "police" },
    { identifier = "license:b", money = 800, job = "police" },
}
local results = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :orderBy("money", "DESC")
    :limit(2)
    :get()
T.eq(#results, 2, "query chain returns correct count")
T.match(dbLog[1].sql, "ORDER BY `money` DESC", "query chain has ORDER BY")

reset()
mockResults[1] = { { identifier = "license:a", money = 900, job = "police" } }
local first = User.query():where({ job = "police" }):first()
T.eq(first.identifier, "license:a", "query first returns single instance")
T.match(dbLog[1].sql, "LIMIT 1", "first adds LIMIT 1")

-- ─── Test: findAll with operators ────────────────────────────────

T.section("findAll with operators")

reset()
mockResults[1] = {
    { identifier = "license:rich1", money = 5000, job = "police" },
    { identifier = "license:rich2", money = 8000, job = "police" },
}
local richCops = User.findAll({ money = ORM.op(">", 1000), job = "police" })
T.eq(#richCops, 2, "findAll operators: returns results")
T.match(dbLog[1].sql, "`money` > %?", "findAll operators: has > operator in SQL")
T.match(dbLog[1].sql, "`job` = %?", "findAll operators: has equality in SQL")

-- ─── Test: Paginate ─────────────────────────────────────────────

T.section("Paginate")

reset()
-- Mock: count returns 25, data returns 10 items
mockResults[1] = { { cnt = 25 } }
mockResults[2] = {}
for i = 1, 10 do
    mockResults[2][i] = { identifier = "license:" .. i, money = i * 100, job = "test" }
end

local page = ScopedModel.query():where({ job = "test" }):paginate(2, 10)
T.eq(page.total, 25, "paginate: total is correct")
T.eq(page.page, 2, "paginate: page is correct")
T.eq(page.perPage, 10, "paginate: perPage is correct")
T.eq(page.lastPage, 3, "paginate: lastPage is ceil(25/10) = 3")
T.eq(#page.data, 10, "paginate: returns 10 items")

-- Paginate page 1 with default perPage
reset()
mockResults[1] = { { cnt = 5 } }
mockResults[2] = {}
for i = 1, 5 do
    mockResults[2][i] = { identifier = "license:" .. i, money = i * 100, job = "test" }
end
local page2 = ScopedModel.query():paginate(1)
T.eq(page2.perPage, 15, "paginate: default perPage is 15")
T.eq(page2.lastPage, 1, "paginate: lastPage for 5 items / 15 per page = 1")

-- pluck
reset()
mockResults[1] = {
    { job = "police" },
    { job = "medic" },
    { job = "fire" },
}
local jobs = User.query():pluck("job")
T.eq(#jobs, 3, "pluck: returns 3 values")
T.eq(jobs[1], "police", "pluck: value 1 correct")
T.eq(jobs[2], "medic", "pluck: value 2 correct")

-- exists (true)
reset()
mockResults[1] = { { ["1"] = 1 } }
local doesExist = User.query():where("job", "police"):exists()
T.eq(doesExist, true, "exists: returns true when found")

-- exists (false)
reset()
mockResults[1] = {}
local doesNotExist = User.query():where("job", "unicorn"):exists()
T.eq(doesNotExist, false, "exists: returns false when not found")

-- chunk
reset()
local chunkResults = {}
local chunkAdapter = require("database.adapter").new(require("database.mysql").new())
local ChunkUser = ORM.model("chunk_users", {
    id = "number", name = "string",
}, { primaryKey = "id" })

-- Mock: first chunk has 2, second chunk has 1
local chunkCall = 0
mockResults[1] = { { id = 1, name = "a" }, { id = 2, name = "b" } }
mockResults[2] = { { id = 3, name = "c" } }
ChunkUser.query():chunk(2, function(rows, idx)
    chunkResults[idx] = #rows
end)
T.eq(chunkResults[1], 2, "chunk: first chunk has 2 items")
T.eq(chunkResults[2], 1, "chunk: second chunk has 1 item")

-- ─── Test: Builder aggregates return numbers ─────────────────────────

T.section("Builder aggregates return numbers")

do
    -- sum with string result
    reset()
    mockResults[1] = { { val = "500" } }
    local sumResult = User.query():sum("money")
    T.eq(type(sumResult), "number", "sum: returns number type")
    T.eq(sumResult, 500, "sum: value is 500")

    -- avg with string result
    reset()
    mockResults[1] = { { val = "250.5" } }
    local avgResult = User.query():avg("money")
    T.eq(type(avgResult), "number", "avg: returns number type")
    T.eq(avgResult, 250.5, "avg: value is 250.5")

    -- count with string result
    reset()
    mockResults[1] = { { cnt = "42" } }
    local countResult = User.query():count()
    T.eq(type(countResult), "number", "count: returns number type")
    T.eq(countResult, 42, "count: value is 42")

    -- sum with actual number (should still work)
    reset()
    mockResults[1] = { { val = 100 } }
    local sumNum = User.query():sum("money")
    T.eq(type(sumNum), "number", "sum numeric: returns number type")
    T.eq(sumNum, 100, "sum numeric: value is 100")

    -- sum with empty result
    reset()
    mockResults[1] = {}
    local sumEmpty = User.query():sum("money")
    T.eq(sumEmpty, 0, "sum empty: returns 0")
end

-- whereRaw
T.section("Builder:whereRaw")

reset()
mockResults[1] = {}
TTUser.query():whereRaw("JSON_EXTRACT(position, '$.x') > ?", { 5 }):get()
T.match(dbLog[1].sql, "JSON_EXTRACT", "whereRaw: clause injected")
T.eq(dbLog[1].params[1], 5, "whereRaw: params bound")

-- exists() with pre-set limit must not emit two LIMIT clauses
T.section("exists() with limit")

reset()
mockResults[1] = { { ["1"] = 1 } }
TTUser.query():limit(10):exists()
local _, limitCount = dbLog[1].sql:gsub("LIMIT", "")
T.eq(limitCount, 1, "exists: single LIMIT clause")

T.finish()
