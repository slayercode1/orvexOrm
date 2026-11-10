-- core/model/write.lua
-- Write helpers shared by the model class and its instances.

local Validator = OrvexValidator or require("utils.validator")
local Helpers   = OrvexHelpers or require("utils.helpers")
local Logger    = OrvexLogger or require("utils.logger")

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

OrvexModelWrite = Write
return Write
