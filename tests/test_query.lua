-- tests/test_query.lua
-- SQL generation of core.query (insert, select, update, delete, upsert, joins, increment).
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_query.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local T = require("tests.support.harness")

-- ─── Test: Query Builder ───────────────────────────────────────────

T.section("Query Builder")

local Query = require("core.query")

local q = Query.insert("users", { identifier = "license:abc", money = 500 })
T.match(q.sql, "INSERT INTO `users`", "INSERT SQL generated")
T.eq(#q.params, 2, "INSERT has 2 params")

q = Query.select("users", { identifier = "license:abc" })
T.match(q.sql, "SELECT %* FROM `users` WHERE", "SELECT SQL generated")

q = Query.update("users", { money = 1000 }, { identifier = "license:abc" })
T.match(q.sql, "UPDATE `users` SET", "UPDATE SQL generated")

q = Query.delete("users", { identifier = "license:abc" })
T.match(q.sql, "DELETE FROM `users` WHERE", "DELETE SQL generated")

q = Query.upsert("users", { identifier = "license:abc", money = 500 })
T.match(q.sql, "ON DUPLICATE KEY UPDATE", "UPSERT SQL generated")

q = Query.selectJoin("roles", "user_roles", "role_id", "id", "user_id", 1)
T.match(q.sql, "INNER JOIN `user_roles`", "selectJoin has INNER JOIN")

-- ─── Test: Query.insertMany ──────────────────────────────────────

T.section("Query.insertMany")

local qm = Query.insertMany("users", {
    { identifier = "a", money = 1 },
    { identifier = "b", money = 2 },
})
T.match(qm.sql, "INSERT INTO `users`", "insertMany: INSERT")
T.match(qm.sql, "VALUES %(", "insertMany: VALUES")
T.eq(#qm.params, 4, "insertMany: 4 params for 2 rows x 2 cols")

-- ─── Test: Query.increment / decrement ───────────────────────────

T.section("Query.increment / decrement")

local qi = Query.increment("users", "money", 500, { identifier = "abc" })
T.match(qi.sql, "`money` = `money` %+ %?", "Query.increment: SQL")
T.eq(qi.params[1], 500, "Query.increment: amount param")

local qd = Query.decrement("users", "money", 100, { identifier = "abc" })
T.match(qd.sql, "`money` = `money` %- %?", "Query.decrement: SQL")

T.finish()
