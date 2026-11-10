-- utils/validator.lua

local type = type

---@class OrvexValidator
local Validator = {}

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

--- Every supported field type, in documentation order: the types of
--- TYPE_MAP plus 'auto', the explicit "any value" type.
---@type OrvexFieldType[]
Validator.SUPPORTED_TYPES = { "string", "number", "boolean", "json", "auto", "date", "datetime", "timestamp" }

---@type table<string, true>
local KNOWN_TYPES = {}
for _, fieldType in ipairs(Validator.SUPPORTED_TYPES) do
    KNOWN_TYPES[fieldType] = true
end

---@param fieldType any
---@return boolean
function Validator.isKnownType(fieldType)
    return KNOWN_TYPES[fieldType] == true
end

--- Fails closed: an unknown type (a typo such as 'int') is an error, not a
--- disabled check. Schema.new refuses such types up front.
---@param field string
---@param value any
---@param fieldType OrvexFieldType
---@return boolean ok
---@return string|nil error
function Validator.checkType(field, value, fieldType)
    if fieldType == "auto" then return true end
    local expected = TYPE_MAP[fieldType]
    if not expected then
        return false, ("Field '%s': unknown type '%s'"):format(field, tostring(fieldType))
    end
    if value == nil then return true end
    if type(value) ~= expected then
        return false, ("Field '%s': expected %s, got %s"):format(field, expected, type(value))
    end
    return true
end

---@param field string
---@param value any
---@param fields table<string, OrvexFieldType>
---@return boolean ok
---@return string|nil error
local function checkField(field, value, fields)
    local fieldType = fields[field]
    if not fieldType then
        return false, ("Unknown field '%s'"):format(tostring(field))
    end
    return Validator.checkType(field, value, fieldType)
end

--- Only validates fields present in data (fast path). When several fields
--- are invalid, the one reported is the first in sorted order, so the
--- message does not depend on the table's hash order.
---@param data table
---@param fields table<string, OrvexFieldType>
---@return boolean ok
---@return string|nil firstError
function Validator.validate(data, fields)
    local firstField, firstError
    for field, value in pairs(data) do
        local ok, err = checkField(field, value, fields)
        if not ok and (firstField == nil or tostring(field) < tostring(firstField)) then
            firstField, firstError = field, err
        end
    end
    if firstError then return false, firstError end
    return true
end

OrvexValidator = Validator
return Validator
