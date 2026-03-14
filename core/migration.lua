-- core/migration.lua
-- Migration system for creating and managing database tables.
--
-- Supports:
--   - Automatic table creation from model schemas (Model.sync())
--   - Named migrations with up/down support
--   - Migration tracking via a migrations table

local Helpers = OrvexHelpers or require("utils.helpers")

---@alias OrvexColumnDef { type: string, length?: number, nullable?: boolean, default?: any, primary?: boolean, unique?: boolean, autoIncrement?: boolean, unsigned?: boolean, references?: { table: string, column: string } }

---@class OrvexMigration
---@field name string
---@field up fun(schema: OrvexSchemaBuilder)
---@field down fun(schema: OrvexSchemaBuilder)

---@class OrvexSchemaBuilder
---@field private _tableName string
---@field private _columns OrvexColumnSQL[]
---@field private _drops string[]
---@field private _addColumns OrvexColumnSQL[]
---@field private _dropColumns string[]
---@field private _renames { from: string, to: string }[]
---@field private _rawStatements string[]
local SchemaBuilder = {}
SchemaBuilder.__index = SchemaBuilder

-- Forward declaration (defined below)
local TableBuilder

---@class OrvexColumnSQL
---@field name string
---@field sql string

--- Type mapping from OrvexFieldType to MySQL column type.
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

