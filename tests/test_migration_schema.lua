-- tests/test_migration_schema.lua
-- Schema builder, column mapping, Model.sync() and ORM.migrate().
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_migration_schema.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults = Mock.log, Mock.results
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

-- ─── Test: Migrations ─────────────────────────────────────────────

T.section("Migrations")

local MigrationLib = require("core.migration")

-- Test type mapping
T.eq(MigrationLib.TYPE_MAP["string"], "VARCHAR(255)", "type map: string → VARCHAR(255)")
T.eq(MigrationLib.TYPE_MAP["number"], "INT", "type map: number → INT")
T.eq(MigrationLib.TYPE_MAP["boolean"], "TINYINT(1)", "type map: boolean → TINYINT(1)")
T.eq(MigrationLib.TYPE_MAP["json"], "JSON", "type map: json → JSON")
T.eq(MigrationLib.TYPE_MAP["auto"], "TEXT", "type map: auto → TEXT")

-- Test columnToSQL
local colSQL = MigrationLib.columnToSQL("name", "string", false)
T.match(colSQL, "`name` VARCHAR%(255%)", "columnToSQL: string column")
T.match(colSQL, "NULL", "columnToSQL: nullable by default")

local pkSQL = MigrationLib.columnToSQL("id", "number", true)
T.match(pkSQL, "`id` INT", "columnToSQL: number PK")
T.match(pkSQL, "NOT NULL", "columnToSQL: PK is NOT NULL")
T.match(pkSQL, "AUTO_INCREMENT", "columnToSQL: number PK has AUTO_INCREMENT")

-- Test extended column definition
local extSQL = MigrationLib.columnToSQL("identifier", { type = "string", length = 60 }, true)
T.match(extSQL, "VARCHAR%(60%)", "columnToSQL: extended with custom length")
T.match(extSQL, "NOT NULL", "columnToSQL: extended PK is NOT NULL")

