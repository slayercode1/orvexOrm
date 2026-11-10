-- tests/test_core_model_relations.lua
-- Regression tests for model CRUD helpers, relations and nested writes.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_core_model_relations.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

-- ─── Mock FiveM globals ────────────────────────────────────────────

json = {
    encode = function(t) return tostring(t) end,
    decode = function(s) return s end,
}

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
    str = tostring(str)
    report(str:find(fragment, 1, true) ~= nil, msg, ("'%s' does not contain '%s'"):format(str, fragment))
end

local function assertNotContains(str, fragment, msg)
    str = tostring(str)
    report(str:find(fragment, 1, true) == nil, msg, ("'%s' unexpectedly contains '%s'"):format(str, fragment))
end

local function assertErrors(fn, msg)
    local ok = pcall(fn)
    report(not ok, msg, "expected an error, none raised")
end

local function keyCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- Adapter double: logs every statement, replays queued SELECT results,
--- hands out increasing insert ids and records transaction batches.
local function fakeAdapter()
    local adapter = { log = {}, queue = {}, transactions = {}, nextId = 1, transactionResult = true }
    function adapter:execute(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        return table.remove(self.queue, 1) or {}
    end
    function adapter:scalar(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        if sql:match("^INSERT") then
            local id = self.nextId
            self.nextId = id + 1
            return id
        end
        return 1
    end
    function adapter:transaction(queries)
        self.transactions[#self.transactions + 1] = queries
        return self.transactionResult
    end
    function adapter:reset()
        self.log, self.queue, self.transactions = {}, {}, {}
        self.nextId, self.transactionResult = 1, true
    end
    return adapter
end

local ORM = require("core.orm")
local Query = require("core.query")

local db = fakeAdapter()

local User = ORM.model("users", {
    id = "number", name = "string", job = "string", group = "string",
}, { adapter = db })

local Profile = ORM.model("profiles", {
    id = "number", user_id = "number", bio = "string",
}, { adapter = db })

local Post = ORM.model("posts", {
    id = "number", user_id = "number", title = "string",
    created_at = "datetime", updated_at = "datetime",
}, { adapter = db, softDelete = true, timestamps = true })

local Role = ORM.model("roles", {
    id = "number", name = "string",
}, { adapter = db, softDelete = true })

User.hasOne("profile", Profile, { foreignKey = "user_id" })
User.hasMany("posts", Post, { foreignKey = "user_id" })
User.belongsToMany("roles", Role, { pivot = "role_user", foreignKey = "user_id", otherKey = "role_id" })
Post.belongsTo("author", User, { foreignKey = "user_id" })

-- ─── #0 relations with a nil key do not query ──────────────────────

print("\n== #0 relations with a nil key ==")

db:reset()
local orphan = Post._wrapRow({ id = 1, title = "orphan" })
assertEq(orphan:get("author"), nil, "belongsTo with nil foreign key returns nil")
assertEq(#db.log, 0, "belongsTo with nil foreign key runs no query")

local ghost = User._wrapRow({ name = "ghost" })
assertEq(ghost:get("profile"), nil, "hasOne with nil local key returns nil")
assertEq(#ghost:get("posts"), 0, "hasMany with nil local key returns {}")
assertEq(#ghost:get("roles"), 0, "belongsToMany with nil local key returns {}")
assertEq(#db.log, 0, "relations with nil local key run no query")

db:reset()
db.queue = { { { id = 7, title = "orphan" } } }
local eagerOrphan = Post.find({ id = 7 }, { include = { "author" } })
assertEq(eagerOrphan.author, nil, "eager include with nil foreign key attaches nothing")
assertEq(#db.log, 1, "eager include with nil foreign key runs no extra query")

-- ─── #6 / #23 Model.find with operators and LIMIT 1 ────────────────

print("\n== #6 / #23 Model.find ==")

db:reset()
User.find({ id = { ">", 5 } })
assertContains(db.log[1].sql, "`id` > ?", "find with operator value emits the operator")
assertEq(db.log[1].params[1], 5, "find with operator value binds the scalar")
assertEq(type(db.log[1].params[1]), "number", "find never binds a Lua table")

db:reset()
User.find({ job = "police" })
assertEq(db.log[1].sql, "SELECT * FROM `users` WHERE `job` = ? LIMIT 1", "find fast path fetches one row")

db:reset()
Post.find({ user_id = 1 })
assertContains(db.log[1].sql, "LIMIT 1", "softDelete find fetches one row")

local q = Query.select("users", { id = 1 }, "*", 1)
assertEq(q.sql, "SELECT * FROM `users` WHERE `id` = ? LIMIT 1", "Query.select accepts a limit")
assertErrors(function() Query.select("users", {}, "*", "1; DROP TABLE users") end, "Query.select rejects a non-integer limit")

-- ─── #17 findOpts.select identifiers ───────────────────────────────

print("\n== #17 findOpts.select ==")

assertErrors(function()
    User.find({ id = 1 }, { select = { "id, (SELECT GROUP_CONCAT(name) FROM users) AS id" } })
end, "find rejects an expression in select")
assertErrors(function()
    User.findAll({}, { select = { "name FROM users; --" } })
end, "findAll rejects an expression in select")

db:reset()
User.find({ id = 1 }, { select = { "name", "group" } })
assertEq(db.log[1].sql, "SELECT `name`, `group`, `id` FROM `users` WHERE `id` = ? LIMIT 1",
    "select entries are quoted and the primary key is added")

-- ─── #11 / #39 caller input is never mutated ───────────────────────

print("\n== #11 / #39 caller input ==")

db:reset()
local template = { title = "hello" }
Post.create(template)
assertEq(keyCount(template), 1, "create leaves the caller's table unchanged")
Post.create(template)
assertNotContains(db.log[2].sql, "`id`", "reusing a template does not insert the previous id")

local rows = { { title = "a" }, { title = "b" } }
Post.createMany(rows)
assertEq(keyCount(rows[1]), 1, "createMany leaves the caller's rows unchanged")

local upsertData = { id = 1, title = "x" }
Post.upsert(upsertData)
assertEq(keyCount(upsertData), 2, "upsert leaves the caller's table unchanged")

local updateData = { title = "y" }
Post.update(updateData, { id = 1 })
assertEq(keyCount(updateData), 1, "Model.update leaves the caller's table unchanged")

local post = Post._wrapRow({ id = 1, title = "x" })
local instanceData = { title = "z" }
post:update(instanceData)
assertEq(keyCount(instanceData), 1, "Instance:update leaves the caller's table unchanged")
assertEq(post.updated_at ~= nil, true, "Instance:update still stamps the instance")

db:reset()
local u = User._wrapRow({ id = 1, name = "a" })
u:update({ id = 2 })
u:update({ name = "b" })
assertEq(db.log[2].sql, "UPDATE `users` SET `name` = ? WHERE `id` = ?", "update after a PK change targets the row")
assertEq(db.log[2].params[2], 2, "update after a PK change uses the new primary key")

-- ─── #37 restore ───────────────────────────────────────────────────

print("\n== #37 restore ==")

q = Query.restore("posts", { id = 3 })
assertEq(q.sql, "UPDATE `posts` SET `deleted_at` = NULL WHERE `id` = ?", "Query.restore builds the statement")
assertEq(q.params[1], 3, "Query.restore binds the where values")
assertErrors(function() Query.restore("posts", {}) end, "Query.restore rejects an empty where")
assertErrors(function() Post.restore({}) end, "Model.restore rejects an empty where")
assertErrors(function() Post.restore(nil) end, "Model.restore rejects a nil where")

db:reset()
Post.restore({ id = 3 })
assertEq(db.log[1].sql, "UPDATE `posts` SET `deleted_at` = NULL WHERE `id` = ?", "Model.restore runs the statement")

db:reset()
local trashed = Post._wrapRow({ id = 4, deleted_at = "2024-01-01 00:00:00" })
trashed:restore()
assertEq(db.log[1].sql, "UPDATE `posts` SET `deleted_at` = NULL WHERE `id` = ?", "Instance:restore runs the statement")
assertEq(db.log[1].params[1], 4, "Instance:restore targets its row")
assertEq(trashed.deleted_at, nil, "Instance:restore clears deleted_at")
assertErrors(function() User._wrapRow({ id = 1 }):restore() end, "restore requires soft delete")

-- ─── #7 whereHas / countByRelation ─────────────────────────────────

print("\n== #7 whereHas / countByRelation ==")

local sql = User.whereHas("roles", function(b) b:where("name", "admin") end):toSQL()
assertContains(sql, "EXISTS (SELECT 1 FROM `roles` INNER JOIN `role_user` ON `role_user`.`role_id` = `roles`.`id`",
    "whereHas belongsToMany joins the pivot to the related table")
assertContains(sql, "`role_user`.`user_id` = `users`.`id`", "whereHas belongsToMany correlates the pivot")
assertContains(sql, "`roles`.`deleted_at` IS NULL", "whereHas belongsToMany skips trashed related rows")
assertContains(sql, "`name` = ?", "whereHas belongsToMany applies the callback to the related table")

sql = User.whereHas("posts"):toSQL()
assertContains(sql, "`posts`.`deleted_at` IS NULL AND `posts`.`user_id` = `users`.`id`",
    "whereHas hasMany skips trashed related rows")

sql = User.whereHas("profile"):toSQL()
assertNotContains(sql, "deleted_at", "whereHas without related softDelete adds no filter")

sql = Post.whereHas("author"):toSQL()
assertContains(sql, "`users`.`id` = `posts`.`user_id`", "whereHas belongsTo correlates the owner key")

db:reset()
db.queue = { { { id = 1 }, { id = 2 } }, { { fk = 1, cnt = 2 } } }
local counts = User.countByRelation("posts")
assertEq(db.log[2].sql,
    "SELECT `posts`.`user_id` AS fk, COUNT(*) AS cnt FROM `posts` WHERE `posts`.`deleted_at` IS NULL"
    .. " AND `posts`.`user_id` IN (?, ?) GROUP BY `posts`.`user_id`",
    "countByRelation skips trashed related rows")
assertEq(counts[1].count, 2, "countByRelation maps counts to instances")
assertEq(counts[2].count, 0, "countByRelation defaults to 0")

db:reset()
db.queue = { { { id = 1 } }, { { fk = 1, cnt = 3 } } }
counts = User.countByRelation("roles")
assertContains(db.log[2].sql, "INNER JOIN `role_user` ON `role_user`.`role_id` = `roles`.`id`",
    "countByRelation belongsToMany joins the related table")
assertContains(db.log[2].sql, "`roles`.`deleted_at` IS NULL", "countByRelation belongsToMany skips trashed rows")
assertEq(counts[1].count, 3, "countByRelation belongsToMany counts")

-- ─── #26 belongsToMany eager loading in one query ──────────────────

print("\n== #26 belongsToMany eager loading ==")

db:reset()
db.queue = {
    { { id = 1 }, { id = 2 }, { id = 3 } },
    {
        { id = 10, name = "admin", __pivot_fk = 1 },
        { id = 11, name = "mod", __pivot_fk = 1 },
        { id = 10, name = "admin", __pivot_fk = 2 },
    },
}
local loaded = User.findAll({}, { include = { "roles" } })
assertEq(#db.log, 2, "belongsToMany include runs a single query")
assertContains(db.log[2].sql, "SELECT `roles`.*, `role_user`.`user_id` AS __pivot_fk FROM `roles`",
    "belongsToMany include selects the pivot key")
assertContains(db.log[2].sql, "`role_user`.`user_id` IN (?, ?, ?)", "belongsToMany include batches the keys")
assertContains(db.log[2].sql, "`roles`.`deleted_at` IS NULL", "belongsToMany include skips trashed roles")
assertEq(#loaded[1].roles, 2, "first user gets both roles")
assertEq(#loaded[2].roles, 1, "second user gets its role")
assertEq(#loaded[3].roles, 0, "user without roles gets {}")
assertEq(loaded[1].roles[1].__pivot_fk, nil, "pivot key is stripped from related rows")
assertEq(loaded[1].roles[1].name, "admin", "related rows are wrapped")
assertEq(type(loaded[1].roles[1].toTable), "function", "related rows are instances")

db:reset()
db.queue = { { { id = 5, name = "r" } } }
local lazyRoles = User._wrapRow({ id = 1 }):get("roles")
assertContains(db.log[1].sql, "`role_user`.`user_id` = ?", "lazy belongsToMany filters on the pivot key")
assertContains(db.log[1].sql, "`roles`.`deleted_at` IS NULL", "lazy belongsToMany skips trashed roles")
assertEq(lazyRoles[1].name, "r", "lazy belongsToMany wraps rows")

-- ─── #31 createWith batches nested rows in one transaction ─────────

print("\n== #31 createWith ==")

db:reset()
local created = User.createWith({
    name = "alice",
    profile = { bio = "hi" },
    posts = { { title = "p1" }, { title = "p2" } },
})
assertEq(created.id, 1, "createWith returns the parent with its id")
assertEq(#db.log, 1, "createWith only inserts the parent outside the transaction")
assertEq(#db.transactions, 1, "createWith writes children in one transaction")

local txSQL = {}
for i, tq in ipairs(db.transactions[1]) do txSQL[i] = tq.query end
local joined = table.concat(txSQL, "\n")
assertContains(joined, "INSERT INTO `posts` (`created_at`, `title`, `updated_at`, `user_id`) VALUES (?, ?, ?, ?), (?, ?, ?, ?)",
    "hasMany children use one multi-row insert")
assertContains(joined, "INSERT INTO `profiles` (`bio`, `user_id`) VALUES (?, ?)", "hasOne child is in the transaction")

db:reset()
User.createWith({ name = "bob", roles = { { name = "a" }, { name = "b" } } })
assertEq(#db.transactions, 1, "belongsToMany pivot rows are written in one transaction")
assertEq(db.transactions[1][1].query, "INSERT INTO `role_user` (`role_id`, `user_id`) VALUES (?, ?), (?, ?)",
    "belongsToMany pivot rows use one multi-row insert")

db:reset()
assertErrors(function()
    User.createWith({ name = "carol", posts = { { title = 42 } } })
end, "createWith validates children before writing")
assertEq(#db.log, 0, "invalid child data writes nothing")

db:reset()
db.transactionResult = false
assertErrors(function()
    User.createWith({ name = "dave", posts = { { title = "p" } } })
end, "createWith raises when the transaction fails")
assertContains(db.log[#db.log].sql, "DELETE FROM `users` WHERE `id` = ?", "a failed transaction removes the parent")

db:reset()
local plain = User.createWith({ name = "erin" })
assertEq(plain.name, "erin", "createWith without nested data still creates")
assertEq(#db.transactions, 0, "createWith without nested data opens no transaction")

-- A compensating DELETE that fails must be reported, not mask the cause.
db:reset()
db.transactionResult = false
local scalar = db.scalar
function db:scalar(sql, params)
    if sql:match("^DELETE") then error("connection lost") end
    return scalar(self, sql, params)
end
local cleanupError
pcall(function()
    local ok, err = pcall(User.createWith, { name = "fay", posts = { { title = "p" } } })
    cleanupError = not ok and tostring(err) or nil
end)
db.scalar = scalar
assertContains(cleanupError, "transaction failed", "createWith reports the original failure")
assertContains(cleanupError, "connection lost", "createWith reports a failed compensating delete")
assertContains(cleanupError, "users", "createWith names the row left behind")

-- ─── createWith fires the child model hooks ────────────────────────

print("\n== createWith child hooks ==")

local seenBefore, seenBulk = {}, {}
Post.beforeCreate(function(data)
    seenBefore[#seenBefore + 1] = data.user_id
    data.title = data.title .. "!"
end)
Post.afterBulkCreate(function(rows) seenBulk[#seenBulk + 1] = #rows end)

db:reset()
local childTemplate = { title = "x" }
User.createWith({ name = "gus", posts = { childTemplate, { title = "y" } } })
assertEq(#seenBefore, 2, "createWith fires beforeCreate on every child row")
assertEq(seenBefore[1], 1, "child beforeCreate sees the parent foreign key")
assertEq(#seenBulk, 1, "createWith fires afterBulkCreate once per child relation")
assertEq(seenBulk[1], 2, "afterBulkCreate receives every child row")
assertEq(childTemplate.title, "x", "child hooks work on copies of the caller's rows")
local postInsert = db.transactions[1][1]
assertContains(table.concat(postInsert.values, ","), "x!", "beforeCreate changes reach the insert")

db:reset()
db.transactionResult = false
seenBulk = {}
pcall(User.createWith, { name = "hal", posts = { { title = "z" } } })
assertEq(#seenBulk, 0, "afterBulkCreate does not fire when the transaction fails")

-- ─── attach / detach refuse a nil key ──────────────────────────────

print("\n== attach / detach with a nil key ==")

db:reset()
local keyless = User._wrapRow({ name = "nokey" })
local role = Role._wrapRow({ id = 7, name = "admin" })
assertErrors(function() keyless:detach("roles", role) end, "detach refuses a parent without key")
assertErrors(function() keyless:attach("roles", role) end, "attach refuses a parent without key")
local keyed = User._wrapRow({ id = 3, name = "key" })
assertErrors(function() keyed:detach("roles", { name = "x" }) end, "detach refuses a related row without key")
assertErrors(function() keyed:attach("roles", { name = "x" }) end, "attach refuses a related row without key")
assertEq(#db.log, 0, "attach / detach with a nil key run no query")

keyed:detach("roles", role)
assertEq(db.log[1].sql, "DELETE FROM `role_user` WHERE `role_id` = ? AND `user_id` = ?",
    "detach with both keys deletes one link")

-- ─── findOpts.select as a string ───────────────────────────────────

print("\n== findOpts.select string ==")

db:reset()
User.findAll({}, { select = "name, job" })
assertEq(db.log[1].sql, "SELECT `name`, `job`, `id` FROM `users`", "select accepts a comma-separated string")
assertErrors(function() User.findAll({}, { select = "name, (SELECT 1) AS x" }) end,
    "select string entries must be plain identifiers")
assertErrors(function() User.findAll({}, { select = 42 }) end, "select rejects a non-string, non-table value")

-- ─── Summary ───────────────────────────────────────────────────────

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
if failed > 0 then os.exit(1) end
