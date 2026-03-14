-- core/orm.lua
-- Main entry point for the ORM.

local ModelFactory  = OrvexModelFactory or require("core.model")
local Adapter       = OrvexAdapter or require("database.adapter")
local MySQLDriver   = OrvexMySQLDriver or require("database.mysql")
local Transaction   = OrvexTransaction or require("core.transaction")
local Cache         = OrvexCache or require("utils.cache")
local Migration     = OrvexMigration or require("core.migration")
local Logger        = OrvexLogger or require("utils.logger")
local Helpers       = OrvexHelpers or require("utils.helpers")

---@class OrvexORM
local ORM = {}

--- Default adapter: oxmysql via the MySQL driver.
---@type OrvexAdapter
local defaultAdapter = Adapter.new(MySQLDriver.new())

--- Global cache shared across all models.
---@type OrvexCache
local globalCache = Cache.new({ ttl = 60, enabled = false })

--- Register a model bound to a MySQL table.
---@param tableName string
---@param fields table<string, OrvexFieldType>
---@param opts? OrvexModelOpts
---@return OrvexModel
function ORM.model(tableName, fields, opts)
    opts = opts or {}
    local adapter = opts.adapter or defaultAdapter
    local cache = opts.cache or globalCache
    return ModelFactory.new(tableName, fields, adapter, opts, cache)
end

--- Create a new transaction builder, or execute a callback transactionally.
--- If a function is passed, it is called with the transaction and auto-committed.
--- On error, the transaction is not committed and the error is re-raised.
---@param adapterOrFn? OrvexAdapter|fun(tx: OrvexTransaction)
---@param adapter? OrvexAdapter
---@return OrvexTransaction|boolean
function ORM.transaction(adapterOrFn, adapter)
    -- Callback mode: ORM.transaction(function(tx) ... end)
    if type(adapterOrFn) == "function" then
        local tx = Transaction.new(adapter or defaultAdapter)
        adapterOrFn(tx)
        return tx:commit()
    end

    -- Builder mode: local tx = ORM.transaction()
    return Transaction.new(adapterOrFn or defaultAdapter)
end

--- Enable the global cache with optional TTL.
---@param opts? { ttl?: number }
function ORM.enableCache(opts)
    opts = opts or {}
    if opts.ttl then
        globalCache._ttl = opts.ttl
    end
    globalCache:setEnabled(true)
end

--- Disable and flush the global cache.
function ORM.disableCache()
    globalCache:setEnabled(false)
end

--- Flush the global cache.
function ORM.flushCache()
    globalCache:flush()
end

--- Swap the default adapter.
---@param adapter OrvexAdapter
function ORM.setAdapter(adapter)
    defaultAdapter = adapter
end

--- Execute a raw SQL query.
---@param sql string
---@param params? any[]
---@return table[] rows
function ORM.raw(sql, params)
    params = params or {}
    Logger.query(sql, params)
    return defaultAdapter:execute(sql, params) or {}
end

--- Execute a raw SQL statement (INSERT/UPDATE/DELETE).
---@param sql string
---@param params? any[]
---@return any
function ORM.rawExec(sql, params)
    params = params or {}
    Logger.query(sql, params)
    return defaultAdapter:scalar(sql, params)
end

--- Enable or disable debug mode (logs all SQL queries).
---@param enabled boolean
function ORM.debug(enabled)
    Logger.setEnabled(enabled)
end

--- Registered migrations list.
---@type OrvexMigration[]
local registeredMigrations = {}

--- Register one or more migrations.
---@param migrations OrvexMigration[]
function ORM.migrations(migrations)
    for _, mig in ipairs(migrations) do
        registeredMigrations[#registeredMigrations + 1] = mig
    end
end

--- Run all pending migrations.
---@param adapter? OrvexAdapter
---@return number count
function ORM.migrate(adapter)
    return Migration.migrate(registeredMigrations, adapter or defaultAdapter)
end

--- Rollback the last batch of migrations.
---@param adapter? OrvexAdapter
---@return number count
function ORM.rollback(adapter)
    return Migration.rollback(registeredMigrations, adapter or defaultAdapter)
end

--- Create the schema builder for use in migrations.
---@return OrvexSchemaBuilder
function ORM.schema()
    return Migration.SchemaBuilder.new()
end

--- Run a seed function.
---@param fn fun(orm: OrvexORM)
function ORM.seed(fn)
    Logger.info("Running seed...")
    fn(ORM)
    Logger.info("Seed complete.")
end

-- ─── MySQL type → OrvexFieldType mapping ─────────────────────────

local mysqlTypeMap = {
    int       = "number",
    bigint    = "number",
    tinyint   = "number",
    smallint  = "number",
    mediumint = "number",
    float     = "number",
    double    = "number",
    decimal   = "number",
    varchar   = "string",
    char      = "string",
    text      = "string",
    tinytext  = "string",
    mediumtext = "string",
    longtext  = "string",
    enum      = "string",
    set       = "string",
    date      = "date",
    datetime  = "datetime",
    timestamp = "timestamp",
    time      = "string",
    year      = "string",
    json      = "json",
    blob      = "string",
    tinyblob  = "string",
    mediumblob = "string",
    longblob  = "string",
    boolean   = "boolean",
    bool      = "boolean",
    bit       = "boolean",
}

--- Parse a MySQL type string (e.g. "varchar(255)", "int(11) unsigned") to a base type name.
---@param mysqlType string
---@return string baseType
local function parseBaseType(mysqlType)
    local base = mysqlType:lower():match("^(%a+)")
    return base or "string"
end

--- Introspect an existing MySQL table and return its field definitions.
--- Runs DESCRIBE <tableName> and maps MySQL types to OrvexFieldType.
---@param tableName string
---@param adapter? OrvexAdapter
---@return table<string, OrvexFieldType> fields
---@return string primaryKey
function ORM.introspect(tableName, adapter)
    adapter = adapter or defaultAdapter
    Helpers.assertSafeIdentifier(tableName)
    local sql = "DESCRIBE `" .. tableName .. "`"
    Logger.query(sql, {})
    local rows = adapter:execute(sql, {})
    assert(rows and #rows > 0, ("Table '%s' not found or empty"):format(tableName))

    local fields = {}
    local pk = "id"

    for _, row in ipairs(rows) do
        local fieldName = row.Field
        local fieldType = row.Type
        local key = row.Key

        local baseType = parseBaseType(fieldType)
        local orvexType = mysqlTypeMap[baseType] or "string"

        -- tinyint(1) is typically used as boolean in MySQL
        if baseType == "tinyint" and fieldType:match("%(1%)") then
            orvexType = "boolean"
        end

        fields[fieldName] = orvexType

        if key == "PRI" then
            pk = fieldName
        end
    end

    return fields, pk
end

--- Introspect a table and return a ready-to-use OrvexModel.
---@param tableName string
---@param opts? OrvexModelOpts
---@return OrvexModel
function ORM.fromTable(tableName, opts)
    opts = opts or {}
    local adapter = opts.adapter or defaultAdapter
    local fields, pk = ORM.introspect(tableName, adapter)
    opts.primaryKey = opts.primaryKey or pk
    return ORM.model(tableName, fields, opts)
end

--- Unpack commonly used functions for shorter syntax.
---@return function model, function raw, function migrate, function transaction
function ORM.unpack()
    return ORM.model, ORM.raw, ORM.migrate, ORM.transaction
end

return ORM
