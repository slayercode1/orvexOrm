-- core/model/instance.lua
-- Instances: one row of a model.
--
-- Layout: an instance table holds only the row's columns (plus eager-loaded
-- relations and `_count_*` values). Each model has ONE metatable shared by
-- all its instances; its __index is the model context (`_tableName`,
-- `_schema`, `_adapter`...) chained to the instance methods. The per-row
-- private state (the key that identifies the row) lives in a weak table,
-- outside the instance.
--
-- Columns named like an instance method (update, get, delete, refresh...)
-- are kept in that private state instead of on the instance, so
-- `inst:update()` always reaches the method. Read them with
-- `inst:getAttribute(name)`; toTable() includes them.

local Query      = OrvexQuery or require("core.query")
local Serializer = OrvexSerializer or require("utils.serializer")
local Helpers    = OrvexHelpers or require("utils.helpers")
local Relations  = OrvexRelations or require("core.relations")
local Logger     = OrvexLogger or require("utils.logger")
local Hooks      = OrvexModelHooks or require("core.model.hooks")
local Write      = OrvexModelWrite or require("core.model.write")

local ensure = Helpers.ensure
local raise  = Helpers.raise

---@class OrvexModelInstanceLib
local InstanceLib = {}

---@class OrvexInstanceState
---@field where table<string, any> identifies the row in UPDATE / DELETE statements
---@field methodColumns? table<string, any> columns whose name is an instance method

--- Private state of every live instance, keyed by instance.
---@type table<OrvexInstance, OrvexInstanceState>
local states = setmetatable({}, { __mode = "k" })

---@class OrvexInstance
---@field [string] any
---@field _tableName string
---@field _schema OrvexSchema
---@field _adapter OrvexAdapter
---@field _cache OrvexCache
---@field _primaryKey string
---@field _relations table<string, OrvexRelationDef>
---@field _hooks table
---@field _softDelete boolean
---@field _timestamps boolean
local Instance = {}

---@param key any
---@return boolean
local function isMethodName(key)
    return Instance[key] ~= nil
end

---@param value any
---@return boolean
function InstanceLib.isInstance(value)
    return type(value) == "table" and states[value] ~= nil
end

--- __newindex: method-named columns go to the private state, so assigning
--- them never replaces the method; any other new key is a plain field.
---@param self OrvexInstance
---@param key any
---@param value any
local function assignField(self, key, value)
    if not isMethodName(key) then
        rawset(self, key, value)
        return
    end
    local state = states[self]
    state.methodColumns = state.methodColumns or {}
    state.methodColumns[key] = value
end

-- ─── Writes ────────────────────────────────────────────────────────

---@param self OrvexInstance
---@param q OrvexQueryResult
---@return integer affected
local function exec(self, q)
    return Write.run(self._adapter, self._cache, self._tableName, q)
end

---@param self OrvexInstance
---@return table<string, any>
local function whereOf(self)
    return states[self].where
end

--- The key a write or reload targets. Without it the statement would have
--- no WHERE (or match another row), so the call is refused; its value is
--- checked as a scalar by core/query.lua.
---@param self OrvexInstance
---@param method string
---@return table<string, any>
local function identityOf(self, method)
    local where = whereOf(self)
    local primaryKey = self._primaryKey
    ensure(where[primaryKey] ~= nil,
        ("%s(): the instance has no '%s' value to identify its row (select the primary key)")
            :format(method, primaryKey))
    return where
end

--- Keeps the row identity in sync when an update changes its key, so the
--- next write still targets the same row.
---@param self OrvexInstance
---@param data table<string, any>
local function syncWhere(self, data)
    local where = whereOf(self)
    for k in pairs(where) do
        if data[k] ~= nil then where[k] = data[k] end
    end
end

---@param self OrvexInstance
---@param row table<string, any>
local function assignColumns(self, row)
    for k, v in pairs(row) do
        self[k] = v
    end
end

