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

-- Shared fake database: one in-memory `orvex_migrations` table that several
-- callers (resources) reach through their own adapter, like a real server.
---@param opts? { legacyRows?: { name: string, batch: number }[], failOn?: string, nilOn?: string }
local function sharedDatabase(opts)
    opts = opts or {}
    local db = {
        log = {},
        rows = {},
        nextId = 1,
        hasTable = opts.legacyRows ~= nil,
        hasResourceColumn = opts.legacyRows == nil,
    }
    for _, row in ipairs(opts.legacyRows or {}) do
        db.rows[#db.rows + 1] = { id = db.nextId, name = row.name, batch = row.batch }
        db.nextId = db.nextId + 1
    end

    local function copyRows()
        local out = {}
        for i, row in ipairs(db.rows) do
            out[i] = { id = row.id, name = row.name, batch = row.batch, resource = row.resource }
        end
        return out
    end

    local function findRow(name)
        for i, row in ipairs(db.rows) do
            if row.name == name then return i, row end
        end
    end

    local function execute(sql, params)
        if sql:find("information_schema", 1, true) then
            return db.hasResourceColumn and { { COLUMN_NAME = "resource" } } or {}
        end
        if sql:match("^SELECT id, name, batch, resource FROM orvex_migrations") then return copyRows() end
        return {}
    end

    local function scalar(sql, params)
        if opts.failOn and contains(sql, opts.failOn) then error("driver: syntax error near " .. opts.failOn) end
        if opts.nilOn and contains(sql, opts.nilOn) then return nil end
        if sql:match("^CREATE TABLE IF NOT EXISTS `orvex_migrations`") then
            if not db.hasTable then
                db.hasTable = true
                db.hasResourceColumn = contains(sql, "`resource`")
            end
            return 0
        end
        if sql:match("^ALTER TABLE `orvex_migrations` ADD COLUMN `resource`") then
            if db.hasResourceColumn then error("Duplicate column name 'resource'") end
            db.hasResourceColumn = true
            for _, row in ipairs(db.rows) do row.resource = "" end
            return 0
        end
        if sql:match("^INSERT INTO orvex_migrations") then
            if findRow(params[1]) then error("Duplicate entry for key 'name'") end
            db.rows[#db.rows + 1] = { id = db.nextId, name = params[1], batch = params[2], resource = params[3] }
            db.nextId = db.nextId + 1
            return db.nextId - 1
        end
        if sql:match("^DELETE FROM orvex_migrations") then
            local index, row = findRow(params[1])
            if not index or row.resource ~= params[2] then return 0 end
            table.remove(db.rows, index)
            return 1
        end
        return 1
    end

    --- Adapter for one caller; every call is logged in the shared log.
    function db:adapter()
        return {
            execute = function(_, sql, params)
                db.log[#db.log + 1] = { sql = sql, params = params }
                return execute(sql, params)
            end,
            scalar = function(_, sql, params)
                db.log[#db.log + 1] = { sql = sql, params = params }
                return scalar(sql, params)
            end,
        }
    end

    function db:row(name)
        local _, row = findRow(name)
        return row
    end

    function db:recorded(name) return self:row(name) ~= nil end

    function db:indexOf(fragment)
        for i, entry in ipairs(self.log) do
            if contains(entry.sql, fragment) then return i end
        end
        return nil
    end

    function db:ran(fragment) return self:indexOf(fragment) ~= nil end

    function db:count(fragment)
        local n = 0
        for _, entry in ipairs(self.log) do
            if contains(entry.sql, fragment) then n = n + 1 end
        end
        return n
    end

    return db
end

-- Compatibility shim for the single-caller tests below.
local function fakeAdapter(opts)
    local db = sharedDatabase(opts)
    local adapter = db:adapter()
    adapter.db = db
    function adapter:recorded(name) return db:recorded(name) end
    function adapter:ran(fragment) return db:ran(fragment) end
    return adapter
end

--- Seeds already-applied migrations in a resource-aware table.
local function seed(db, rows)
    for _, row in ipairs(rows) do
        db.hasTable = true
        db.rows[#db.rows + 1] = { id = db.nextId, name = row.name, batch = row.batch, resource = row.resource or "" }
        db.nextId = db.nextId + 1
    end
end

--- A separate copy of the module, as every FiveM resource loads its own.
local function loadMigrationInstance()
    package.loaded["core.migration"] = nil
    local instance = require("core.migration")
    package.loaded["core.migration"] = Migration
    return instance
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
    check(contains(adapter.db.log[1].sql, "`id` INT UNSIGNED NOT NULL AUTO_INCREMENT"), "sync() sends the injected PK")
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
    local adapter = fakeAdapter()
    seed(adapter.db, { { name = "001_a", batch = 1 } })
    local count = Migration.migrate({
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(count == 1, "skips migrations already applied")
    check(adapter.db:count("INSERT INTO orvex_migrations") == 1, "does not re-record an applied migration")
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
    local adapter = fakeAdapter({ failOn = "DROP TABLE `a`" })
    seed(adapter.db, { { name = "001_a", batch = 1 }, { name = "002_b", batch = 1 } })
    local ok, err = pcall(Migration.rollback, {
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(not ok, "rollback raises when down() fails")
    check(contains(tostring(err), "001_a"), "rollback error names the migration")
    check(adapter:ran("DELETE FROM orvex_migrations") and true, "successful rollback still un-recorded")
    local deletedA = false
    for _, entry in ipairs(adapter.db.log) do
        if entry.sql:match("^DELETE FROM orvex_migrations") and entry.params[1] == "001_a" then deletedA = true end
    end
    check(not deletedA, "failed rollback keeps the migration recorded")
end

do
    local adapter = fakeAdapter()
    seed(adapter.db, { { name = "001_a", batch = 1 }, { name = "002_b", batch = 1 } })
    local count = Migration.rollback({
        createTableMigration("001_a", "a"),
        createTableMigration("002_b", "b"),
    }, adapter)
    check(count == 2, "rollback returns the number of rolled back migrations")
end

-- ─── Rollback scope: one caller never undoes another's migrations ───

print("\n== two resources sharing orvex_migrations ==")

do
    local db = sharedDatabase()
    local shops, bank = loadMigrationInstance(), loadMigrationInstance()
    local shopsList = { createTableMigration("a_create_shops", "shops") }
    local bankList = { createTableMigration("b_create_bank", "bank") }

    shops.migrate(shopsList, db:adapter(), "res_shops")
    bank.migrate(bankList, db:adapter(), "res_bank")
    check(db:row("a_create_shops").resource == "res_shops", "migrate records the caller's resource")
    check(db:row("a_create_shops").batch ~= db:row("b_create_bank").batch, "two migrate() calls get distinct batches")

    local count = shops.rollback(shopsList, db:adapter(), "res_shops")
    check(count == 1, "rollback counts the caller's own migration")
    check(db:ran("DROP TABLE `shops`"), "rollback runs the caller's down, not the newest global batch")
    check(not db:ran("DROP TABLE `bank`"), "rollback never runs another resource's down")
    check(not db:recorded("a_create_shops"), "caller's tracking row is deleted")
    check(db:recorded("b_create_bank"), "other resource's tracking row is kept")

    check(bank.migrate(bankList, db:adapter(), "res_bank") == 0, "other resource does not re-run its up afterwards")
    check(bank.rollback(bankList, db:adapter(), "res_bank") == 1, "other resource can still roll back its own batch")
    check(not db:recorded("b_create_bank"), "other resource's rollback deletes its own row")
end

do
    local db = sharedDatabase()
    local mig = loadMigrationInstance()
    mig.migrate({ createTableMigration("001_a", "a") }, db:adapter(), "res_a")
    check(mig.rollback({ createTableMigration("009_z", "z") }, db:adapter(), "res_b") == 0,
        "rollback with nothing of the caller's recorded returns 0")
    check(db:recorded("001_a"), "rollback with nothing of the caller's recorded deletes nothing")
    check(not db:ran("DELETE FROM orvex_migrations"), "no DELETE is sent when nothing belongs to the caller")
end

do
    local db = sharedDatabase()
    local mig = loadMigrationInstance()
    mig.migrate({ createTableMigration("001_a", "a"), createTableMigration("002_b", "b") }, db:adapter(), "res_a")
    local count = mig.rollback({ createTableMigration("002_b", "b") }, db:adapter(), "res_a")
    check(count == 1, "rollback counts only migrations whose down ran")
    check(db:recorded("001_a"), "rollback keeps rows whose name is not in the caller's list")
    check(not db:ran("DROP TABLE `a`"), "a migration missing from the list is not rolled back")
end

print("\n== migration names already recorded by another resource ==")

do
    local db = sharedDatabase()
    local a, c = loadMigrationInstance(), loadMigrationInstance()
    a.migrate({ createTableMigration("create_users", "a_users") }, db:adapter(), "res_a")
    local ok, err = pcall(c.migrate, {
        createTableMigration("c_first", "c_first"),
        createTableMigration("create_users", "c_users"),
    }, db:adapter(), "res_c")
    check(not ok, "a name recorded by another resource is rejected, not silently skipped")
    check(contains(tostring(err), "create_users") and contains(tostring(err), "res_a"),
        "conflict error names the migration and the owning resource")
    check(not db:ran("`c_first`") and not db:ran("`c_users`"), "no migration runs when the list has a conflict")
    check(db:row("create_users").resource == "res_a", "the owner's tracking row is untouched")
end

print("\n== legacy orvex_migrations without a resource column ==")

do
    local db = sharedDatabase({ legacyRows = { { name = "001_a", batch = 1 } } })
    local mig = loadMigrationInstance()
    local list = { createTableMigration("001_a", "a"), createTableMigration("002_b", "b") }
    local count = mig.migrate(list, db:adapter(), "res_a")
    check(db:count("ADD COLUMN `resource`") == 1, "missing resource column is added")
    check(db:row("001_a").resource == "", "legacy rows keep an empty resource")
    check(count == 1 and not db:ran("CREATE TABLE IF NOT EXISTS `a`"), "legacy row still counts as applied")
    check(db:row("002_b").resource == "res_a", "new row records the resource")

    mig.migrate(list, db:adapter(), "res_a")
    check(db:count("ADD COLUMN `resource`") == 1, "resource column is added only once")

    check(mig.rollback(list, db:adapter(), "res_a") == 1 and db:recorded("001_a"), "rollback undoes the newest batch first")
    check(mig.rollback(list, db:adapter(), "res_a") == 1 and not db:recorded("001_a"),
        "legacy row is rolled back by a caller that lists it")
end

do
    local db = sharedDatabase({ legacyRows = { { name = "001_a", batch = 1 } } })
    local mig = loadMigrationInstance()
    check(mig.rollback({ createTableMigration("009_z", "z") }, db:adapter(), "res_x") == 0 and db:recorded("001_a"),
        "legacy row is not rolled back by a caller that does not list it")
end

do
    local db = sharedDatabase()
    Migration.migrate({ createTableMigration("001_a", "a") }, db:adapter(), "res_a")
    check(not db:ran("ADD COLUMN `resource`"), "a fresh tracking table already has the resource column")
end

print("\n== resource name defaults to GetCurrentResourceName() ==")

do
    local db = sharedDatabase()
    GetCurrentResourceName = function() return "res_current" end
    Migration.migrate({ createTableMigration("001_a", "a") }, db:adapter())
    GetCurrentResourceName = nil
    check(db:row("001_a").resource == "res_current", "migrate() without a resource uses the current resource")
    check(Migration.rollback({ createTableMigration("001_a", "a") }, db:adapter()) == 0,
        "outside FiveM the fallback resource does not own another resource's rows")
end

print("\n== tracking writes are checked ==")

do
    local db = sharedDatabase({ nilOn = "INSERT INTO orvex_migrations" })
    local ok, err = pcall(Migration.migrate, { createTableMigration("001_a", "a") }, db:adapter(), "res_a")
    check(not ok, "migrate raises when the tracking INSERT returns no result")
    check(contains(tostring(err), "001_a") and contains(tostring(err), "record"),
        "unrecorded migration error names the migration")
end

do
    local db = sharedDatabase({ nilOn = "DELETE FROM orvex_migrations" })
    seed(db, { { name = "001_a", batch = 1, resource = "res_a" } })
    local ok, err = pcall(Migration.rollback, { createTableMigration("001_a", "a") }, db:adapter(), "res_a")
    check(not ok, "rollback raises when the tracking DELETE returns no result")
    check(contains(tostring(err), "001_a"), "undeleted tracking row error names the migration")
end

do
    local db = sharedDatabase({ nilOn = "CREATE TABLE IF NOT EXISTS `orvex_migrations`" })
    local ok = pcall(Migration.migrate, { createTableMigration("001_a", "a") }, db:adapter(), "res_a")
    check(not ok, "migrate raises when the tracking table cannot be created")
end

-- ─── columnToSQL DEFAULT values ─────────────────────────────────────

print("\n== columnToSQL DEFAULT ==")

do
    check(contains(Migration.columnToSQL("n", { type = "number", default = 5 }), "DEFAULT 5"), "integer default")
    check(contains(Migration.columnToSQL("n", { type = "number", default = 1.5 }), "DEFAULT 1.5"), "float default")
    check(contains(Migration.columnToSQL("b", { type = "boolean", default = false }), "DEFAULT 0"), "boolean default")
    local spliced = setmetatable({}, { __tostring = function() return "0, evil INT" end })
    local rejected = {
        { spliced, "table with __tostring" },
        { math.huge, "infinity" },
        { -math.huge, "negative infinity" },
        { 0 / 0, "NaN" },
        { print, "function" },
    }
    for _, case in ipairs(rejected) do
        local ok, err = pcall(Migration.columnToSQL, "n", { type = "number", default = case[1] })
        check(not ok and contains(tostring(err), "DEFAULT"), "rejects a " .. case[2] .. " default")
    end
end

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
