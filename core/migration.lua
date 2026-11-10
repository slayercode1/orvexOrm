-- core/migration.lua
-- Migration system for creating and managing database tables.

local Helpers = OrvexHelpers or require("utils.helpers")
local assertId = Helpers.assertSafeIdentifier

---@alias OrvexColumnDef { type: string, length?: number, nullable?: boolean, default?: any, primary?: boolean, unique?: boolean, autoIncrement?: boolean, unsigned?: boolean, references?: { table: string, column: string } }

---@class OrvexMigration
---@field name string
---@field up fun(schema: OrvexSchemaBuilder)
---@field down fun(schema: OrvexSchemaBuilder)

---@class OrvexSchemaBuilder
---@field private _statements string[] SQL statements, in call order
local SchemaBuilder = {}
SchemaBuilder.__index = SchemaBuilder

local TableBuilder

---@class OrvexColumnSQL
---@field name string
---@field sql string
---@field primary? boolean

---@type table<string, string>
local TYPE_MAP = {
    string    = "VARCHAR(255)",
    number    = "INT",
    boolean   = "TINYINT(1)",
    json      = "JSON",
    auto      = "TEXT",
    date      = "DATE",
    datetime  = "DATETIME",
    timestamp = "TIMESTAMP",
}

--- DEFAULT clause for a declared default. Only strings, booleans and finite
--- numbers are accepted: anything else (a table with __tostring, NaN, ...)
--- would be spliced into the DDL verbatim.
---@param columnName string
---@param default any
---@return string
local function defaultClause(columnName, default)
    if type(default) == "string" then
        return "DEFAULT " .. Helpers.quoteLiteral(default)
    elseif type(default) == "boolean" then
        return ("DEFAULT %s"):format(default and "1" or "0")
    elseif Helpers.isFiniteNumber(default) then
        return ("DEFAULT %s"):format(tostring(default))
    end
    error(("Invalid DEFAULT for column '%s': expected a string, a boolean or a finite number, got %s"):format(
        columnName, type(default) == "number" and tostring(default) or type(default)
    ), 0)
end

