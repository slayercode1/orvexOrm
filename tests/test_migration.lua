-- tests/test_migration.lua
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_migration.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Migration = require("core.migration")

local passed, failed = 0, 0

local function check(condition, message)
    if condition then
        passed = passed + 1
        print("  ✓ " .. message)
    else
        failed = failed + 1
        print("  ✗ " .. message)
    end
end

local function contains(str, fragment)
    return type(str) == "string" and str:find(fragment, 1, true) ~= nil
end

local function indexOf(statements, fragment)
    for i, sql in ipairs(statements) do
        if contains(sql, fragment) then return i end
    end
    return nil
end

local function toSQL(build)
    local sb = Migration.SchemaBuilder.new()
    build(sb)
    return sb:toSQL()
end

-- Fake adapter: logs every statement, lets a test make one statement fail.
---@param opts? { failOn?: string, nilOn?: string, appliedRows?: table[], batch?: number }
local function fakeAdapter(opts)
    opts = opts or {}
    local adapter = { log = {} }

    function adapter:execute(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        if sql:match("MAX%(batch%)") then return { { batch = opts.batch or 0 } } end
        if sql:match("^SELECT name FROM orvex_migrations ORDER") then return opts.appliedRows or {} end
        if sql:match("WHERE batch") then return opts.appliedRows or {} end
        return {}
    end

    function adapter:scalar(sql, params)
        self.log[#self.log + 1] = { sql = sql, params = params }
        if opts.failOn and contains(sql, opts.failOn) then error("driver: syntax error near " .. opts.failOn) end
        if opts.nilOn and contains(sql, opts.nilOn) then return nil end
        return 1
    end

    function adapter:recorded(name)
        for _, entry in ipairs(self.log) do
            if entry.sql:match("^INSERT INTO orvex_migrations") and entry.params[1] == name then return true end
        end
        return false
    end

    function adapter:ran(fragment)
        for _, entry in ipairs(self.log) do
            if contains(entry.sql, fragment) then return true end
        end
        return false
    end

    return adapter
end

local function createTableMigration(name, tableName)
    return {
        name = name,
        up = function(schema) schema:create(tableName, function(t) t:id() end) end,
        down = function(schema) schema:drop(tableName) end,
    }
end

-- ─── #9: SchemaBuilder keeps call order ─────────────────────────────

print("\n== SchemaBuilder: statements in call order ==")

do
    local stmts = toSQL(function(sb)
        sb:dropIfExists("users")
        sb:create("users", function(t) t:id() end)
    end)
    check(#stmts == 2, "dropIfExists + create: 2 statements")
    check(contains(stmts[1], "DROP TABLE IF EXISTS `users`"), "dropIfExists runs first")
    check(contains(stmts[2], "CREATE TABLE IF NOT EXISTS `users`"), "create runs second")
end

do
    local stmts = toSQL(function(sb)
        sb:create("users", function(t) t:id() end)
        sb:raw("INSERT INTO users VALUES (1)")
        sb:drop("legacy")
    end)
    check(contains(stmts[1], "CREATE TABLE"), "create / raw / drop: create first")
    check(contains(stmts[2], "INSERT INTO users"), "create / raw / drop: raw second")
    check(contains(stmts[3], "DROP TABLE `legacy`"), "create / raw / drop: drop third")
end

print("\n== SchemaBuilder: table() appends instead of overwriting ==")

do
    local stmts = toSQL(function(sb)
        sb:table("users", function(t) t:string("a") end)
        sb:table("posts", function(t) t:string("b") end)
    end)
    local usersAt = indexOf(stmts, "ALTER TABLE `users` ADD COLUMN `a`")
    local postsAt = indexOf(stmts, "ALTER TABLE `posts` ADD COLUMN `b`")
    check(usersAt ~= nil, "first table() call kept")
    check(postsAt ~= nil, "second table() call kept")
    check(usersAt and postsAt and usersAt < postsAt, "table() calls keep call order")
end

do
    local stmts = toSQL(function(sb)
        sb:create("users", function(t) t:id() end)
        sb:table("users", function(t) t:string("email") end)
    end)
    check(#stmts == 2, "create + table in the same migration: 2 statements")
    check(contains(stmts[2], "ALTER TABLE `users` ADD COLUMN `email`"), "ADD COLUMN not skipped when create() is also used")
end

do
    local sb = Migration.SchemaBuilder.new()
    sb:drop("a")
    local first = sb:toSQL()
    first[#first + 1] = "tampered"
    check(#sb:toSQL() == 1, "toSQL returns a copy (caller mutations do not leak)")
end

print("\n== SchemaBuilder: index and foreign keys inside table() ==")

do
    local stmts = toSQL(function(sb)
        sb:table("users", function(t)
            t:integer("team_id")
            t:index("b")
            t:unique({ "email", "server" })
            t:foreignKey("team_id", "teams", "id", { onDelete = "set null" })
        end)
    end)
    check(indexOf(stmts, "ALTER TABLE `users` ADD INDEX `idx_b` (`b`)") ~= nil, "index() emits ADD INDEX")
    check(indexOf(stmts, "ALTER TABLE `users` ADD UNIQUE INDEX `uq_email_server` (`email`, `server`)") ~= nil, "unique() emits ADD UNIQUE INDEX")
    check(indexOf(stmts,
        "ALTER TABLE `users` ADD CONSTRAINT `fk_users_team_id` FOREIGN KEY (`team_id`) REFERENCES `teams` (`id`) ON DELETE SET NULL ON UPDATE CASCADE"
    ) ~= nil, "foreignKey() emits ADD CONSTRAINT")
    local addAt = indexOf(stmts, "ADD COLUMN `team_id`")
    local fkAt = indexOf(stmts, "ADD CONSTRAINT")
    check(addAt and fkAt and addAt < fkAt, "foreign key added after its column")
end

do
    local stmts = toSQL(function(sb)
        sb:table("logs", function(t) t:id() end)
    end)
    check(contains(stmts[1], "ADD COLUMN `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY"),
        "id() inside table() is added as PRIMARY KEY")
end

-- ─── #13: sync() without a declared primary key ─────────────────────

print("\n== generateCreateSQL: missing primary key ==")

do
    local sql = Migration.generateCreateSQL("things", { name = "string" }, "id")
    check(contains(sql, "`id` INT UNSIGNED NOT NULL AUTO_INCREMENT"), "missing PK column is injected as auto-increment")
    check(contains(sql, "PRIMARY KEY (`id`)"), "PRIMARY KEY still declared")
    check(sql:find("`id`", 1, true) < sql:find("`name`", 1, true), "injected PK is the first column")
end

do
    local sql = Migration.generateCreateSQL("users", { identifier = "string", money = "number" }, "identifier")
    local _, occurrences = sql:gsub("`identifier`", "")
    check(occurrences == 2, "declared PK is not injected twice (column + PRIMARY KEY)")
    check(not contains(sql, "AUTO_INCREMENT"), "declared string PK is left untouched")
end

do
    local adapter = fakeAdapter()
    Migration.sync("things", { name = "string" }, "id", adapter)
    check(contains(adapter.log[1].sql, "`id` INT UNSIGNED NOT NULL AUTO_INCREMENT"), "sync() sends the injected PK")
end

-- ─── String literals escape backslashes ─────────────────────────────
-- MySQL treats `\` as an escape in string literals: doubling quotes alone
-- lets a value ending in a backslash close the literal.

print("\n== DDL string literals ==")

do
    local sql = Migration.generateCreateSQL("things", {
        id = "number",
        label = { type = "string", default = [[x\' , evil INT -- ]] },
    }, "id")
    check(contains(sql, [[DEFAULT 'x\\'' , evil INT -- ']]), "default escapes backslash then quote")
end

do
    local sql = toSQL(function(sb)
        sb:create("things", function(t) t:enum("kind", { [[a\]], "b'c" }) end)
    end)[1]
    check(contains(sql, [[ENUM('a\\', 'b''c')]]), "enum values escape backslashes and quotes")
end

-- ─── #38: migrate() / rollback() surface failures ───────────────────

print("\n== migrate: success ==")

do
    local adapter = fakeAdapter()
    local count = Migration.migrate({
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(count == 2, "returns the number of applied migrations")
    check(adapter:recorded("001_a") and adapter:recorded("002_b"), "records every applied migration")
end

do
    local adapter = fakeAdapter({ appliedRows = { { name = "001_a" } }, batch = 1 })
    local count = Migration.migrate({
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(count == 1, "skips migrations already applied")
    check(not adapter:recorded("001_a"), "does not re-record an applied migration")
end

print("\n== migrate: failing statement ==")

do
    local adapter = fakeAdapter({ failOn = "`b`" })
    local ok, err = pcall(Migration.migrate, {
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
        createTableMigration("003_c", "c"),
    }, adapter)
    check(not ok, "raises when a statement fails")
    check(contains(tostring(err), "002_b"), "error names the failed migration")
    check(contains(tostring(err), "syntax error"), "error carries the driver message")
    check(contains(tostring(err), "1 migration(s) applied"), "error reports how many migrations were applied")
    check(adapter:recorded("001_a"), "previous migration stays recorded")
    check(not adapter:recorded("002_b"), "failed migration is NOT recorded")
    check(not adapter:ran("`c`"), "stops at the first failure")
end

do
    local adapter = fakeAdapter({ nilOn = "`b`" })
    local ok, err = pcall(Migration.migrate, { createTableMigration("002_b", "b") }, adapter)
    check(not ok, "raises when the driver returns no result (silent error)")
    check(contains(tostring(err), "002_b"), "silent error names the migration")
    check(not adapter:recorded("002_b"), "silently failed migration is NOT recorded")
end

do
    local adapter = fakeAdapter()
    local ok, err = pcall(Migration.migrate, {
        { name = "001_bad", up = function() error("boom in up") end, down = function() end },
    }, adapter)
    check(not ok, "raises when up() itself errors")
    check(contains(tostring(err), "boom in up"), "up() error message is surfaced")
    check(not adapter:recorded("001_bad"), "migration whose up() errors is NOT recorded")
end

print("\n== rollback: failing statement ==")

do
    local adapter = fakeAdapter({ appliedRows = { { name = "002_b" }, { name = "001_a" } }, batch = 1, failOn = "DROP TABLE `a`" })
    local ok, err = pcall(Migration.rollback, {
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(not ok, "rollback raises when down() fails")
    check(contains(tostring(err), "001_a"), "rollback error names the migration")
    check(adapter:ran("DELETE FROM orvex_migrations") and true, "successful rollback still un-recorded")
    local deletedA = false
    for _, entry in ipairs(adapter.log) do
        if entry.sql:match("^DELETE FROM orvex_migrations") and entry.params[1] == "001_a" then deletedA = true end
    end
    check(not deletedA, "failed rollback keeps the migration recorded")
end

do
    local adapter = fakeAdapter({ appliedRows = { { name = "002_b" }, { name = "001_a" } }, batch = 1 })
    local count = Migration.rollback({
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(count == 2, "rollback returns the number of rolled back migrations")
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