-- Test generateCreateSQL
local createSQL = MigrationLib.generateCreateSQL("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, "identifier")
T.match(createSQL, "CREATE TABLE IF NOT EXISTS `users`", "generateCreateSQL: has CREATE TABLE")
T.match(createSQL, "PRIMARY KEY %(`identifier`%)", "generateCreateSQL: has PRIMARY KEY")
T.match(createSQL, "`money` INT", "generateCreateSQL: number column")
T.match(createSQL, "`job` VARCHAR%(255%)", "generateCreateSQL: string column")

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
T.eq(#stmts, 1, "SchemaBuilder create: 1 statement")
T.match(stmts[1], "CREATE TABLE IF NOT EXISTS `players`", "SchemaBuilder create: CREATE TABLE")
T.match(stmts[1], "`id` INT UNSIGNED NOT NULL AUTO_INCREMENT", "SchemaBuilder create: id column")
T.match(stmts[1], "`name` VARCHAR%(100%)", "SchemaBuilder create: string with length")
T.match(stmts[1], "PRIMARY KEY %(`id`%)", "SchemaBuilder create: PRIMARY KEY")

-- Test SchemaBuilder - drop table
local sb2 = MigrationLib.SchemaBuilder.new()
sb2:drop("old_table")
local stmts2 = sb2:toSQL()
T.eq(#stmts2, 1, "SchemaBuilder drop: 1 statement")
T.match(stmts2[1], "DROP TABLE `old_table`", "SchemaBuilder drop: DROP TABLE")

-- Test SchemaBuilder - dropIfExists
local sb3 = MigrationLib.SchemaBuilder.new()
sb3:dropIfExists("maybe_table")
local stmts3 = sb3:toSQL()
T.match(stmts3[1], "DROP TABLE IF EXISTS `maybe_table`", "SchemaBuilder dropIfExists")

-- Test SchemaBuilder - alter table
local sb4 = MigrationLib.SchemaBuilder.new()
sb4:table("users", function(t)
    t:string("email", 255)
    t:dropColumn("old_col")
    t:renameColumn("name", "full_name")
end)
local stmts4 = sb4:toSQL()
T.eq(#stmts4, 3, "SchemaBuilder alter: 3 statements (add + drop + rename)")
T.match(stmts4[1], "ALTER TABLE `users` ADD COLUMN", "SchemaBuilder alter: ADD COLUMN")
T.match(stmts4[2], "DROP COLUMN `old_col`", "SchemaBuilder alter: DROP COLUMN")
T.match(stmts4[3], "RENAME COLUMN `name` TO `full_name`", "SchemaBuilder alter: RENAME COLUMN")

-- Test Model.sync()
reset()
local SyncUser = ORM.model("sync_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })
SyncUser.sync()
T.eq(#dbLog, 1, "Model.sync: executes 1 SQL query")
T.match(dbLog[1].sql, "CREATE TABLE IF NOT EXISTS `sync_users`", "Model.sync: runs CREATE TABLE")

-- Test ORM.migrate() and ORM.rollback()
reset()
mockResults[1] = {} -- ensureTrackingTable (CREATE TABLE)
mockResults[2] = { { COLUMN_NAME = "resource" } } -- resource column already there
mockResults[3] = {} -- tracking rows → none applied

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
T.eq(migCount, 1, "ORM.migrate: ran 1 migration")
-- Find the CREATE TABLE statement in logs
local foundCreate = false
for _, entry in ipairs(dbLog) do
    if entry.sql:match("CREATE TABLE IF NOT EXISTS `items`") then
        foundCreate = true
        break
    end
end
T.eq(foundCreate, true, "ORM.migrate: executed CREATE TABLE for items")

-- Find the INSERT into tracking table
local foundInsert = false
for _, entry in ipairs(dbLog) do
    if entry.sql:match("INSERT INTO orvex_migrations") then
        foundInsert = true
        break
    end
end
T.eq(foundInsert, true, "ORM.migrate: recorded migration in tracking table")

-- Test TableBuilder column types
local tb = MigrationLib.TableBuilder.new()
tb:float("price")
tb:double("coordinates")
tb:text("description")
tb:bigInteger("big_num")
tb:datetime("event_date")
tb:primaryString("code", 30)

T.eq(#tb._columns, 6, "TableBuilder: all 6 columns created")
T.match(tb._columns[1].sql, "FLOAT", "TableBuilder: float column")
T.match(tb._columns[2].sql, "DOUBLE", "TableBuilder: double column")
T.match(tb._columns[3].sql, "TEXT", "TableBuilder: text column")
T.match(tb._columns[4].sql, "BIGINT", "TableBuilder: bigInteger column")
T.match(tb._columns[5].sql, "DATETIME", "TableBuilder: datetime column")
T.match(tb._columns[6].sql, "VARCHAR%(30%)", "TableBuilder: primaryString with length")
T.eq(tb._columns[6].primary, true, "TableBuilder: primaryString is primary")

-- Test TableBuilder new column types
local tb2 = MigrationLib.TableBuilder.new()
tb2:enum("status", {"active", "banned", "suspended"})
tb2:softDeletes()
tb2:timestamps()
tb2:unique("email")
tb2:index({"job", "money"})
tb2:foreignKey("owner_id", "users", "identifier", { onDelete = "SET NULL" })

T.match(tb2._columns[1].sql, "ENUM", "TableBuilder: enum column")
T.match(tb2._columns[1].sql, "'active'", "TableBuilder: enum values")
T.match(tb2._columns[2].sql, "deleted_at", "TableBuilder: softDeletes")
T.match(tb2._columns[3].sql, "created_at", "TableBuilder: timestamps created_at")
T.match(tb2._columns[4].sql, "updated_at", "TableBuilder: timestamps updated_at")
T.eq(#tb2._indexes, 2, "TableBuilder: 2 indexes")
T.eq(tb2._indexes[1].unique, true, "TableBuilder: unique index")
T.eq(tb2._indexes[2].unique, false, "TableBuilder: non-unique index")
T.eq(#tb2._foreignKeys, 1, "TableBuilder: 1 foreign key")
T.eq(tb2._foreignKeys[1].refTable, "users", "TableBuilder: FK references users")

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
T.match(stmts5[1], "UNIQUE KEY", "SchemaBuilder: UNIQUE KEY in CREATE TABLE")
T.match(stmts5[1], "FOREIGN KEY", "SchemaBuilder: FOREIGN KEY in CREATE TABLE")
T.match(stmts5[1], "REFERENCES `users`", "SchemaBuilder: FK REFERENCES")

-- ─── Test: SchemaBuilder multiple create() ──────────────────────────

T.section("SchemaBuilder multiple create()")

do
    local sb = MigrationLib.SchemaBuilder.new()
    sb:create("table_alpha", function(t)
        t:id()
        t:string("name")
    end)
    sb:create("table_beta", function(t)
        t:id()
        t:integer("score")
    end)
    local stmts = sb:toSQL()
    T.eq(#stmts, 2, "multi-create: generates 2 statements")
    T.match(stmts[1], "table_alpha", "multi-create: first statement is table_alpha")
    T.match(stmts[2], "table_beta", "multi-create: second statement is table_beta")
    T.match(stmts[1], "CREATE TABLE", "multi-create: first is CREATE TABLE")
    T.match(stmts[2], "CREATE TABLE", "multi-create: second is CREATE TABLE")
    T.match(stmts[1], "`name`", "multi-create: first has name column")
    T.match(stmts[2], "`score`", "multi-create: second has score column")
end

-- ─── Test: sync() with timestamps ────────────────────────────────────

T.section("sync() with timestamps")

do
    reset()
    local TsModel = ORM.model("ts_users", {
        id   = "number",
        name = "string",
    }, { timestamps = true })

    TsModel.sync()
    local syncSQL = dbLog[1].sql
    T.match(syncSQL, "CREATE TABLE", "sync timestamps: generates CREATE TABLE")
    T.match(syncSQL, "created_at", "sync timestamps: includes created_at")
    T.match(syncSQL, "updated_at", "sync timestamps: includes updated_at")
    T.match(syncSQL, "ts_users", "sync timestamps: correct table name")
end

-- ─── Test: sync() with softDelete ────────────────────────────────────

T.section("sync() with softDelete")

do
    reset()
    local SdModel = ORM.model("sd_users", {
        id   = "number",
        name = "string",
    }, { softDelete = true })

    SdModel.sync()
    local syncSQL = dbLog[1].sql
    T.match(syncSQL, "CREATE TABLE", "sync softDelete: generates CREATE TABLE")
    T.match(syncSQL, "deleted_at", "sync softDelete: includes deleted_at")
    T.match(syncSQL, "sd_users", "sync softDelete: correct table name")
end

-- ─── Test: sync() with both timestamps and softDelete ────────────────

T.section("sync() with timestamps + softDelete")

do
    reset()
    local BothModel = ORM.model("both_users", {
        id   = "number",
        name = "string",
    }, { timestamps = true, softDelete = true })

    BothModel.sync()
    local syncSQL = dbLog[1].sql
    T.match(syncSQL, "created_at", "sync both: includes created_at")
    T.match(syncSQL, "updated_at", "sync both: includes updated_at")
    T.match(syncSQL, "deleted_at", "sync both: includes deleted_at")
end

T.section("Migration identifier security")

local invalidTableOk = pcall(function()
    ORM.schema():create("users`; DROP TABLE users; --", function(t) t:id() end)
end)
T.eq(invalidTableOk, false, "migration rejects unsafe table names")

local invalidColumnOk = pcall(function()
    ORM.schema():create("safe_table", function(t) t:string("name`; DROP TABLE users; --") end)
end)
T.eq(invalidColumnOk, false, "migration rejects unsafe column names")

local invalidIndexOk = pcall(function()
    ORM.schema():create("safe_table", function(t)
        t:string("name")
        t:index("name", "idx`; DROP TABLE users; --")
    end)
end)
T.eq(invalidIndexOk, false, "migration rejects unsafe index names")

local invalidLengthOk = pcall(function()
    ORM.schema():create("safe_table", function(t) t:string("name", -1) end)
end)
T.eq(invalidLengthOk, false, "migration rejects invalid VARCHAR lengths")

T.finish()
