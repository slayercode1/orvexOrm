-- utils/validator.lua
-- Validates field values against the types declared in a schema.
-- Performance-optimized: direct type() comparison, no function call overhead.

local type = type

---@class OrvexValidator
local Validator = {}

--- Maps schema type names -> Lua type() strings.
---@type table<OrvexFieldType, string>
local TYPE_MAP = {
    string    = "string",
    number    = "number",
    boolean   = "boolean",
    json      = "table",
    date      = "string",
    datetime  = "string",
    timestamp = "string",
}

--- Validate a single field value against its declared type.
---@param field string
---@param value any
---@param fieldType OrvexFieldType
---@return boolean ok
---@return string|nil error
function Validator.checkType(field, value, fieldType)
    if value == nil then return true end
    local expected = TYPE_MAP[fieldType]
    if not expected then return true end
    if type(value) ~= expected then
        return false, ("Field '%s': expected %s, got %s"):format(field, expected, type(value))
    end
    return true
end

--- Validate a full data table against a schema.
--- Only validates fields present in data (fast path).
---@param data table
---@param fields table<string, OrvexFieldType>
---@return boolean ok
---@return string|nil firstError
function Validator.validate(data, fields)
    for key, value in pairs(data) do
        local fieldType = fields[key]
        if not fieldType then
            return false, ("Unknown field '%s'"):format(key)
        end
        if value ~= nil then
            local expected = TYPE_MAP[fieldType]
            if expected and type(value) ~= expected then
                return false, ("Field '%s': expected %s, got %s"):format(key, expected, type(value))
            end
        end
    end
    return true
end

OrvexValidator = Validator
return Validator
