-- tests/test_core_builder.lua
-- Regression tests for the chainable query builder and identifier quoting.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_core_builder.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = {
    encode = function(t) return tostring(t) end,
    decode = function(s) return s end,
}

local dbLog = {}
local mockResults = {}

local function mockDriverCall(query, params, cb)
    dbLog[#dbLog + 1] = { sql = query, params = params }
    local result = mockResults[#dbLog]
    if result then return cb(result) end
    if query:match("^SELECT") then return cb({}) end
    return cb(1)
end

MySQL = {
    prepare = mockDriverCall,
    query = mockDriverCall,
    insert = mockDriverCall,
    update = mockDriverCall,
    transaction = function(_, cb) cb(true) end,
}

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

-- ─── Test helpers ──────────────────────────────────────────────────

local passed, failed = 0, 0

local function report(ok, msg, detail)
    if ok then
        passed = passed + 1
        print(("  ✓ %s"):format(msg))
    else
        failed = failed + 1
        print(("  ✗ %s — %s"):format(msg, detail))
    end
end

local function assertEq(got, expected, msg)
    report(got == expected, msg, ("expected: %s, got: %s"):format(tostring(expected), tostring(got)))
end

local function assertContains(str, fragment, msg)
    report(str:find(fragment, 1, true) ~= nil, msg, ("'%s' does not contain '%s'"):format(str, fragment))
end

local function assertNotContains(str, fragment, msg)
    report(str:find(fragment, 1, true) == nil, msg, ("'%s' unexpectedly contains '%s'"):format(str, fragment))
end

local function assertErrors(fn, msg)
    local ok = pcall(fn)
    report(not ok, msg, "expected an error, none raised")
end

local function reset()
    dbLog = {}
    mockResults = {}
end

--- Adapter double recording executed statements and replaying queued rows.
local function fakeAdapter(queuedRows)
    local adapter = { log = {}, queue = queuedRows or {} }
    function adapter:execute(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        return table.remove(self.queue, 1) or {}
    end
    return adapter
end

local Helpers = require("utils.helpers")
local Builder = require("core.builder")
local Query = require("core.query")

local function users(adapter)
    return Builder.new("users", adapter or fakeAdapter())
end

-- ─── Helpers.quoteId ───────────────────────────────────────────────

print("\n== Helpers.quoteId ==")

assertEq(Helpers.quoteId("group"), "`group`", "quoteId: plain identifier")
assertEq(Helpers.quoteId("users.id"), "`users`.`id`", "quoteId: qualified identifier")
assertEq(Helpers.quoteId("*"), "*", "quoteId: star untouched")
assertEq(Helpers.quoteId("users.*"), "`users`.*", "quoteId: qualified star")
assertEq(Helpers.quoteId("we`ird"), "`we``ird`", "quoteId: escapes backticks")

assertEq(Helpers.quoteColumnList("id, users.name"), "`id`, `users`.`name`", "quoteColumnList: quotes identifiers")
assertEq(Helpers.quoteColumnList("COUNT(*) as c, job"), "COUNT(*) as c, `job`", "quoteColumnList: keeps expressions")
assertEq(Helpers.quoteColumnList("*"), "*", "quoteColumnList: star untouched")

-- ─── #1 where(field, op, value) goes through the entry parser ──────

print("\n== where(field, op, value) ==")

local sql, params = users():where("job", "IN", { "police", "medic" }):toSQL()
assertContains(sql, "`job` IN (?, ?)", "where 3-arg IN expands placeholders")
assertEq(#params, 2, "where 3-arg IN binds each value")

sql, params = users():where("job", "not in", { "a" }):toSQL()
assertContains(sql, "`job` NOT IN (?)", "where 3-arg NOT IN (case-insensitive)")

sql, params = users():where("money", "BETWEEN", { 1, 9 }):toSQL()
assertContains(sql, "`money` BETWEEN ? AND ?", "where 3-arg BETWEEN")
assertEq(params[2], 9, "where 3-arg BETWEEN binds both bounds")

sql, params = users():where("deleted_at", "IS", "NULL"):toSQL()
assertContains(sql, "`deleted_at` IS NULL", "where 3-arg IS NULL")
assertEq(#params, 0, "where 3-arg IS NULL binds nothing")

sql = users():where("deleted_at", "IS NOT", "NULL"):toSQL()
assertContains(sql, "`deleted_at` IS NOT NULL", "where 3-arg IS NOT NULL")

assertErrors(function() users():where("age", ">", nil) end, "where 3-arg with explicit nil value errors")
assertErrors(function() users():orWhere("age", ">", nil) end, "orWhere 3-arg with explicit nil value errors")
assertErrors(function() users():where("age", nil) end, "where 2-arg with nil value errors")
assertErrors(function() users():where("job", "IN", {}) end, "where IN with empty array errors")
assertErrors(function() users():where("job", "DROP", 1) end, "where with invalid operator errors")

sql, params = users():where("job", "police"):orWhere("job", "IN", { "medic", "ems" }):toSQL()
assertContains(sql, "`job` = ? OR `job` IN (?, ?)", "orWhere 3-arg IN expands placeholders")
assertEq(#params, 3, "orWhere 3-arg IN binds each value")

-- ─── #2/#34 constraints are AND-ed outside user clauses ────────────

print("\n== Constraints vs user clauses ==")

local b = users()
b:constrain(function(q) q:whereNull("deleted_at") end)
sql = b:where({ job = "police" }):orWhere({ job = "medic" }):toSQL()
assertContains(sql, "WHERE `deleted_at` IS NULL AND (`job` = ? OR `job` = ?)",
    "constraint wraps user OR clauses in parentheses")

b = users()
b:constrain(function(q) q:whereNull("deleted_at") end)
sql = b:toSQL()
assertEq(sql, "SELECT * FROM `users` WHERE `deleted_at` IS NULL", "constraint alone, no double spaces")

sql = users():where({ job = "police" }):orWhere({ job = "medic" }):toSQL()
assertEq(sql, "SELECT * FROM `users` WHERE `job` = ? OR `job` = ?", "user clauses without constraint unchanged")

reset()
local ORM = require("core.orm")
local SoftPost = ORM.model("cb_posts", {
    id = "number", user_id = "number", title = "string",
}, { softDelete = true })

sql = SoftPost.query():where({ user_id = 1 }):orWhere({ user_id = 2 }):toSQL()
assertContains(sql, "`deleted_at` IS NULL AND (`user_id` = ? OR `user_id` = ?)",
    "softDelete query keeps trashed rows out of OR branches")

sql = SoftPost.onlyTrashed():where({ user_id = 1 }):orWhere({ user_id = 2 }):toSQL()
assertContains(sql, "`deleted_at` IS NOT NULL AND (`user_id` = ? OR `user_id` = ?)",
    "onlyTrashed keeps live rows out of OR branches")

reset()
SoftPost.find({ id = 1 })
local _, softFilters = dbLog[1].sql:gsub("deleted_at", "")
assertEq(softFilters, 1, "softDelete find filters trashed rows exactly once")

reset()
SoftPost.restore({ id = 1 })
assertEq(dbLog[1].sql, "UPDATE `cb_posts` SET `deleted_at` = NULL WHERE `id` = ?", "restore quotes identifiers")

b = users()
assertErrors(function() b:constrain(function(q) q:where("x", ">", nil) end) end, "constrain propagates errors")
sql = b:where({ job = "police" }):toSQL()
assertEq(sql, "SELECT * FROM `users` WHERE `job` = ?", "constrain restores user conditions after an error")

sql = users():whereColumn("users.updated_at", ">", "users.created_at"):toSQL()
assertContains(sql, "`users`.`updated_at` > `users`.`created_at`", "whereColumn compares two quoted columns")

local WhUser = ORM.model("cb_users", { id = "number", name = "string" }, { primaryKey = "id" })
WhUser.hasMany("posts", SoftPost, { foreignKey = "user_id" })
local whereHasSQL = WhUser.whereHas("posts", function(q)
    q:where({ title = "a" }):orWhere({ title = "b" })
end):toSQL()
assertContains(whereHasSQL,
    "EXISTS (SELECT 1 FROM `cb_posts` WHERE `cb_posts`.`deleted_at` IS NULL"
    .. " AND `cb_posts`.`user_id` = `cb_users`.`id` AND (`title` = ? OR `title` = ?))",
    "whereHas keeps correlation outside callback OR clauses")

-- ─── #8 count() / paginate() with distinct, groupBy, paging ────────

print("\n== count() and paginate() ==")

local adapter = fakeAdapter({ { { cnt = 3 } } })
users(adapter):select("job"):distinct():count()
assertEq(adapter.log[1].sql, "SELECT COUNT(*) AS cnt FROM (SELECT DISTINCT `job` FROM `users`) AS t",
    "count with distinct wraps the query")

adapter = fakeAdapter({ { { cnt = 2 } } })
local total = users(adapter):select("job"):groupBy("job"):count()
assertEq(adapter.log[1].sql, "SELECT COUNT(*) AS cnt FROM (SELECT `job` FROM `users` GROUP BY `job`) AS t",
    "count with groupBy counts groups")
assertEq(total, 2, "count with groupBy returns number of groups")

adapter = fakeAdapter({ { { cnt = 42 } } })
total = users(adapter):where({ job = "police" }):orderBy("id"):limit(10):offset(10):count()
assertEq(adapter.log[1].sql, "SELECT COUNT(*) AS cnt FROM `users` WHERE `job` = ?",
    "count strips ORDER BY, LIMIT and OFFSET")
assertEq(total, 42, "count ignores paging")

adapter = fakeAdapter({ { { cnt = 4 } }, {} })
local page = users(adapter):select("job"):groupBy("job"):paginate(1, 3)
assertContains(adapter.log[1].sql, "GROUP BY `job`) AS t", "paginate counts grouped rows")
assertEq(page.total, 4, "paginate total uses grouped count")
assertEq(page.lastPage, 2, "paginate lastPage uses grouped count")
assertContains(adapter.log[2].sql, "GROUP BY `job` LIMIT 3 OFFSET 0", "paginate data query keeps groupBy")

-- A derived table rejects duplicate column names (MySQL error 1060), so a
-- `*` select over joined tables must not be copied into it.
adapter = fakeAdapter({ { { cnt = 5 } } })
users(adapter):distinct():leftJoin("posts", "posts.user_id", "users.id"):count()
assertEq(adapter.log[1].sql,
    "SELECT COUNT(*) AS cnt FROM (SELECT DISTINCT `users`.* FROM `users`"
    .. " LEFT JOIN `posts` ON `posts`.`user_id` = `users`.`id`) AS t",
    "count with distinct + join selects the main table only")

adapter = fakeAdapter({ { { cnt = 3 } } })
users(adapter):leftJoin("posts", "posts.user_id", "users.id"):groupBy("users.job"):count()
assertEq(adapter.log[1].sql,
    "SELECT COUNT(*) AS cnt FROM (SELECT `users`.`job` FROM `users`"
    .. " LEFT JOIN `posts` ON `posts`.`user_id` = `users`.`id` GROUP BY `users`.`job`) AS t",
    "count with groupBy and a * select selects the group-by columns")

adapter = fakeAdapter({ { { cnt = 1 } }, {} })
users(adapter):select("job, COUNT(*) AS n"):having("n > ?", 2):paginate(1, 10)
assertEq(adapter.log[1].sql,
    "SELECT COUNT(*) AS cnt FROM (SELECT `job`, COUNT(*) AS n FROM `users` HAVING n > ?) AS t",
    "paginate with having and no groupBy counts through a derived table")
assertEq(adapter.log[1].params[1], 2, "paginate with having binds the having params in the count")

adapter = fakeAdapter({ { { val = 7 } } })
users(adapter):limit(5):offset(5):max("money")
assertEq(adapter.log[1].sql, "SELECT MAX(`money`) AS val FROM `users`", "aggregate ignores paging")

-- ─── #12/#15/#35 limit / offset validation ─────────────────────────

print("\n== limit() / offset() ==")

assertErrors(function() users():limit("1; DROP TABLE x") end, "limit rejects SQL strings")
assertErrors(function() users():limit(-1) end, "limit rejects negative numbers")
assertErrors(function() users():limit(1.5) end, "limit rejects non-integers")
assertErrors(function() users():offset("1 UNION SELECT 1") end, "offset rejects SQL strings")
assertErrors(function() users():offset(-5) end, "offset rejects negative numbers")
assertErrors(function() users():offset(2.5) end, "offset rejects non-integers")

sql = users():limit(10.0):offset("20"):toSQL()
assertContains(sql, "LIMIT 10 OFFSET 20", "limit/offset accept integral numbers and numeric strings")

sql = users():offset(10):toSQL()
assertContains(sql, "LIMIT 18446744073709551615 OFFSET 10", "offset without limit emits max LIMIT")

assertErrors(function() users():paginate(1, "15; DROP") end, "paginate rejects non-numeric perPage")

-- ─── #12 pluck on a qualified column ───────────────────────────────

print("\n== pluck() ==")

adapter = fakeAdapter({ { { id = 1 }, { id = 2 } } })
local ids = users(adapter):pluck("users.id")
assertEq(adapter.log[1].sql, "SELECT `users`.`id` FROM `users`", "pluck quotes qualified column")
assertEq(#ids, 2, "pluck qualified column returns values")
assertEq(ids[2], 2, "pluck qualified column reads unqualified key")

-- ─── #16 after() / before() direction validation ───────────────────

print("\n== after() / before() ==")

local payload = "ASC, (SELECT SLEEP(3))"
assertErrors(function() users():after("id", 1, payload) end, "after rejects invalid direction")
assertErrors(function() users():before("id", 1, payload) end, "before rejects invalid direction")
assertErrors(function() users():orderBy("id", payload) end, "orderBy rejects invalid direction")

sql = users():after("id", 5, "desc"):toSQL()
assertContains(sql, "`id` < ? ORDER BY `id` DESC", "after accepts lowercase desc")
sql = users():before("id", 5):toSQL()
assertContains(sql, "`id` < ? ORDER BY `id` ASC", "before defaults to ASC")

-- ─── #28 chunkById (keyset) ────────────────────────────────────────

print("\n== chunkById() ==")

adapter = fakeAdapter({
    { { id = 1 }, { id = 2 } },
    { { id = 5 }, { id = 9 } },
    { { id = 12 } },
})
local seen = {}
users(adapter):where({ job = "police" }):orWhere({ job = "medic" }):chunkById(2, function(rows, index)
    seen[#seen + 1] = index .. ":" .. #rows
end)
assertEq(table.concat(seen, ","), "1:2,2:2,3:1", "chunkById iterates every chunk")
assertEq(adapter.log[1].sql, "SELECT * FROM `users` WHERE `job` = ? OR `job` = ? ORDER BY `id` ASC LIMIT 2",
    "chunkById first chunk has no keyset condition")
assertEq(adapter.log[2].sql,
    "SELECT * FROM `users` WHERE `id` > ? AND (`job` = ? OR `job` = ?) ORDER BY `id` ASC LIMIT 2",
    "chunkById keyset condition is AND-ed outside user clauses")
assertEq(adapter.log[2].params[1], 2, "chunkById resumes after last key")
assertEq(adapter.log[3].params[1], 9, "chunkById advances the cursor")
assertNotContains(adapter.log[3].sql, "OFFSET", "chunkById never uses OFFSET")

adapter = fakeAdapter({ { { id = 1 }, { id = 2 } }, { { id = 3 } } })
local calls = 0
users(adapter):chunkById(2, function() calls = calls + 1 return false end)
assertEq(calls, 1, "chunkById stops when callback returns false")

assertErrors(function() users():chunkById(0, function() end) end, "chunkById rejects size 0")

adapter = fakeAdapter({ { { name = "x" }, { name = "y" } } })
assertErrors(function()
    users(adapter):chunkById(2, function() end, "id")
end, "chunkById errors when the key column is missing from results")

adapter = fakeAdapter({ { { id = 1 } } })
local chunked = users(adapter)
chunked:chunk(5, function() end)
assertEq(chunked:toSQL(), "SELECT * FROM `users`", "chunk does not leave paging on the builder")

-- ─── #41 consistent quoting / no double spaces ─────────────────────

print("\n== Identifier quoting ==")

sql = users()
    :where({ group = "vip" })
    :whereIn("key", { 1, 2 })
    :whereNotBetween("rank", 1, 3)
    :whereLike("desc", "%a%")
    :leftJoin("profiles", "profiles.user_id", "users.id")
    :orderBy("order", "DESC")
    :limit(3)
    :toSQL()
assertEq(sql,
    "SELECT * FROM `users` LEFT JOIN `profiles` ON `profiles`.`user_id` = `users`.`id`"
    .. " WHERE `group` = ? AND `key` IN (?, ?) AND `rank` NOT BETWEEN ? AND ? AND `desc` LIKE ?"
    .. " ORDER BY `order` DESC LIMIT 3",
    "builder quotes every identifier")
assertNotContains(sql, "  ", "builder SQL has no double spaces")

sql = users():whereNotInSub("id", "SELECT user_id FROM banned"):toSQL()
assertContains(sql, "`id` NOT IN (SELECT user_id FROM banned)", "whereNotInSub subquery kept verbatim")

sql, params = users():whereInSub("id", "SELECT user_id FROM active WHERE score > ?", { 100 }):toSQL()
assertContains(sql, "`id` IN (SELECT user_id FROM active WHERE score > ?)", "whereInSub subquery kept verbatim")
assertEq(params[1], 100, "whereInSub binds the subquery params")

-- whereIn values often come from client net events: a string must never be
-- spliced into the SQL as a subquery.
assertErrors(function() users():whereIn("id", "0) OR (1=1") end,
    "whereIn rejects a string (no implicit raw subquery)")
assertErrors(function() users():whereNotIn("id", "0) OR (1=1") end,
    "whereNotIn rejects a string (no implicit raw subquery)")
assertErrors(function() users():whereIn("id", 5) end, "whereIn rejects a non-table value")

sql = users():select("name, NULL, CURRENT_TIMESTAMP, true, Default"):toSQL()
assertEq(sql, "SELECT `name`, NULL, CURRENT_TIMESTAMP, true, Default FROM `users`",
    "select keeps SQL literals and niladic functions verbatim")

sql = users():select("id, COUNT(*) AS c"):groupBy("job, grade"):toSQL()
assertEq(sql, "SELECT `id`, COUNT(*) AS c FROM `users` GROUP BY `job`, `grade`",
    "select and groupBy quote plain identifiers only")

-- ─── #3 Query quotes column identifiers ────────────────────────────

print("\n== Query quoting ==")

local q = Query.insert("users", { group = "vip", key = "x" })
assertEq(q.sql, "INSERT INTO `users` (`group`, `key`) VALUES (?, ?)", "insert quotes columns")

q = Query.insertMany("users", { { group = "a" }, { group = "b" } })
assertEq(q.sql, "INSERT INTO `users` (`group`) VALUES (?), (?)", "insertMany quotes columns")

q = Query.select("users", { group = "vip" })
assertEq(q.sql, "SELECT * FROM `users` WHERE `group` = ?", "select quotes where columns")

q = Query.select("users", {}, "id, rank")
assertEq(q.sql, "SELECT `id`, `rank` FROM `users`", "select quotes column list")

q = Query.update("users", { rank = 2 }, { key = "x" })
assertEq(q.sql, "UPDATE `users` SET `rank` = ? WHERE `key` = ?", "update quotes columns")

q = Query.delete("users", { key = "x" })
assertEq(q.sql, "DELETE FROM `users` WHERE `key` = ?", "delete quotes columns")

q = Query.upsert("users", { key = "x", rank = 1 }, { rank = true })
assertEq(q.sql, "INSERT INTO `users` (`key`, `rank`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `rank` = VALUES(`rank`)",
    "upsert quotes columns")

q = Query.increment("users", "rank", 1, { key = "x" })
assertEq(q.sql, "UPDATE `users` SET `rank` = `rank` + ? WHERE `key` = ?", "increment quotes columns")

q = Query.selectJoin("roles", "user_roles", "role_id", "id", "user_id", 1)
assertEq(q.sql,
    "SELECT `roles`.* FROM `roles` INNER JOIN `user_roles` ON `user_roles`.`role_id` = `roles`.`id`"
    .. " WHERE `user_roles`.`user_id` = ?",
    "selectJoin quotes identifiers")

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
