-- core/model.lua
-- Model factory.  Each call to Model.new() returns a typed model class.

local Query        = OrvexQuery or require("core.query")
local SchemaLib    = OrvexSchema or require("core.schema")
local Validator    = OrvexValidator or require("utils.validator")
local Serializer   = OrvexSerializer or require("utils.serializer")
local Helpers      = OrvexHelpers or require("utils.helpers")
local Relations    = OrvexRelations or require("core.relations")
local Builder      = OrvexBuilder or require("core.builder")
local CacheLib     = OrvexCache or require("utils.cache")
local MigrationLib = OrvexMigration or require("core.migration")
local Logger       = OrvexLogger or require("utils.logger")

---@class OrvexModelFactory
local Model = {}

-- ─── Instance class ────────────────────────────────────────────────

---@class OrvexInstance
---@field [string] any
---@field private _tableName string
---@field private _schema OrvexSchema
---@field private _adapter OrvexAdapter
---@field private _cache OrvexCache
---@field private _where table<string, any>
---@field private _relations table<string, OrvexRelationDef>
---@field private _hooks table
---@field private _softDelete boolean
---@field private _timestamps boolean
local Instance = {}
Instance.__index = Instance

--- Fire all registered hooks for an event.
---@param hooks table
---@param event string
---@param ... any
local function fireHooks(hooks, event, ...)
    if hooks and hooks[event] then
        for _, fn in ipairs(hooks[event]) do fn(...) end
    end
end

--- Execute a write query on an instance (Logger + adapter + cache invalidation).
---@param self OrvexInstance
---@param q table  Query object with .sql and .params
function Instance:_exec(q)
    Logger.query(q.sql, q.params)
    self._adapter:scalar(q.sql, q.params)
    self._cache:invalidateTable(self._tableName)
end

--- Execute a raw write query on an instance (Logger + adapter + cache invalidation).
---@param self OrvexInstance
---@param sql string
---@param params table
function Instance:_execRaw(sql, params)
    Logger.query(sql, params)
    self._adapter:scalar(sql, params)
    self._cache:invalidateTable(self._tableName)
end

--- Update this instance in the database and mirror changes locally.
---@param data table<string, any>
---@return boolean success
function Instance:update(data)
    fireHooks(self._hooks, "beforeUpdate", self, data)

    local ok, err = Validator.validate(data, self._schema.fields)
    if not ok then error(err) end

    if self._timestamps then
        data.updated_at = os.date("!%Y-%m-%d %H:%M:%S")
    end

    -- Encode only json/auto fields
    local encoded = data
    local decodeFields = self._schema.decodeFields
    if decodeFields and #decodeFields > 0 then
        encoded = {}
        for k, v in pairs(data) do
            local ft = self._schema.fields[k]
            if (ft == "json" or ft == "auto") and v ~= nil and type(v) == "table" then
                encoded[k] = json.encode(v)
            else
                encoded[k] = v
            end
        end
    end

    self:_exec(Query.update(self._tableName, encoded, self._where))

    for k, v in pairs(data) do
        self[k] = v
    end

    fireHooks(self._hooks, "afterUpdate", self)

    return true
end

--- Delete this instance from the database.
---@return boolean success
function Instance:delete()
    fireHooks(self._hooks, "beforeDelete", self)

    if self._softDelete then
        local now = os.date("!%Y-%m-%d %H:%M:%S")
        self:_exec(Query.update(self._tableName, { deleted_at = now }, self._where))
        self.deleted_at = now
    else
        self:_exec(Query.delete(self._tableName, self._where))
    end

    fireHooks(self._hooks, "afterDelete", self)

    return true
end

--- Force-delete this instance (bypasses soft delete).
---@return boolean success
function Instance:forceDelete()
    fireHooks(self._hooks, "beforeDelete", self)
    self:_exec(Query.delete(self._tableName, self._where))
    fireHooks(self._hooks, "afterDelete", self)
    return true
end