---@param name string
---@param def string|OrvexColumnDef
---@param isPrimaryKey? boolean
---@return string sql
local function columnToSQL(name, def, isPrimaryKey)
    assertId(name)
    local colType, nullable, default, unique, autoIncrement, unsigned

    if type(def) == "string" then
        colType = TYPE_MAP[def] or "TEXT"
        nullable = not isPrimaryKey
        autoIncrement = isPrimaryKey and (def == "number")
    elseif type(def) == "table" then
        local baseType = TYPE_MAP[def.type] or "TEXT"
        if def.length and (def.type == "string") then
            colType = ("VARCHAR(%d)"):format(def.length)
        else
            colType = baseType
        end
        nullable = def.nullable
        if nullable == nil then nullable = not (isPrimaryKey or def.primary) end
        default = def.default
        unique = def.unique
        autoIncrement = def.autoIncrement
        unsigned = def.unsigned
    else
        colType = "TEXT"
        nullable = true
    end

    local parts = { ("`%s`"):format(name), colType }

    if unsigned then
        parts[#parts + 1] = "UNSIGNED"
    end

    if not nullable then
        parts[#parts + 1] = "NOT NULL"
    else
        parts[#parts + 1] = "NULL"
    end

    if autoIncrement then
        parts[#parts + 1] = "AUTO_INCREMENT"
    end

    if default ~= nil then
        parts[#parts + 1] = defaultClause(name, default)
    elseif nullable and not autoIncrement then
        parts[#parts + 1] = "DEFAULT NULL"
    end

    if unique and not isPrimaryKey then
        parts[#parts + 1] = "UNIQUE"
    end

    return table.concat(parts, " ")
end

-- ─── SQL fragments shared by CREATE TABLE and ALTER TABLE ───────────

---@param columns string[]
---@return string
local function quoteColumnList(columns)
    local quoted = {}
    for _, c in ipairs(columns) do quoted[#quoted + 1] = "`" .. c .. "`" end
    return table.concat(quoted, ", ")
end

---@param tableName string
---@param fk table
---@return string
local function foreignKeyClause(tableName, fk)
    return ("CONSTRAINT `%s` FOREIGN KEY (`%s`) REFERENCES `%s` (`%s`) ON DELETE %s ON UPDATE %s"):format(
        ("fk_%s_%s"):format(tableName, fk.column), fk.column, fk.refTable, fk.refColumn, fk.onDelete, fk.onUpdate
    )
end

---@param tableName string
---@param tb OrvexTableBuilder
---@return string sql
local function buildCreateTableSQL(tableName, tb)
    local colParts = {}
    local pkName = nil
    for _, col in ipairs(tb._columns) do
        colParts[#colParts + 1] = "  " .. col.sql
        if col.primary then
            pkName = col.name
        end
    end
    if pkName then
        colParts[#colParts + 1] = ("  PRIMARY KEY (`%s`)"):format(pkName)
    end
    for _, idx in ipairs(tb._indexes) do
        local keyword = idx.unique and "UNIQUE KEY" or "KEY"
        colParts[#colParts + 1] = ("  %s `%s` (%s)"):format(keyword, idx.name, quoteColumnList(idx.columns))
    end
    for _, fk in ipairs(tb._foreignKeys) do
        colParts[#colParts + 1] = "  " .. foreignKeyClause(tableName, fk)
    end
    return ("CREATE TABLE IF NOT EXISTS `%s` (\n%s\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"):format(
        tableName, table.concat(colParts, ",\n")
    )
end

--- ALTER TABLE statements for one table() call. Columns are added, dropped
--- and renamed first so that indexes and foreign keys can target them.
---@param tableName string
---@param tb OrvexTableBuilder
---@return string[] statements
local function buildAlterTableSQL(tableName, tb)
    local alter = ("ALTER TABLE `%s` "):format(tableName)
    local statements = {}
    local function add(clause) statements[#statements + 1] = alter .. clause end

    for _, col in ipairs(tb._columns) do
        add("ADD COLUMN " .. col.sql .. (col.primary and " PRIMARY KEY" or ""))
    end
    for _, colName in ipairs(tb._dropColumns) do
        add(("DROP COLUMN `%s`"):format(colName))
    end
    for _, r in ipairs(tb._renames) do
        add(("RENAME COLUMN `%s` TO `%s`"):format(r.from, r.to))
    end
    for _, idx in ipairs(tb._indexes) do
        local keyword = idx.unique and "ADD UNIQUE INDEX" or "ADD INDEX"
        add(("%s `%s` (%s)"):format(keyword, idx.name, quoteColumnList(idx.columns)))
    end
    for _, fk in ipairs(tb._foreignKeys) do
        add("ADD " .. foreignKeyClause(tableName, fk))
    end
    return statements
end

-- ─── SchemaBuilder methods ──────────────────────────────────────────
-- Every operation appends its SQL to `_statements` when it is called,
-- so toSQL() returns the statements in call order.

function SchemaBuilder.new()
    return setmetatable({ _statements = {} }, SchemaBuilder)
end

---@param sql string
function SchemaBuilder:_push(sql)
    self._statements[#self._statements + 1] = sql
end

---@param callback fun(table: OrvexTableBuilder)
---@return OrvexTableBuilder
local function buildTable(callback)
    local tb = TableBuilder.new()
    callback(tb)
    return tb
end

---@param tableName string
---@param callback fun(table: OrvexTableBuilder)
function SchemaBuilder:create(tableName, callback)
    assertId(tableName)
    self:_push(buildCreateTableSQL(tableName, buildTable(callback)))
end

---@param tableName string
function SchemaBuilder:drop(tableName)
    assertId(tableName)
    self:_push(("DROP TABLE `%s`"):format(tableName))
end

---@param tableName string
function SchemaBuilder:dropIfExists(tableName)
    assertId(tableName)
    self:_push(("DROP TABLE IF EXISTS `%s`"):format(tableName))
end

---@param tableName string
---@param callback fun(table: OrvexTableBuilder)
function SchemaBuilder:table(tableName, callback)
    assertId(tableName)
    for _, sql in ipairs(buildAlterTableSQL(tableName, buildTable(callback))) do
        self:_push(sql)
    end
end

---@param sql string
function SchemaBuilder:raw(sql)
    self:_push(sql)
end

---@return string[]
function SchemaBuilder:toSQL()
    return table.move(self._statements, 1, #self._statements, 1, {})
end

-- ─── TableBuilder ───────────────────────────────────────────────────

---@class OrvexTableBuilder
---@field private _columns OrvexColumnSQL[]
---@field private _dropColumns string[]
---@field private _renames { from: string, to: string }[]
---@field private _indexes { name: string, columns: string[], unique: boolean }[]
---@field private _foreignKeys { column: string, refTable: string, refColumn: string, onDelete?: string, onUpdate?: string }[]
TableBuilder = {}
TableBuilder.__index = TableBuilder

function TableBuilder.new()
    return setmetatable({
        _columns     = {},
        _dropColumns = {},
        _renames     = {},
        _indexes     = {},
        _foreignKeys = {},
    }, TableBuilder)
end

---@param name string
---@param length? number
---@return OrvexTableBuilder
function TableBuilder:string(name, length)
    assertId(name)
    assert(not length or (type(length) == "number" and length >= 1 and length <= 65535 and length % 1 == 0), "VARCHAR length must be an integer between 1 and 65535")
    local colType = length and ("VARCHAR(%d)"):format(length) or "VARCHAR(255)"
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` %s NULL DEFAULT NULL"):format(name, colType),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:integer(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` INT NULL DEFAULT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:bigInteger(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` BIGINT NULL DEFAULT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:boolean(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` TINYINT(1) NULL DEFAULT 0"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:text(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` TEXT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:json(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` JSON NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:float(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` FLOAT NULL DEFAULT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:double(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` DOUBLE NULL DEFAULT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:date(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` DATE NULL DEFAULT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:datetime(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` DATETIME NULL DEFAULT NULL"):format(name),
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:timestamp(name)
    assertId(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP"):format(name),
    }
    return self
end

---@param name? string
---@return OrvexTableBuilder
function TableBuilder:id(name)
    name = name or "id"
    assertId(name)
    self._columns[#self._columns + 1] = {
        name    = name,
        primary = true,
        sql     = ("`%s` INT UNSIGNED NOT NULL AUTO_INCREMENT"):format(name),
    }
    return self
end

---@param name string
---@param length? number
---@return OrvexTableBuilder
function TableBuilder:primaryString(name, length)
    length = length or 60
    assertId(name)
    assert(type(length) == "number" and length >= 1 and length <= 65535 and length % 1 == 0, "VARCHAR length must be an integer between 1 and 65535")
    self._columns[#self._columns + 1] = {
        name    = name,
        primary = true,
        sql     = ("`%s` VARCHAR(%d) NOT NULL"):format(name, length),
    }
    return self
end

---@param name string
---@param values string[]
---@return OrvexTableBuilder
function TableBuilder:enum(name, values)
    assertId(name)
    assert(type(values) == "table" and #values > 0, "enum requires at least one value")
    local quoted = {}
    for _, v in ipairs(values) do
        quoted[#quoted + 1] = Helpers.quoteLiteral(v)
    end
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` ENUM(%s) NULL DEFAULT NULL"):format(name, table.concat(quoted, ", ")),
    }
    return self
end

---@return OrvexTableBuilder
function TableBuilder:softDeletes()
    self._columns[#self._columns + 1] = {
        name = "deleted_at",
        sql  = "`deleted_at` DATETIME NULL DEFAULT NULL",
    }
    return self
end

---@return OrvexTableBuilder
function TableBuilder:timestamps()
    self._columns[#self._columns + 1] = {
        name = "created_at",
        sql  = "`created_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP",
    }
    self._columns[#self._columns + 1] = {
        name = "updated_at",
        sql  = "`updated_at` DATETIME NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP",
    }
    return self
end

---@param columns string|string[]
---@param indexName? string
---@return OrvexTableBuilder
function TableBuilder:unique(columns, indexName)
    if type(columns) == "string" then columns = { columns } end
    indexName = indexName or ("uq_" .. table.concat(columns, "_"))
    assertId(indexName)
    for _, column in ipairs(columns) do assertId(column) end
    self._indexes[#self._indexes + 1] = {
        name = indexName,
        columns = columns,
        unique = true,
    }
    return self
end

---@param columns string|string[]
---@param indexName? string
---@return OrvexTableBuilder
function TableBuilder:index(columns, indexName)
    if type(columns) == "string" then columns = { columns } end
    indexName = indexName or ("idx_" .. table.concat(columns, "_"))
    assertId(indexName)
    for _, column in ipairs(columns) do assertId(column) end
    self._indexes[#self._indexes + 1] = {
        name = indexName,
        columns = columns,
        unique = false,
    }
    return self
end

---@param column string
---@param refTable string
---@param refColumn string
---@param opts? { onDelete?: string, onUpdate?: string }
---@return OrvexTableBuilder
function TableBuilder:foreignKey(column, refTable, refColumn, opts)
    opts = opts or {}
    assertId(column)
    assertId(refTable)
    assertId(refColumn)
    local VALID_ACTIONS = { CASCADE = true, RESTRICT = true, ["SET NULL"] = true, ["NO ACTION"] = true, ["SET DEFAULT"] = true }
    local onDelete = (opts.onDelete or "CASCADE"):upper()
    local onUpdate = (opts.onUpdate or "CASCADE"):upper()
    assert(VALID_ACTIONS[onDelete], ("Invalid ON DELETE action: '%s'"):format(onDelete))
    assert(VALID_ACTIONS[onUpdate], ("Invalid ON UPDATE action: '%s'"):format(onUpdate))
    self._foreignKeys[#self._foreignKeys + 1] = {
        column    = column,
        refTable  = refTable,
        refColumn = refColumn,
        onDelete  = onDelete,
        onUpdate  = onUpdate,
    }
    return self
end

---@param name string
---@return OrvexTableBuilder
function TableBuilder:dropColumn(name)
    assertId(name)
    self._dropColumns[#self._dropColumns + 1] = name
    return self
end

---@param from string
---@param to string
---@return OrvexTableBuilder
function TableBuilder:renameColumn(from, to)
    assertId(from)
    assertId(to)
    self._renames[#self._renames + 1] = { from = from, to = to }
    return self
end

-- ─── Migration module ───────────────────────────────────────────────

---@class OrvexMigrationRunner
local Migration = {}

Migration.TRACKING_TABLE = "orvex_migrations"

--- Same column as TableBuilder:id(), used when a model does not declare its primary key.
---@param primaryKey string
---@return string sql
local function autoIncrementPrimaryKeySQL(primaryKey)
    return ("`%s` INT UNSIGNED NOT NULL AUTO_INCREMENT"):format(primaryKey)
end

--- Builds the CREATE TABLE used by Model.sync(). When `primaryKey` is not
--- declared in `fields`, an `INT UNSIGNED NOT NULL AUTO_INCREMENT` column is
--- injected first, like TableBuilder:id().
---@param tableName string
---@param fields table<string, OrvexFieldType|OrvexColumnDef>
---@param primaryKey string
---@return string sql
function Migration.generateCreateSQL(tableName, fields, primaryKey)
    assertId(tableName)
    assertId(primaryKey)
    local keys = Helpers.sortedKeys(fields)
    local colParts = {}

    if fields[primaryKey] == nil then
        colParts[1] = "  " .. autoIncrementPrimaryKeySQL(primaryKey)
    end

    for _, name in ipairs(keys) do
        local isPK = (name == primaryKey)
        local sql = columnToSQL(name, fields[name], isPK)
        colParts[#colParts + 1] = "  " .. sql
    end

    colParts[#colParts + 1] = ("  PRIMARY KEY (`%s`)"):format(primaryKey)

    return ("CREATE TABLE IF NOT EXISTS `%s` (\n%s\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"):format(
        tableName, table.concat(colParts, ",\n")
    )
end

-- ─── Tracking table ─────────────────────────────────────────────────
-- orvex_migrations is shared by every resource on the database. Each row
-- records the resource that applied it; rows written before that column
-- existed keep LEGACY_RESOURCE and belong to whichever caller lists them.
-- Names stay globally unique (UNIQUE `name`), so a name already recorded by
-- another resource is rejected instead of being silently skipped.

local LEGACY_RESOURCE = ""

local TRACKING_TABLE_SQL = [[CREATE TABLE IF NOT EXISTS `orvex_migrations` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `resource` VARCHAR(255) NOT NULL DEFAULT '',
  `batch` INT NOT NULL DEFAULT 1,
  `executed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

local RESOURCE_COLUMN_EXISTS_SQL = "SELECT COLUMN_NAME FROM information_schema.COLUMNS "
    .. "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orvex_migrations' AND COLUMN_NAME = 'resource'"

local ADD_RESOURCE_COLUMN_SQL = "ALTER TABLE `orvex_migrations` ADD COLUMN `resource` VARCHAR(255) NOT NULL DEFAULT '' AFTER `name`"

--- Runs a write and raises when the driver fails, including when it
--- swallows the error and returns nil (oxmysql).
---@param adapter OrvexAdapter
---@param sql string
---@param params any[]
---@param failureMessage string
local function runCheckedWrite(adapter, sql, params, failureMessage)
    local ok, result = pcall(adapter.scalar, adapter, sql, params)
    if not ok or result == nil then
        error(("[OrvexORM] %s: %s"):format(failureMessage, ok and "driver returned no result" or tostring(result)), 0)
    end
end

--- Creates orvex_migrations, and adds the `resource` column to a table
--- created by an older version.
---@param adapter OrvexAdapter
function Migration.ensureTrackingTable(adapter)
    runCheckedWrite(adapter, TRACKING_TABLE_SQL, {}, "cannot create the orvex_migrations table")
    local rows = adapter:execute(RESOURCE_COLUMN_EXISTS_SQL, {})
    if not (rows and rows[1]) then
        runCheckedWrite(adapter, ADD_RESOURCE_COLUMN_SQL, {}, "cannot add the resource column to orvex_migrations")
    end
end

---@class OrvexMigrationRecord
---@field id number
---@field name string
---@field batch number
---@field resource string

--- Every tracking row, oldest first.
---@param adapter OrvexAdapter
---@return OrvexMigrationRecord[]
local function readRecords(adapter)
    local rows = adapter:execute("SELECT id, name, batch, resource FROM orvex_migrations ORDER BY id", {}) or {}
    local records = {}
    for i, row in ipairs(rows) do
        records[i] = {
            id = tonumber(row.id) or i,
            name = row.name,
            batch = tonumber(row.batch) or 0,
            resource = row.resource or LEGACY_RESOURCE,
        }
    end
    return records
end

---@param adapter OrvexAdapter
---@return table<string, boolean>
function Migration.getApplied(adapter)
    local applied = {}
    for _, record in ipairs(readRecords(adapter)) do applied[record.name] = true end
    return applied
end

---@param records OrvexMigrationRecord[]
---@return number
local function highestBatch(records)
    local batch = 0
    for _, record in ipairs(records) do
        if record.batch > batch then batch = record.batch end
    end
    return batch
end

--- Highest batch number recorded by any resource.
---@param adapter OrvexAdapter
---@return number
function Migration.getCurrentBatch(adapter)
    return highestBatch(readRecords(adapter))
end

---@param migrations OrvexMigration[]
---@return table<string, OrvexMigration>
local function indexByName(migrations)
    local byName = {}
    for _, mig in ipairs(migrations) do byName[mig.name] = mig end
    return byName
end

---@param record OrvexMigrationRecord
---@param resource string
---@param migByName table<string, OrvexMigration>
---@return boolean
local function isOwnedBy(record, resource, migByName)
    if record.resource == resource then return true end
    return record.resource == LEGACY_RESOURCE and migByName[record.name] ~= nil
end

--- Resource the caller runs in: FiveM gives every resource its own copy of
--- this module (lib/import.lua), so GetCurrentResourceName() names the caller.
---@return string
local function currentResourceName()
    if type(GetCurrentResourceName) == "function" then
        return GetCurrentResourceName() or LEGACY_RESOURCE
    end
    return LEGACY_RESOURCE
end

-- ─── migrate / rollback ─────────────────────────────────────────────

--- Runs one schema step (`up` or `down`) and every statement it produces.
--- A driver that swallows a query error returns nil (oxmysql), so a nil
--- result is treated as a failure too.
---@param step fun(schema: OrvexSchemaBuilder)
---@param adapter OrvexAdapter
local function runSchemaStep(step, adapter)
    local sb = SchemaBuilder.new()
    step(sb)
    for _, sql in ipairs(sb:toSQL()) do
        if adapter:scalar(sql, {}) == nil then
            error(("statement failed (driver returned no result): %s"):format(sql), 0)
        end
    end
end

--- Raises the error of a failed migration step. MySQL DDL is not
--- transactional: statements that ran before the failure stay applied.
---@param action string "Migration" or "Rollback"
---@param doneVerb string past tense of the action, e.g. "applied"
---@param mig OrvexMigration
---@param doneCount number
---@param err any
local function raiseStepFailure(action, doneVerb, mig, doneCount, err)
    error(("[OrvexORM] %s of migration '%s' failed (%d migration(s) %s before it): %s"):format(
        action, mig.name, doneCount, doneVerb, tostring(err)
    ), 0)
end

--- Migrations of the list not recorded yet. Raises, before anything runs,
--- when a name is already recorded by another resource.
---@param migrations OrvexMigration[]
---@param records OrvexMigrationRecord[]
---@param resource string
---@return OrvexMigration[]
local function pendingMigrations(migrations, records, resource)
    local migByName = indexByName(migrations)
    local recordByName = {}
    for _, record in ipairs(records) do recordByName[record.name] = record end

    local pending = {}
    for _, mig in ipairs(migrations) do
        local record = recordByName[mig.name]
        if not record then
            pending[#pending + 1] = mig
        elseif not isOwnedBy(record, resource, migByName) then
            error(("[OrvexORM] Migration '%s' is already recorded by resource '%s': migration names are shared by every resource on the database, prefix them with your resource name"):format(
                mig.name, record.resource
            ), 0)
        end
    end
    return pending
end

--- Applies pending migrations in order, in a new batch recorded for
--- `resource`. Each migration runs under pcall: on the first failure it is
--- NOT recorded, the following ones are not run, and an error naming it is
--- raised. A migration whose tracking row cannot be written raises too.
---@param migrations OrvexMigration[]
---@param adapter OrvexAdapter
---@param resource? string defaults to GetCurrentResourceName()
---@return number count applied migrations
function Migration.migrate(migrations, adapter, resource)
    resource = resource or currentResourceName()
    Migration.ensureTrackingTable(adapter)
    local records = readRecords(adapter)
    local pending = pendingMigrations(migrations, records, resource)
    -- Not atomic: resources calling migrate() at the same instant may share
    -- a batch number. Harmless, since rollback only touches the caller's rows.
    local batch = highestBatch(records) + 1

    for index, mig in ipairs(pending) do
        local applied = index - 1
        local ok, err = pcall(runSchemaStep, mig.up, adapter)
        if not ok then raiseStepFailure("Migration", "applied", mig, applied, err) end
        runCheckedWrite(adapter,
            "INSERT INTO orvex_migrations (name, batch, resource) VALUES (?, ?, ?)",
            { mig.name, batch, resource },
            ("migration '%s' was applied but could not be recorded (%d migration(s) applied before it)"):format(mig.name, applied)
        )
    end
    return #pending
end

--- Caller's last batch, newest first: rows it owns, listed in `migrations`.
---@param records OrvexMigrationRecord[]
---@param migByName table<string, OrvexMigration>
---@param resource string
---@return OrvexMigrationRecord[]
local function lastOwnedBatch(records, migByName, resource)
    local owned = {}
    for _, record in ipairs(records) do
        if migByName[record.name] and isOwnedBy(record, resource, migByName) then owned[#owned + 1] = record end
    end
    local batch = highestBatch(owned)
    local lastBatch = {}
    for i = #owned, 1, -1 do
        if owned[i].batch == batch then lastBatch[#lastBatch + 1] = owned[i] end
    end
    return lastBatch
end

--- Rolls back the caller's last batch, newest first. Only migrations listed
--- in `migrations` and recorded for `resource` (or legacy rows) are
--- touched. A failed `down` keeps its migration recorded and raises.
---@param migrations OrvexMigration[]
---@param adapter OrvexAdapter
---@param resource? string defaults to GetCurrentResourceName()
---@return number count rolled back migrations
function Migration.rollback(migrations, adapter, resource)
    resource = resource or currentResourceName()
    Migration.ensureTrackingTable(adapter)
    local migByName = indexByName(migrations)
    local toRollBack = lastOwnedBatch(readRecords(adapter), migByName, resource)

    for index, record in ipairs(toRollBack) do
        local rolledBack = index - 1
        local mig = migByName[record.name]
        local ok, err = pcall(runSchemaStep, mig.down, adapter)
        if not ok then raiseStepFailure("Rollback", "rolled back", mig, rolledBack, err) end
        runCheckedWrite(adapter,
            "DELETE FROM orvex_migrations WHERE name = ? AND resource = ?",
            { record.name, record.resource },
            ("migration '%s' was rolled back but its tracking row could not be deleted (%d migration(s) rolled back before it)"):format(mig.name, rolledBack)
        )
    end
    return #toRollBack
end

---@param tableName string
---@param fields table<string, OrvexFieldType|OrvexColumnDef>
---@param primaryKey string
---@param adapter OrvexAdapter
function Migration.sync(tableName, fields, primaryKey, adapter)
    local sql = Migration.generateCreateSQL(tableName, fields, primaryKey)
    adapter:scalar(sql, {})
end

Migration.columnToSQL    = columnToSQL
Migration.SchemaBuilder  = SchemaBuilder
Migration.TableBuilder   = TableBuilder
Migration.TYPE_MAP       = TYPE_MAP

OrvexMigration = Migration
return Migration
