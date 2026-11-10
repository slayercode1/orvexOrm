-- core/orm.lua

-- luacheck: read globals GetResourceMetadata

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

--- Name of the resource that ships the ORM. Not GetCurrentResourceName():
--- lib/import.lua runs this file inside consumer resources too.
local ORVEX_RESOURCE = "orvexorm"

--- fxmanifest.lua is the single source of the version. Outside FiveM
--- (tests, tooling) there is no resource metadata, hence the fallback.
---@return string
local function resourceVersion()
    if type(GetResourceMetadata) ~= "function" then
        return "dev"
    end
    return GetResourceMetadata(ORVEX_RESOURCE, "version", 0) or "dev"
end

ORM.version = resourceVersion()

---@type OrvexAdapter
local defaultAdapter = Adapter.new(MySQLDriver.new())

---@type OrvexCache
local globalCache = Cache.new({ ttl = 60, enabled = false })

--- Operator condition for a table-form where:
--- `User.findAll({ money = ORM.op(">", 1000) })`. Only values built here
--- are read as operators; any other table value raises, so data shaped
--- like `{ "LIKE", "%" }` (e.g. a client's net-event argument) can never
--- turn an equality into another comparison.
ORM.op = Helpers.op

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

--- If a function is passed, it is called with the transaction and auto-committed.
--- On error, the transaction is not committed and the error is re-raised.
--- After a successful commit, the shared model cache drops the entries of
--- every table the transaction wrote (all entries for raw statements whose
--- tables cannot be told). Models built with their own `opts.cache` are
--- not covered: call `Model.flushCache()` on them.
--- Without a function, returns the transaction to fill and `commit()`.
---@param adapterOrFn fun(tx: OrvexTransaction)
---@param adapter? OrvexAdapter
---@return boolean success
---@overload fun(adapter?: OrvexAdapter): OrvexTransaction
function ORM.transaction(adapterOrFn, adapter)
    if type(adapterOrFn) == "function" then
        local tx = Transaction.new(adapter or defaultAdapter, globalCache)
        adapterOrFn(tx)
        return tx:commit()
    end

    return Transaction.new(adapterOrFn or defaultAdapter, globalCache)
end

---@param opts? { ttl?: number }
function ORM.enableCache(opts)
    opts = opts or {}
    if opts.ttl then
        globalCache._ttl = opts.ttl
    end
    globalCache:setEnabled(true)
end

function ORM.disableCache()
    globalCache:setEnabled(false)
end

function ORM.flushCache()
    globalCache:flush()
end

---@return OrvexCacheStats
function ORM.cacheStats()
    return globalCache:stats()
end

---@param adapter OrvexAdapter
function ORM.setAdapter(adapter)
    defaultAdapter = adapter
end

--- Raw SQL bypasses the models, so a write invalidates the shared cache
--- for the table it names, or flushes it when the table cannot be told.
---@param sql string
---@param params? any[]
---@return table[] rows
function ORM.raw(sql, params)
    params = params or {}
    Logger.query(sql, params)
    local rows = defaultAdapter:execute(sql, params) or {}
    Transaction.invalidateWritten(globalCache, sql)
    return rows
end

--- See `ORM.raw` for the cache invalidation.
---@param sql string
---@param params? any[]
---@return any
function ORM.rawExec(sql, params)
    params = params or {}
    Logger.query(sql, params)
    local result = defaultAdapter:scalar(sql, params)
    Transaction.invalidateWritten(globalCache, sql)
    return result
end

---@param enabled boolean
function ORM.debug(enabled)
    Logger.setEnabled(enabled)
end

---@type OrvexMigration[]
local registeredMigrations = {}

---@param migrations OrvexMigration[]
function ORM.migrations(migrations)
    for _, mig in ipairs(migrations) do
        registeredMigrations[#registeredMigrations + 1] = mig
    end
end

---@param adapter? OrvexAdapter
---@return number count
function ORM.migrate(adapter)
    return Migration.migrate(registeredMigrations, adapter or defaultAdapter)
end

---@param adapter? OrvexAdapter
---@return number count
function ORM.rollback(adapter)
    return Migration.rollback(registeredMigrations, adapter or defaultAdapter)
end

---@return OrvexSchemaBuilder
function ORM.schema()
    return Migration.SchemaBuilder.new()
end

---@param fn fun(orm: OrvexORM)
function ORM.seed(fn)
    Logger.info("Running seed...")
    fn(ORM)
    Logger.info("Seed complete.")
end

-- ─── MySQL type -> OrvexFieldType mapping ─────────────────────────

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

---@param mysqlType string
---@return string baseType
local function parseBaseType(mysqlType)
    local base = mysqlType:lower():match("^(%a+)")
    return base or "string"
end

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
    Helpers.ensure(rows and #rows > 0, ("Table '%s' not found or empty"):format(tableName))

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

---@param tableName string
---@param opts? OrvexModelOpts
---@return OrvexModel
function ORM.fromTable(tableName, opts)
    -- Copy: the detected primary key must not leak into the caller's opts.
    opts = Helpers.shallowCopy(opts or {})
    local adapter = opts.adapter or defaultAdapter
    local fields, pk = ORM.introspect(tableName, adapter)
    opts.primaryKey = opts.primaryKey or pk
    return ORM.model(tableName, fields, opts)
end

---@return fun(tableName: string, fields: table<string, OrvexFieldType>, opts?: OrvexModelOpts): OrvexModel model
---@return fun(sql: string, params?: any[]): table[] raw
---@return fun(adapter?: OrvexAdapter): number migrate
---@return (fun(fn: fun(tx: OrvexTransaction), adapter?: OrvexAdapter): boolean)|(fun(adapter?: OrvexAdapter): OrvexTransaction) transaction
function ORM.unpack()
    return ORM.model, ORM.raw, ORM.migrate, ORM.transaction
end

OrvexORM = ORM
return ORM