--- Convert an OrvexFieldType or extended column definition to a MySQL column SQL fragment.
---@param name string              Column name
---@param def string|OrvexColumnDef  Field type string or extended definition
---@param isPrimaryKey? boolean    Whether this column is the primary key
---@return string sql              e.g. "`name` VARCHAR(60) NOT NULL DEFAULT 'value'"
local function columnToSQL(name, def, isPrimaryKey)
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
        if type(default) == "string" then
            parts[#parts + 1] = ("DEFAULT '%s'"):format(default:gsub("'", "''"))
        elseif type(default) == "boolean" then
            parts[#parts + 1] = ("DEFAULT %s"):format(default and "1" or "0")
        else
            parts[#parts + 1] = ("DEFAULT %s"):format(tostring(default))
        end
    elseif nullable and not autoIncrement then
        parts[#parts + 1] = "DEFAULT NULL"
    end

    if unique and not isPrimaryKey then
        parts[#parts + 1] = "UNIQUE"
    end

    return table.concat(parts, " ")
end

-- ─── SchemaBuilder methods ──────────────────────────────────────────

function SchemaBuilder.new()
    return setmetatable({
        _tableName     = nil,
        _columns       = {},
        _drops         = {},
        _addColumns    = {},
        _dropColumns   = {},
        _renames       = {},
        _rawStatements = {},
    }, SchemaBuilder)
end

--- Create a new table.
---@param tableName string
---@param callback fun(table: OrvexTableBuilder)
function SchemaBuilder:create(tableName, callback)
    self._tableName = tableName
    local tb = TableBuilder.new()
    callback(tb)
    self._columns = tb._columns
    self._tableBuilder = tb
end

--- Drop a table.
---@param tableName string
function SchemaBuilder:drop(tableName)
    self._drops[#self._drops + 1] = tableName
end

--- Drop a table if it exists.
---@param tableName string
function SchemaBuilder:dropIfExists(tableName)
    self._rawStatements[#self._rawStatements + 1] = ("DROP TABLE IF EXISTS `%s`"):format(tableName)
end

--- Add columns to an existing table.
---@param tableName string
---@param callback fun(table: OrvexTableBuilder)
function SchemaBuilder:table(tableName, callback)
    self._tableName = tableName
    local tb = TableBuilder.new()
    callback(tb)
    self._addColumns = tb._columns
    self._dropColumns = tb._dropColumns or {}
    self._renames = tb._renames or {}
end

--- Add a raw SQL statement.
---@param sql string
function SchemaBuilder:raw(sql)
    self._rawStatements[#self._rawStatements + 1] = sql
end

--- Convert to SQL statements.
---@return string[]
function SchemaBuilder:toSQL()
    local statements = {}

    -- CREATE TABLE
    if self._tableName and #self._columns > 0 then
        local colParts = {}
        local pkName = nil
        for _, col in ipairs(self._columns) do
            colParts[#colParts + 1] = "  " .. col.sql
            if col.primary then
                pkName = col.name
            end
        end
        if pkName then
            colParts[#colParts + 1] = ("  PRIMARY KEY (`%s`)"):format(pkName)
        end
        -- Inline indexes
        local tb = self._tableBuilder
        if tb then
            for _, idx in ipairs(tb._indexes) do
                local cols = {}
                for _, c in ipairs(idx.columns) do cols[#cols + 1] = "`" .. c .. "`" end
                local colStr = table.concat(cols, ", ")
                if idx.unique then
                    colParts[#colParts + 1] = ("  UNIQUE KEY `%s` (%s)"):format(idx.name, colStr)
                else
                    colParts[#colParts + 1] = ("  KEY `%s` (%s)"):format(idx.name, colStr)
                end
            end
            for _, fk in ipairs(tb._foreignKeys) do
                local fkName = ("fk_%s_%s"):format(self._tableName, fk.column)
                colParts[#colParts + 1] = ("  CONSTRAINT `%s` FOREIGN KEY (`%s`) REFERENCES `%s` (`%s`) ON DELETE %s ON UPDATE %s"):format(
                    fkName, fk.column, fk.refTable, fk.refColumn, fk.onDelete, fk.onUpdate
                )
            end
        end
        local sql = ("CREATE TABLE IF NOT EXISTS `%s` (\n%s\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"):format(
            self._tableName, table.concat(colParts, ",\n")
        )
        statements[#statements + 1] = sql
    end

    -- ALTER TABLE (add columns)
    if self._tableName and #self._addColumns > 0 and #self._columns == 0 then
        for _, col in ipairs(self._addColumns) do
            statements[#statements + 1] = ("ALTER TABLE `%s` ADD COLUMN %s"):format(
                self._tableName, col.sql
            )
        end
    end

    -- ALTER TABLE (drop columns)
    if self._tableName and self._dropColumns then
        for _, colName in ipairs(self._dropColumns) do
            statements[#statements + 1] = ("ALTER TABLE `%s` DROP COLUMN `%s`"):format(
                self._tableName, colName
            )
        end
    end

    -- ALTER TABLE (rename columns)
    if self._tableName and self._renames then
        for _, r in ipairs(self._renames) do
            statements[#statements + 1] = ("ALTER TABLE `%s` RENAME COLUMN `%s` TO `%s`"):format(
                self._tableName, r.from, r.to
            )
        end
    end

    -- DROP TABLE
    for _, tableName in ipairs(self._drops) do
        statements[#statements + 1] = ("DROP TABLE `%s`"):format(tableName)
    end

    -- Raw statements
    for _, sql in ipairs(self._rawStatements) do
        statements[#statements + 1] = sql
    end

    return statements
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

--- Add a string (VARCHAR) column.
---@param name string
---@param length? number  Default 255
---@return OrvexTableBuilder
function TableBuilder:string(name, length)
    local colType = length and ("VARCHAR(%d)"):format(length) or "VARCHAR(255)"
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` %s NULL DEFAULT NULL"):format(name, colType),
    }
    return self
end

--- Add an integer column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:integer(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` INT NULL DEFAULT NULL"):format(name),
    }
    return self
end

--- Add a BIGINT column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:bigInteger(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` BIGINT NULL DEFAULT NULL"):format(name),
    }
    return self
end

--- Add a TINYINT(1) boolean column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:boolean(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` TINYINT(1) NULL DEFAULT 0"):format(name),
    }
    return self
end

--- Add a TEXT column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:text(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` TEXT NULL"):format(name),
    }
    return self
end

--- Add a JSON column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:json(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` JSON NULL"):format(name),
    }
    return self
end

--- Add a FLOAT column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:float(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` FLOAT NULL DEFAULT NULL"):format(name),
    }
    return self
end

--- Add a DOUBLE column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:double(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` DOUBLE NULL DEFAULT NULL"):format(name),
    }
    return self
end

--- Add a DATE column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:date(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` DATE NULL DEFAULT NULL"):format(name),
    }
    return self
end

--- Add a DATETIME column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:datetime(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` DATETIME NULL DEFAULT NULL"):format(name),
    }
    return self
end

--- Add a TIMESTAMP column.
---@param name string
---@return OrvexTableBuilder
function TableBuilder:timestamp(name)
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP"):format(name),
    }
    return self
end

--- Add an auto-increment primary key column.
---@param name? string  Default "id"
---@return OrvexTableBuilder
function TableBuilder:id(name)
    name = name or "id"
    self._columns[#self._columns + 1] = {
        name    = name,
        primary = true,
        sql     = ("`%s` INT UNSIGNED NOT NULL AUTO_INCREMENT"):format(name),
    }
    return self
end

--- Add a string primary key column (for identifiers).
---@param name string
---@param length? number  Default 60
---@return OrvexTableBuilder
function TableBuilder:primaryString(name, length)
    length = length or 60
    self._columns[#self._columns + 1] = {
        name    = name,
        primary = true,
        sql     = ("`%s` VARCHAR(%d) NOT NULL"):format(name, length),
    }
    return self
end

--- Add an ENUM column.
---@param name string
---@param values string[]  e.g. {"active", "banned", "suspended"}
---@return OrvexTableBuilder
function TableBuilder:enum(name, values)
    local quoted = {}
    for _, v in ipairs(values) do
        quoted[#quoted + 1] = "'" .. v:gsub("'", "''") .. "'"
    end
    self._columns[#self._columns + 1] = {
        name = name,
        sql  = ("`%s` ENUM(%s) NULL DEFAULT NULL"):format(name, table.concat(quoted, ", ")),
    }
    return self
end

--- Add soft delete support (deleted_at column).
---@return OrvexTableBuilder
function TableBuilder:softDeletes()
    self._columns[#self._columns + 1] = {
        name = "deleted_at",
        sql  = "`deleted_at` DATETIME NULL DEFAULT NULL",
    }
    return self
end

--- Add created_at and updated_at timestamp columns.
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

--- Add a UNIQUE constraint on one or more columns.
---@param columns string|string[]  Column name or list of column names
---@param indexName? string
---@return OrvexTableBuilder
function TableBuilder:unique(columns, indexName)
    if type(columns) == "string" then columns = { columns } end
    indexName = indexName or ("uq_" .. table.concat(columns, "_"))
    self._indexes[#self._indexes + 1] = {
        name = indexName,
        columns = columns,
        unique = true,
    }
    return self
end

--- Add an INDEX on one or more columns.
---@param columns string|string[]
---@param indexName? string
---@return OrvexTableBuilder
function TableBuilder:index(columns, indexName)
    if type(columns) == "string" then columns = { columns } end
    indexName = indexName or ("idx_" .. table.concat(columns, "_"))
    self._indexes[#self._indexes + 1] = {
        name = indexName,
        columns = columns,
        unique = false,
    }
    return self
end

--- Add a FOREIGN KEY constraint.
---@param column string       Local column
---@param refTable string     Referenced table
---@param refColumn string    Referenced column
---@param opts? { onDelete?: string, onUpdate?: string }
---@return OrvexTableBuilder
function TableBuilder:foreignKey(column, refTable, refColumn, opts)
    opts = opts or {}
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

--- Mark that a column should be dropped (for use in :table() alter mode).
---@param name string
---@return OrvexTableBuilder
function TableBuilder:dropColumn(name)
    self._dropColumns[#self._dropColumns + 1] = name
    return self
end

--- Rename a column.
---@param from string
---@param to string
---@return OrvexTableBuilder
function TableBuilder:renameColumn(from, to)
    self._renames[#self._renames + 1] = { from = from, to = to }
    return self
end

-- ─── Migration module ───────────────────────────────────────────────

---@class OrvexMigrationRunner
local Migration = {}

--- The tracking table name for applied migrations.
Migration.TRACKING_TABLE = "orvex_migrations"

--- Generate CREATE TABLE SQL from a model's schema and primaryKey.
---@param tableName string
---@param fields table<string, OrvexFieldType|OrvexColumnDef>
---@param primaryKey string
---@return string sql
function Migration.generateCreateSQL(tableName, fields, primaryKey)
    local keys = Helpers.sortedKeys(fields)
    local colParts = {}

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

--- Ensure the migrations tracking table exists.
---@param adapter OrvexAdapter
function Migration.ensureTrackingTable(adapter)
    local sql = [[CREATE TABLE IF NOT EXISTS `orvex_migrations` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `batch` INT NOT NULL DEFAULT 1,
  `executed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
    adapter:scalar(sql, {})
end

--- Get all applied migration names.
---@param adapter OrvexAdapter
---@return table<string, boolean>
function Migration.getApplied(adapter)
    local rows = adapter:execute("SELECT name FROM orvex_migrations ORDER BY id", {})
    local applied = {}
    if rows then
        for _, row in ipairs(rows) do
            applied[row.name] = true
        end
    end
    return applied
end

--- Get the current batch number.
---@param adapter OrvexAdapter
---@return number
function Migration.getCurrentBatch(adapter)
    local rows = adapter:execute("SELECT MAX(batch) as batch FROM orvex_migrations", {})
    if rows and rows[1] and rows[1].batch then
        return rows[1].batch
    end
    return 0
end

--- Run pending migrations.
---@param migrations OrvexMigration[]
---@param adapter OrvexAdapter
---@return number count  Number of migrations applied
function Migration.migrate(migrations, adapter)
    Migration.ensureTrackingTable(adapter)
    local applied = Migration.getApplied(adapter)
    local batch = Migration.getCurrentBatch(adapter) + 1
    local count = 0

    for _, mig in ipairs(migrations) do
        if not applied[mig.name] then
            local sb = SchemaBuilder.new()
            mig.up(sb)
            local statements = sb:toSQL()
            for _, sql in ipairs(statements) do
                adapter:scalar(sql, {})
            end
            adapter:scalar(
                "INSERT INTO orvex_migrations (name, batch) VALUES (?, ?)",
                { mig.name, batch }
            )
            count = count + 1
        end
    end

    return count
end

--- Rollback the last batch of migrations.
---@param migrations OrvexMigration[]
---@param adapter OrvexAdapter
---@return number count  Number of migrations rolled back
function Migration.rollback(migrations, adapter)
    Migration.ensureTrackingTable(adapter)
    local batch = Migration.getCurrentBatch(adapter)
    if batch == 0 then return 0 end

    local rows = adapter:execute(
        "SELECT name FROM orvex_migrations WHERE batch = ? ORDER BY id DESC",
        { batch }
    )
    if not rows or #rows == 0 then return 0 end

    -- Build lookup for migration definitions
    local migByName = {}
    for _, mig in ipairs(migrations) do
        migByName[mig.name] = mig
    end

    local count = 0
    for _, row in ipairs(rows) do
        local mig = migByName[row.name]
        if mig then
            local sb = SchemaBuilder.new()
            mig.down(sb)
            local statements = sb:toSQL()
            for _, sql in ipairs(statements) do
                adapter:scalar(sql, {})
            end
        end
        adapter:scalar("DELETE FROM orvex_migrations WHERE name = ?", { row.name })
        count = count + 1
    end

    return count
end

--- Sync a model's table (create if not exists).
---@param tableName string
---@param fields table<string, OrvexFieldType|OrvexColumnDef>
---@param primaryKey string
---@param adapter OrvexAdapter
function Migration.sync(tableName, fields, primaryKey, adapter)
    local sql = Migration.generateCreateSQL(tableName, fields, primaryKey)
    adapter:scalar(sql, {})
end

-- Expose internals for testing
Migration.columnToSQL    = columnToSQL
Migration.SchemaBuilder  = SchemaBuilder
Migration.TableBuilder   = TableBuilder
Migration.TYPE_MAP       = TYPE_MAP

OrvexMigration = Migration
return Migration
