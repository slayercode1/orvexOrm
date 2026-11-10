-- core/model/write.lua
-- Write helpers shared by the model class and its instances.

local Validator = OrvexValidator or require("utils.validator")
local Helpers   = OrvexHelpers or require("utils.helpers")
local Logger    = OrvexLogger or require("utils.logger")
local Query     = OrvexQuery or require("core.query")

---@class OrvexModelWrite
local Write = {}

--- Drivers report UPDATE / DELETE results as a number (oxmysql update,
--- mysql-async execute) or as a result table (raw oxmysql query).
---@param result any
---@return integer
function Write.affectedRows(result)
    if type(result) == "number" then return result end
    if type(result) == "table" and type(result.affectedRows) == "number" then
        return result.affectedRows
    end
    return 0
end

--- Runs a write, invalidates the table's cache and returns the affected rows.
---@param adapter OrvexAdapter
---@param cache OrvexCache
---@param tableName string
---@param q OrvexQueryResult
---@return integer affected
function Write.run(adapter, cache, tableName, q)
    Logger.query(q.sql, q.params)
    local result = adapter:scalar(q.sql, q.params)
    cache:invalidateTable(tableName)
    return Write.affectedRows(result)
end

--- Raises the first validation error, located at the caller's line.
---@param data table<string, any>
---@param fields table<string, OrvexFieldType>
function Write.validate(data, fields)
    local ok, err = Validator.validate(data, fields)
    if not ok then Helpers.raise(err) end
end

--- Refuses caller data that sets a column the ORM manages: deleted_at
--- always (it is what delete() / restore() write), created_at / updated_at
--- unless the model sets `allowManagedColumns = true`. Hooks run after this
--- check and may still set them.
---@param data any the caller's row; anything but a table is left to the write
---@param schema OrvexSchema
---@param method string
function Write.refuseManagedColumns(data, schema, method)
    if type(data) ~= "table" then return end
    for _, column in ipairs(Helpers.sortedKeys(schema.managedColumns)) do
        if data[column] ~= nil then
            if schema.managedColumns[column] == "softDelete" then
                Helpers.raise(("%s(): '%s' is managed by soft delete, use delete() / restore() instead")
                    :format(method, column))
            elseif not schema.allowManagedColumns then
                Helpers.raise(("%s(): '%s' is stamped by the ORM (timestamps = true); "
                    .. "set allowManagedColumns = true on the model to write it yourself"):format(method, column))
            end
        end
    end
end

--- Queues one multi-row INSERT per group (insertMany needs rows that
--- share their columns, see `Query.groupByKeySet`).
---@param tx OrvexTransaction
---@param tableName string
---@param groups table[][] encoded rows grouped by key set
function Write.queueInsertGroups(tx, tableName, groups)
    for _, group in ipairs(groups) do
        local q = Query.insertMany(tableName, group)
        Logger.query(q.sql, q.params)
        tx:addRaw(q.sql, q.params)
    end
end

OrvexModelWrite = Write
return Write