---@param data table<string, any>
---@return integer affected rows the driver reports changed (0: none)
function Instance:update(data)
    Write.refuseManagedColumns(data, self._schema, "update")
    data = Helpers.shallowCopy(data)
    Hooks.fire(self._hooks, "beforeUpdate", self, data)

    Write.validate(data, self._schema.allFields)

    if self._timestamps then
        data.updated_at = data.updated_at or Helpers.nowUtc()
    end

    local encoded = Serializer.encodeRow(data, self._schema.encodeSet)

    local affected = exec(self, Query.update(self._tableName, encoded, identityOf(self, "update")))

    assignColumns(self, data)
    syncWhere(self, data)

    Hooks.fire(self._hooks, "afterUpdate", self)

    return affected
end

---@return integer affected
function Instance:delete()
    Hooks.fire(self._hooks, "beforeDelete", self)

    local where = identityOf(self, "delete")
    local affected
    if self._softDelete then
        local now = Helpers.nowUtc()
        affected = exec(self, Query.update(self._tableName, { deleted_at = now }, where))
        self.deleted_at = now
    else
        affected = exec(self, Query.delete(self._tableName, where))
    end

    Hooks.fire(self._hooks, "afterDelete", self)

    return affected
end

---@return integer affected
function Instance:forceDelete()
    Hooks.fire(self._hooks, "beforeDelete", self)
    local affected = exec(self, Query.delete(self._tableName, identityOf(self, "forceDelete")))
    Hooks.fire(self._hooks, "afterDelete", self)
    return affected
end

---@return integer affected
function Instance:restore()
    ensure(self._softDelete, "restore() requires soft delete to be enabled")
    local affected = exec(self, Query.restore(self._tableName, identityOf(self, "restore")))
    self.deleted_at = nil
    return affected
end

---@param self OrvexInstance
---@param column string
---@param amount number
---@param op string
---@return integer affected
local function adjustColumn(self, column, amount, op)
    local method = Query.adjustMethod(op)
    local q = Query[method](self._tableName, column, amount, identityOf(self, method))
    local affected = exec(self, q)
    local current = self:getAttribute(column)
    if current then
        self[column] = current + (op == "+" and amount or -amount)
    end
    return affected
end

--- Unlike the class form `Model.increment(column, amount, where)`, the
--- amount is optional here and defaults to 1.
---@param column string
---@param amount? number
---@return integer affected
function Instance:increment(column, amount)
    return adjustColumn(self, column, amount or 1, "+")
end

---@param column string
---@param amount? number
---@return integer affected
function Instance:decrement(column, amount)
    return adjustColumn(self, column, amount or 1, "-")
end

-- ─── Relations ─────────────────────────────────────────────────────

---@param name string
---@return OrvexInstance|OrvexInstance[]|nil
function Instance:get(name)
    local rel = self._relations[name]
    ensure(rel, ("Unknown relation '%s'"):format(name))

    if rel.type == Relations.HAS_ONE then
        return Relations.fetchHasOne(self, rel)
    elseif rel.type == Relations.HAS_MANY then
        return Relations.fetchHasMany(self, rel)
    elseif rel.type == Relations.BELONGS_TO then
        return Relations.fetchBelongsTo(self, rel)
    elseif rel.type == Relations.BELONGS_TO_MANY then
        return Relations.fetchBelongsToMany(self, rel)
    else
        raise(("Unsupported relation type '%s'"):format(rel.type))
    end
end

---@param self OrvexInstance
---@param name string
---@param method string
---@return OrvexRelationDef
local function pivotRelation(self, name, method)
    local rel = self._relations[name]
    ensure(rel, ("Unknown relation '%s'"):format(name))
    ensure(rel.type == Relations.BELONGS_TO_MANY, method .. "() only works on belongsToMany relations")
    return rel
end

---@param name string
---@param relatedInstance OrvexInstance|table
---@return boolean
function Instance:attach(name, relatedInstance)
    local rel = pivotRelation(self, name, "attach")
    local result = Relations.attach(self, rel, relatedInstance)
    self._cache:invalidateTable(rel.pivot)
    return result
end

---@param name string
---@param relatedInstance OrvexInstance|table
---@return boolean
function Instance:detach(name, relatedInstance)
    local rel = pivotRelation(self, name, "detach")
    local result = Relations.detach(self, rel, relatedInstance)
    self._cache:invalidateTable(rel.pivot)
    return result
end

-- ─── Columns / serialization ───────────────────────────────────────