--- Restore a soft-deleted instance.
---@return boolean success
function Instance:restore()
    assert(self._softDelete, "restore() requires soft delete to be enabled")
    local whereKeys = Helpers.sortedKeys(self._where)
    local whereParts, params = {}, {}
    for i, k in ipairs(whereKeys) do
        whereParts[i] = k .. " = ?"
        params[#params + 1] = self._where[k]
    end
    local sql = ("UPDATE `%s` SET deleted_at = NULL WHERE %s"):format(
        self._tableName, table.concat(whereParts, " AND ")
    )
    self:_execRaw(sql, params)
    self.deleted_at = nil
    return true
end

--- Internal helper for increment/decrement on an instance.
---@param self OrvexInstance
---@param column string
---@param amount number
---@param op string  "+" or "-"
---@return boolean
local function adjustColumn(self, column, amount, op)
    local q = (op == "+" and Query.increment or Query.decrement)(self._tableName, column, amount, self._where)
    self:_exec(q)
    if self[column] then
        self[column] = self[column] + (op == "+" and amount or -amount)
    end
    return true
end

--- Increment a column value.
---@param column string
---@param amount? number  Default 1
---@return boolean
function Instance:increment(column, amount)
    return adjustColumn(self, column, amount or 1, "+")
end

--- Decrement a column value.
---@param column string
---@param amount? number  Default 1
---@return boolean
function Instance:decrement(column, amount)
    return adjustColumn(self, column, amount or 1, "-")
end

--- Fetch a related model by relation name.
---@param name string
---@return OrvexInstance|OrvexInstance[]|nil
function Instance:get(name)
    local rel = self._relations[name]
    assert(rel, ("Unknown relation '%s'"):format(name))

    if rel.type == Relations.HAS_ONE then
        return Relations.fetchHasOne(self, rel)
    elseif rel.type == Relations.HAS_MANY then
        return Relations.fetchHasMany(self, rel)
    elseif rel.type == Relations.BELONGS_TO then
        return Relations.fetchBelongsTo(self, rel)
    elseif rel.type == Relations.BELONGS_TO_MANY then
        return Relations.fetchBelongsToMany(self, rel)
    else
        error(("Unsupported relation type '%s'"):format(rel.type))
    end
end

--- Attach a related instance through a belongsToMany pivot table.
---@param name string
---@param relatedInstance OrvexInstance|table
---@return boolean
function Instance:attach(name, relatedInstance)
    local rel = self._relations[name]
    assert(rel, ("Unknown relation '%s'"):format(name))
    assert(rel.type == Relations.BELONGS_TO_MANY, "attach() only works on belongsToMany relations")
    local result = Relations.attach(self, rel, relatedInstance)
    self._cache:invalidateTable(rel.pivot)
    return result
end

--- Detach a related instance from a belongsToMany pivot table.
---@param name string
---@param relatedInstance OrvexInstance|table
---@return boolean
function Instance:detach(name, relatedInstance)
    local rel = self._relations[name]
    assert(rel, ("Unknown relation '%s'"):format(name))
    assert(rel.type == Relations.BELONGS_TO_MANY, "detach() only works on belongsToMany relations")
    local result = Relations.detach(self, rel, relatedInstance)
    self._cache:invalidateTable(rel.pivot)
    return result
end

-- ─── Private helpers ───────────────────────────────────────────────

---@param row table
---@param tableName string
---@param schema OrvexSchema
---@param adapter OrvexAdapter
---@param primaryKey string
---@param relations table<string, OrvexRelationDef>
---@param cache OrvexCache
---@param hooks table
---@param softDelete boolean
---@param timestamps boolean
---@return OrvexInstance
local function wrapRow(row, tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)
    -- Only decode json/auto fields (pre-computed list, skips string/number/boolean)
    local decodeFields = schema.decodeFields
    if decodeFields then
        for i = 1, #decodeFields do
            local df = decodeFields[i]
            local val = row[df.name]
            if val ~= nil then
                row[df.name] = Serializer.decode(val, df.type)
            end
        end
    end

    row._tableName  = tableName
    row._schema     = schema
    row._adapter    = adapter
    row._cache      = cache
    row._where      = { [primaryKey] = row[primaryKey] }
    row._relations  = relations
    row._hooks      = hooks
    row._softDelete = softDelete
    row._timestamps = timestamps

    return setmetatable(row, Instance)
end

-- ─── Model options ─────────────────────────────────────────────────

---@class OrvexModelOpts
---@field primaryKey? string       Primary key column name (default "id")
---@field adapter? OrvexAdapter    Custom adapter (overrides the default)
---@field cache? OrvexCache        Custom cache instance
---@field softDelete? boolean      Enable soft delete (adds deleted_at)
---@field timestamps? boolean      Auto-manage created_at and updated_at

---@class OrvexHasOneOpts
---@field foreignKey string
---@field localKey? string

---@class OrvexHasManyOpts
---@field foreignKey string
---@field localKey? string

---@class OrvexBelongsToOpts
---@field foreignKey string
---@field ownerKey? string

---@class OrvexBelongsToManyOpts
---@field pivot string
---@field foreignKey string
---@field otherKey string
---@field localKey? string

-- ─── Model class ──────────────────────────────────────────────────

---@class OrvexModel
---@field _tableName string
---@field _schema OrvexSchema
---@field _adapter OrvexAdapter
---@field _primaryKey string
---@field _cache OrvexCache
---@field _wrapRow fun(row: table): OrvexInstance

--- Build a column list from a select option, ensuring primaryKey is included.
---@param selectOpt? string[]
---@param pk string
---@return string
local function buildColumns(selectOpt, pk)
    if not selectOpt then return "*" end
    local cols = {}
    local hasPK = false
    for _, c in ipairs(selectOpt) do
        cols[#cols + 1] = c
        if c == pk then hasPK = true end
    end
    if not hasPK then cols[#cols + 1] = pk end
    return table.concat(cols, ", ")
end

-- ─── Model class factory ───────────────────────────────────────────

--- Create a new Model "class" bound to a table and schema.
---@param tableName string
---@param fields table<string, OrvexFieldType>
---@param adapter OrvexAdapter
---@param opts? OrvexModelOpts
---@param cache? OrvexCache
---@return OrvexModel
function Model.new(tableName, fields, adapter, opts, cache)
    opts = opts or {}
    local primaryKey = opts.primaryKey or "id"
    cache = cache or CacheLib.new({ enabled = false })
    local softDelete = opts.softDelete or false
    local timestamps = opts.timestamps or false

    local schema = SchemaLib.new(fields)
    local relations = {} ---@type table<string, OrvexRelationDef>
    local hooks = {}     ---@type table<string, function[]>
    local scopes = {}    ---@type table<string, function>

    ---@type OrvexModel
    local M = {}

    M._tableName  = tableName
    M._schema     = schema
    M._adapter    = adapter
    M._primaryKey = primaryKey
    M._cache      = cache

    function M._wrapRow(row)
        return wrapRow(row, tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)
    end

    -- ─── Write helpers ─────────────────────────────────────────

    --- Execute a write query (Logger + adapter + cache invalidation).
    ---@param q table  Query object with .sql and .params
    local function execWrite(q)
        Logger.query(q.sql, q.params)
        adapter:scalar(q.sql, q.params)
        cache:invalidateTable(tableName)
    end

    --- Execute a raw write query (Logger + adapter + cache invalidation).
    ---@param sql string
    ---@param params table
    local function execWriteRaw(sql, params)
        Logger.query(sql, params)
        adapter:scalar(sql, params)
        cache:invalidateTable(tableName)
    end

    -- ─── Hooks ──────────────────────────────────────────────────

    --- Register a lifecycle hook.
    ---@param event string  "beforeCreate"|"afterCreate"|"beforeUpdate"|"afterUpdate"|"beforeDelete"|"afterDelete"
    ---@param fn function
    function M.hook(event, fn)
        if not hooks[event] then
            hooks[event] = {}
        end
        hooks[event][#hooks[event] + 1] = fn
    end

    --- Shorthand hook registrations.
    function M.beforeCreate(fn) M.hook("beforeCreate", fn) end
    function M.afterCreate(fn) M.hook("afterCreate", fn) end
    function M.beforeUpdate(fn) M.hook("beforeUpdate", fn) end
    function M.afterUpdate(fn) M.hook("afterUpdate", fn) end
    function M.beforeDelete(fn) M.hook("beforeDelete", fn) end
    function M.afterDelete(fn) M.hook("afterDelete", fn) end

    -- Register inline hooks from opts
    if opts.hooks then
        for event, fn in pairs(opts.hooks) do
            M.hook(event, fn)
        end
    end

    -- ─── Scopes ─────────────────────────────────────────────────

    --- Register a named scope (reusable query filter).
    --- Also adds a direct method on the model: Model.scopeName() → builder.
    ---@param name string
    ---@param fn fun(builder: OrvexBuilder): OrvexBuilder
    function M.scope(name, fn)
        scopes[name] = fn
        -- Add scope as a direct method on the model
        M[name] = function()
            local b = M.query()
            fn(b)
            return b
        end
    end

    --- Get a query builder with a named scope applied.
    ---@param name string
    ---@return OrvexBuilder
    function M.scoped(name)
        local fn = scopes[name]
        assert(fn, ("Unknown scope '%s'"):format(name))
        local b = M.query()
        fn(b)
        return b
    end

    -- Register inline scopes from opts
    if opts.scopes then
        for name, fn in pairs(opts.scopes) do
            M.scope(name, fn)
        end
    end

    -- ─── Relation definitions ──────────────────────────────────────

    function M.hasOne(name, relatedModel, ropts)
        ropts = ropts or {}
        relations[name] = {
            type       = Relations.HAS_ONE,
            model      = relatedModel,
            foreignKey = ropts.foreignKey,
            localKey   = ropts.localKey or primaryKey,
        }
    end

    function M.hasMany(name, relatedModel, ropts)
        ropts = ropts or {}
        relations[name] = {
            type       = Relations.HAS_MANY,
            model      = relatedModel,
            foreignKey = ropts.foreignKey,
            localKey   = ropts.localKey or primaryKey,
        }
    end

    function M.belongsTo(name, relatedModel, ropts)
        ropts = ropts or {}
        relations[name] = {
            type       = Relations.BELONGS_TO,
            model      = relatedModel,
            foreignKey = ropts.foreignKey,
            ownerKey   = ropts.ownerKey or relatedModel._primaryKey,
        }
    end

    function M.belongsToMany(name, relatedModel, ropts)
        ropts = ropts or {}
        assert(ropts.pivot, "belongsToMany requires a pivot table name")
        relations[name] = {
            type       = Relations.BELONGS_TO_MANY,
            model      = relatedModel,
            pivot      = ropts.pivot,
            foreignKey = ropts.foreignKey,
            otherKey   = ropts.otherKey,
            localKey   = ropts.localKey or primaryKey,
        }
    end

    -- ─── Inline relations from opts ──────────────────────────────────
    -- Deferred: registered via opts.relations callback after all models are created.
    -- Call: opts.relations(M) to register relations.
    if opts.relations then
        -- Store for deferred resolution (relations may reference other models not yet created)
        M._pendingRelations = opts.relations
    end

    --- Apply pending relations (call after all models are created).
    function M.applyRelations()
        if M._pendingRelations then
            M._pendingRelations(M)
            M._pendingRelations = nil
        end
    end

    -- ─── CRUD methods ──────────────────────────────────────────────

    -- Pre-compute set of fields that need encoding (json/auto only)
    local encodeNeeded = {}
    for name, fieldType in pairs(schema.fields) do
        if fieldType == "json" or fieldType == "auto" then
            encodeNeeded[name] = fieldType
        end
    end
    local hasEncodeFields = next(encodeNeeded) ~= nil

    --- Fast encode: only encodes json/auto fields that are tables.
    --- Modifies a COPY only when needed, otherwise returns data as-is.
    ---@param data table
    ---@return table
    local function fastEncode(data)
        if not hasEncodeFields then return data end
        -- Check if any json/auto field in data actually needs encoding
        local needsCopy = false
        for name in pairs(encodeNeeded) do
            if data[name] ~= nil and type(data[name]) == "table" then
                needsCopy = true
                break
            end
        end
        if not needsCopy then return data end
        -- Only copy+encode when at least one field needs it
        local encoded = {}
        for k, v in pairs(data) do
            if encodeNeeded[k] and type(v) == "table" then
                encoded[k] = json.encode(v)
            else
                encoded[k] = v
            end
        end
        return encoded
    end

    ---@param data table<string, any>
    ---@return OrvexInstance
    function M.create(data)
        fireHooks(hooks, "beforeCreate", data)

        local ok, err = Validator.validate(data, schema.fields)
        if not ok then error(err) end

        if timestamps then
            local now = os.date("!%Y-%m-%d %H:%M:%S")
            data.created_at = data.created_at or now
            data.updated_at = data.updated_at or now
        end

        local encoded = fastEncode(data)

        local q = Query.insert(tableName, encoded)
        Logger.query(q.sql, q.params)
        local insertId = adapter:scalar(q.sql, q.params)

        if data[primaryKey] == nil and insertId then
            data[primaryKey] = insertId
        end

        cache:invalidateTable(tableName)

        local instance = wrapRow(Helpers.shallowCopy(data), tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)

        fireHooks(hooks, "afterCreate", instance)

        return instance
    end

    --- Create multiple rows in a single query.
    ---@param rows table[]
    ---@return boolean
    function M.createMany(rows)
        assert(#rows > 0, "createMany requires at least one row")

        for _, row in ipairs(rows) do
            local ok, err = Validator.validate(row, schema.fields)
            if not ok then error(err) end

            if timestamps then
                local now = os.date("!%Y-%m-%d %H:%M:%S")
                row.created_at = row.created_at or now
                row.updated_at = row.updated_at or now
            end
        end

        local encodedRows = {}
        for i, row in ipairs(rows) do
            encodedRows[i] = fastEncode(row)
        end

        execWrite(Query.insertMany(tableName, encodedRows))
        return true
    end

    ---@param where table<string, any>
    ---@param findOpts? { select?: string[], include?: string[] }
    ---@return OrvexInstance|nil
    function M.find(where, findOpts)
        findOpts = findOpts or {}
        local columns = buildColumns(findOpts.select, primaryKey)

        if softDelete then
            where = Helpers.shallowCopy(where)
            if where.deleted_at == nil then
                local b = M.query()
                if columns ~= "*" then b:select(columns) end
                for k, v in pairs(where) do
                    b:where({ [k] = v })
                end
                b:whereNull("deleted_at")
                b:limit(1)
                local results = b:get()
                local instance = results[1] or nil
                if instance and findOpts.include then
                    M._eagerLoad(instance, findOpts.include)
                end
                return instance
            end
        end

        local q = Query.select(tableName, where, columns)

        local cacheKey = CacheLib.makeKey(q.sql, q.params)
        local cached, hit = cache:get(cacheKey)
        if hit then
            if not cached or #cached == 0 then return nil end
            local instance = wrapRow(Helpers.shallowCopy(cached[1]), tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)
            if findOpts.include then
                M._eagerLoad(instance, findOpts.include)
            end
            return instance
        end

        Logger.query(q.sql, q.params)
        local rows = adapter:execute(q.sql, q.params)
        cache:set(cacheKey, rows)

        if not rows or #rows == 0 then
            return nil
        end

        local instance = wrapRow(rows[1], tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)
        if findOpts.include then
            M._eagerLoad(instance, findOpts.include)
        end
        return instance
    end

    --- Check if a where table contains operator values (tables like { ">", 1000 }).
    ---@param where table
    ---@return boolean
    local function hasOperatorValues(where)
        for _, v in pairs(where) do
            if type(v) == "table" then return true end
        end
        return false
    end

    ---@param where table<string, any>
    ---@param findOpts? { select?: string[] }
    ---@return OrvexInstance[]
    function M.findAll(where, findOpts)
        findOpts = findOpts or {}
        local columns = buildColumns(findOpts.select, primaryKey)

        -- Use builder when operator values are present or soft delete is active
        if softDelete or hasOperatorValues(where) then
            local b = M.query()
            if columns ~= "*" then b:select(columns) end
            for k, v in pairs(where) do
                b:where({ [k] = v })
            end
            if softDelete then
                -- softDelete whereNull is already added by M.query()
            end
            return b:get()
        end

        local q = Query.select(tableName, where, columns)

        local cacheKey = CacheLib.makeKey(q.sql, q.params)
        local cached, hit = cache:get(cacheKey)
        if hit then
            if not cached then return {} end
            local results = {}
            for i, row in ipairs(cached) do
                results[i] = wrapRow(Helpers.shallowCopy(row), tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)
            end
            return results
        end

        Logger.query(q.sql, q.params)
        local rows = adapter:execute(q.sql, q.params)
        cache:set(cacheKey, rows)

        if not rows then return {} end

        local results = {}
        for i, row in ipairs(rows) do
            results[i] = wrapRow(row, tableName, schema, adapter, primaryKey, relations, cache, hooks, softDelete, timestamps)
        end
        return results
    end

    ---@param data table<string, any>
    ---@return boolean
    function M.upsert(data)
        local ok, err = Validator.validate(data, schema.fields)
        if not ok then error(err) end

        if timestamps then
            local now = os.date("!%Y-%m-%d %H:%M:%S")
            data.created_at = data.created_at or now
            data.updated_at = data.updated_at or now
        end

        local encoded = fastEncode(data)

        execWrite(Query.upsert(tableName, encoded))
        return true
    end

    ---@param data table<string, any>
    ---@param where table<string, any>
    ---@return boolean
    function M.update(data, where)
        assert(where and next(where), "update() requires a where clause")

        local ok, err = Validator.validate(data, schema.fields)
        if not ok then error(err) end

        if timestamps then
            data.updated_at = data.updated_at or os.date("!%Y-%m-%d %H:%M:%S")
        end

        local encoded = fastEncode(data)

        execWrite(Query.update(tableName, encoded, where))
        return true
    end

    ---@param where table<string, any>
    ---@return boolean
    function M.delete(where)
        assert(where and next(where), "delete() requires a where clause")
        if softDelete then
            local now = os.date("!%Y-%m-%d %H:%M:%S")
            execWrite(Query.update(tableName, { deleted_at = now }, where))
        else
            execWrite(Query.delete(tableName, where))
        end
        return true
    end

    --- Force delete (bypasses soft delete).
    ---@param where table<string, any>
    ---@return boolean
    function M.forceDelete(where)
        assert(where and next(where), "forceDelete() requires a where clause")
        execWrite(Query.delete(tableName, where))
        return true
    end

    --- Restore soft-deleted rows.
    ---@param where table<string, any>
    ---@return boolean
    function M.restore(where)
        assert(softDelete, "restore() requires soft delete to be enabled")
        local whereKeys = Helpers.sortedKeys(where)
        local whereParts = {}
        local params = {}
        for i, k in ipairs(whereKeys) do
            whereParts[i] = k .. " = ?"
            params[#params + 1] = where[k]
        end
        local sql = ("UPDATE %s SET deleted_at = NULL WHERE %s"):format(
            tableName, table.concat(whereParts, " AND ")
        )
        execWriteRaw(sql, params)
        return true
    end

    -- ─── Find or Create ────────────────────────────────────────────

    --- Find a record or create it if it doesn't exist.
    ---@param where table<string, any>
    ---@param defaults? table<string, any>  Extra fields for creation
    ---@return OrvexInstance instance
    ---@return boolean created  true if a new record was created
    function M.findOrCreate(where, defaults)
        local existing = M.find(where)
        if existing then
            return existing, false
        end
        local data = Helpers.shallowCopy(where)
        if defaults then
            for k, v in pairs(defaults) do
                data[k] = v
            end
        end
        return M.create(data), true
    end

    --- Update an existing record or create a new one. Returns the instance.
    ---@param where table<string, any>
    ---@param data table<string, any>
    ---@return OrvexInstance instance
    ---@return boolean created
    function M.updateOrCreate(where, data)
        local existing = M.find(where)
        if existing then
            existing:update(data)
            return existing, false
        end
        local fullData = Helpers.shallowCopy(where)
        for k, v in pairs(data) do
            fullData[k] = v
        end
        return M.create(fullData), true
    end

    -- ─── Increment / Decrement ─────────────────────────────────────

    --- Internal helper for class-level increment/decrement.
    local function classAdjust(column, amount, where, op)
        assert(where and next(where), op .. "() requires a where clause")
        local q = (op == "increment" and Query.increment or Query.decrement)(tableName, column, amount, where)
        execWrite(q)
        return true
    end

    --- Increment a column for matching rows.
    ---@param column string
    ---@param amount number
    ---@param where table<string, any>
    ---@return boolean
    function M.increment(column, amount, where)
        return classAdjust(column, amount, where, "increment")
    end

    --- Decrement a column for matching rows.
    ---@param column string
    ---@param amount number
    ---@param where table<string, any>
    ---@return boolean
    function M.decrement(column, amount, where)
        return classAdjust(column, amount, where, "decrement")
    end

    -- ─── Eager loading helper ──────────────────────────────────────

    --- Load relations onto an instance.
    ---@param instance OrvexInstance
    ---@param relationNames string[]
    function M._eagerLoad(instance, relationNames)
        for _, name in ipairs(relationNames) do
            local rel = relations[name]
            if rel then
                instance[name] = instance:get(name)
            end
        end
    end

    -- ─── whereHas ────────────────────────────────────────────────────

    --- Filter by relation existence: returns a builder with WHERE EXISTS.
    ---@param relationName string
    ---@param callback? fun(builder: OrvexBuilder): OrvexBuilder  Optional extra conditions on the related query
    ---@return OrvexBuilder
    function M.whereHas(relationName, callback)
        local rel = relations[relationName]
        assert(rel, ("Unknown relation '%s'"):format(relationName))

        local b = M.query()

        local subSQL, subParams

        if rel.type == Relations.HAS_ONE or rel.type == Relations.HAS_MANY then
            -- SELECT 1 FROM related WHERE related.foreignKey = parent.localKey
            local localKey = rel.localKey or primaryKey
            subSQL = ("SELECT 1 FROM %s WHERE %s.%s = %s.%s"):format(
                rel.model._tableName,
                rel.model._tableName, rel.foreignKey,
                tableName, localKey
            )
            subParams = {}
        elseif rel.type == Relations.BELONGS_TO then
            local ownerKey = rel.ownerKey or rel.model._primaryKey
            subSQL = ("SELECT 1 FROM %s WHERE %s.%s = %s.%s"):format(
                rel.model._tableName,
                rel.model._tableName, ownerKey,
                tableName, rel.foreignKey
            )
            subParams = {}
        elseif rel.type == Relations.BELONGS_TO_MANY then
            local localKey = rel.localKey or primaryKey
            subSQL = ("SELECT 1 FROM %s WHERE %s.%s = %s.%s"):format(
                rel.pivot,
                rel.pivot, rel.foreignKey,
                tableName, localKey
            )
            subParams = {}
        else
            error(("whereHas not supported for relation type '%s'"):format(rel.type))
        end

        if callback then
            local innerBuilder = Builder.new(rel.model._tableName, adapter, nil, nil)
            callback(innerBuilder)
            local innerWhere, innerParams = innerBuilder:_buildWhere()
            if innerWhere ~= "" then
                local stripped = innerWhere:gsub("^%s*WHERE%s+", "")
                subSQL = subSQL .. " AND " .. stripped
                for _, p in ipairs(innerParams) do
                    subParams[#subParams + 1] = p
                end
            end
        end

        b:whereExists(subSQL, subParams)
        return b
    end

    -- ─── Count by relation ───────────────────────────────────────────

    --- Count related records for a given relation.
    ---@param relationName string
    ---@param where? table<string, any>  Optional filter on the parent model
    ---@return integer
    function M.countByRelation(relationName, where)
        local rel = relations[relationName]
        assert(rel, ("Unknown relation '%s'"):format(relationName))
        assert(rel.type ~= Relations.BELONGS_TO, "countByRelation not supported for belongsTo")

        local localKey = rel.localKey or primaryKey

        local b = M.query()
        if where then b:where(where) end
        local results = b:get()

        local counts = {}
        for _, inst in ipairs(results) do
            local countSQL, countParams
            if rel.type == Relations.HAS_ONE or rel.type == Relations.HAS_MANY then
                countSQL = ("SELECT COUNT(*) as cnt FROM %s WHERE %s = ?"):format(
                    rel.model._tableName, rel.foreignKey
                )
                countParams = { inst[localKey] }
            elseif rel.type == Relations.BELONGS_TO_MANY then
                countSQL = ("SELECT COUNT(*) as cnt FROM %s WHERE %s = ?"):format(
                    rel.pivot, rel.foreignKey
                )
                countParams = { inst[localKey] }
            end

            Logger.query(countSQL, countParams)
            local rows = adapter:execute(countSQL, countParams)
            local cnt = (rows and rows[1]) and rows[1].cnt or 0
            inst["_count_" .. relationName] = cnt
            counts[#counts + 1] = { instance = inst, count = cnt }
        end

        return counts
    end

    -- ─── Nested writes ───────────────────────────────────────────────

    --- Create a record with nested related records.
    ---@param data table<string, any>  Fields + relation keys with nested data
    ---@return OrvexInstance
    function M.createWith(data)
        local mainData = {}
        local nestedData = {}

        for k, v in pairs(data) do
            if relations[k] then
                nestedData[k] = v
            else
                mainData[k] = v
            end
        end

        local instance = M.create(mainData)

        for relName, relData in pairs(nestedData) do
            local rel = relations[relName]

            if rel.type == Relations.HAS_ONE then
                local childData = Helpers.shallowCopy(relData)
                childData[rel.foreignKey] = instance[rel.localKey or primaryKey]
                rel.model.create(childData)
            elseif rel.type == Relations.HAS_MANY then
                assert(type(relData) == "table", "hasMany nested data must be an array")
                for _, childRow in ipairs(relData) do
                    local childData = Helpers.shallowCopy(childRow)
                    childData[rel.foreignKey] = instance[rel.localKey or primaryKey]
                    rel.model.create(childData)
                end
            elseif rel.type == Relations.BELONGS_TO_MANY then
                assert(type(relData) == "table", "belongsToMany nested data must be an array")
                for _, relatedData in ipairs(relData) do
                    local related = rel.model.create(relatedData)
                    Relations.attach(instance, rel, related)
                end
            end
        end

        return instance
    end

    -- ─── Query builder ─────────────────────────────────────────────

    ---@return OrvexBuilder
    function M.query()
        local b = Builder.new(tableName, adapter, M._wrapRow, cache)
        if softDelete then
            b:whereNull("deleted_at")
        end
        return b
    end

    --- Query including soft-deleted rows (only relevant if softDelete is enabled).
    ---@return OrvexBuilder
    function M.withTrashed()
        return Builder.new(tableName, adapter, M._wrapRow, cache)
    end

    --- Query only soft-deleted rows.
    ---@return OrvexBuilder
    function M.onlyTrashed()
        local b = Builder.new(tableName, adapter, M._wrapRow, cache)
        b:whereNotNull("deleted_at")
        return b
    end

    -- ─── Aggregate shortcuts ───────────────────────────────────────

    for _, agg in ipairs({"count", "sum", "avg", "min", "max"}) do
        M[agg] = function(columnOrWhere, where)
            local b = M.query()
            if agg == "count" then
                -- count(where?) - first arg is where
                if columnOrWhere then b:where(columnOrWhere) end
                return b:count()
            else
                -- sum/avg/min/max(column, where?)
                if where then b:where(where) end
                return b[agg](b, columnOrWhere)
            end
        end
    end

    -- ─── Extra shortcuts ────────────────────────────────────────────

    --- Find a record or throw an error if not found.
    ---@param where table<string, any>
    ---@param findOpts? { select?: string[], include?: string[] }
    ---@return OrvexInstance
    function M.findOrFail(where, findOpts)
        local result = M.find(where, findOpts)
        if not result then
            local parts = {}
            for k, v in pairs(where) do
                parts[#parts + 1] = k .. "=" .. tostring(v)
            end
            error(("Record not found in '%s' where %s"):format(tableName, table.concat(parts, ", ")))
        end
        return result
    end

    --- Shortcut: find the first record matching where.
    ---@param where? table<string, any>
    ---@return OrvexInstance|nil
    function M.first(where)
        local b = M.query()
        if where then b:where(where) end
        return b:first()
    end

    --- Shortcut: check if any record matches.
    ---@param where table<string, any>
    ---@return boolean
    function M.exists(where)
        local b = M.query()
        if where then b:where(where) end
        return b:exists()
    end

    --- Shortcut: get an array of values for a single column.
    ---@param column string
    ---@param where? table<string, any>
    ---@return any[]
    function M.pluck(column, where)
        local b = M.query()
        if where then b:where(where) end
        return b:pluck(column)
    end

    --- Alias: update with where as first arg (more readable).
    ---@param where table<string, any>
    ---@param data table<string, any>
    ---@return boolean
    function M.updateWhere(where, data)
        return M.update(data, where)
    end

    --- Alias: delete with explicit name.
    ---@param where table<string, any>
    ---@return boolean
    function M.deleteWhere(where)
        return M.delete(where)
    end

    --- Flush this model's cache entries.
    function M.flushCache()
        cache:invalidateTable(tableName)
    end

    --- Sync this model's table: create it if it doesn't exist.
    function M.sync()
        MigrationLib.sync(tableName, fields, primaryKey, adapter)
    end

    return M
end

OrvexModelFactory = Model
return Model