--- Reads a column, including one named like an instance method, which
--- `inst[name]` would resolve to the method.
---@param name string
---@return any
function Instance:getAttribute(name)
    if isMethodName(name) then
        local methodColumns = states[self].methodColumns
        return methodColumns and methodColumns[name]
    end
    return rawget(self, name)
end

---@param value any
---@return boolean
local function isInstanceList(value)
    return type(value) == "table" and getmetatable(value) == nil and InstanceLib.isInstance(value[1])
end

---@param value any
---@return any
local function plainValue(value)
    if InstanceLib.isInstance(value) then
        return value:toTable()
    elseif isInstanceList(value) then
        local list = {}
        for i, item in ipairs(value) do
            list[i] = item:toTable()
        end
        return list
    end
    return value
end

--- Returns a plain table copy of the columns, without metatable.
--- Safe to json.encode or send through TriggerClientEvent.
--- Eager-loaded relations are converted recursively.
---@return table<string, any>
function Instance:toTable()
    local out = {}
    for k, v in pairs(self) do
        out[k] = plainValue(v)
    end
    local methodColumns = states[self].methodColumns
    if methodColumns then
        for k, v in pairs(methodColumns) do
            out[k] = plainValue(v)
        end
    end
    return out
end

--- Decodes the json / auto columns of a raw row in place (pre-computed
--- list, skips string / number / boolean columns).
---@param row table<string, any>
---@param schema OrvexSchema
function InstanceLib.decodeRow(row, schema)
    local decodeFields = schema.decodeFields
    if not decodeFields then return end
    for i = 1, #decodeFields do
        local df = decodeFields[i]
        local val = row[df.name]
        if val ~= nil then
            row[df.name] = Serializer.decode(val, df.type, df.name)
        end
    end
end

--- Reloads this instance's columns from the database.
---@return boolean found
function Instance:refresh()
    local q = Query.select(self._tableName, identityOf(self, "refresh"), "*")
    Logger.query(q.sql, q.params)
    local rows = self._adapter:execute(q.sql, q.params)
    local row = rows and rows[1]
    if not row then return false end

    InstanceLib.decodeRow(row, self._schema)
    assignColumns(self, row)
    return true
end

-- ─── Classes ───────────────────────────────────────────────────────

--- Method names, listed once: a row's columns are checked against them.
---@type string[]
local METHOD_NAMES = Helpers.sortedKeys(Instance)

--- Moves the columns named like a method out of a raw row.
---@param row table<string, any>
---@return table<string, any>|nil
local function takeMethodColumns(row)
    local taken
    for i = 1, #METHOD_NAMES do
        local name = METHOD_NAMES[i]
        local value = rawget(row, name)
        if value ~= nil then
            taken = taken or {}
            taken[name] = value
            rawset(row, name, nil)
        end
    end
    return taken
end

---@class OrvexInstanceContext
---@field tableName string
---@field schema OrvexSchema
---@field adapter OrvexAdapter
---@field cache OrvexCache
---@field primaryKey string
---@field relations table<string, OrvexRelationDef>
---@field hooks table<string, function[]>
---@field softDelete boolean
---@field timestamps boolean

--- Builds the metatable shared by every instance of one model.
---@param ctx OrvexInstanceContext
---@return table class
function InstanceLib.newClass(ctx)
    local context = setmetatable({
        _tableName  = ctx.tableName,
        _schema     = ctx.schema,
        _adapter    = ctx.adapter,
        _cache      = ctx.cache,
        _primaryKey = ctx.primaryKey,
        _relations  = ctx.relations,
        _hooks      = ctx.hooks,
        _softDelete = ctx.softDelete,
        _timestamps = ctx.timestamps,
    }, { __index = Instance })
    return { __index = context, __newindex = assignField }
end

--- Turns a raw row into an instance of `class`, in place: decodes its
--- json / auto columns and records the key that identifies it.
---@param row table<string, any>
---@param class table from `InstanceLib.newClass`
---@return OrvexInstance
function InstanceLib.wrap(row, class)
    local context = class.__index
    InstanceLib.decodeRow(row, context._schema)
    local primaryKey = context._primaryKey
    states[row] = {
        where         = { [primaryKey] = rawget(row, primaryKey) },
        methodColumns = takeMethodColumns(row),
    }
    return setmetatable(row, class)
end

InstanceLib.methods = Instance

OrvexModelInstance = InstanceLib
return InstanceLib
