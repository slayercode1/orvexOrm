-- utils/serializer.lua

local type = type
local string_byte = string.byte

local BYTE_LBRACE  = string_byte("{")
local BYTE_LBRACKET = string_byte("[")

---@class OrvexSerializer
local Serializer = {}

---@param s string
---@return boolean
local function looksLikeJSON(s)
    if type(s) ~= "string" then return false end
    local b = string_byte(s)
    return b == BYTE_LBRACE or b == BYTE_LBRACKET
end

---@param value any
---@param fieldType? OrvexFieldType
---@return any
function Serializer.encode(value, fieldType)
    if value == nil then return value end
    if type(value) == "table" and (fieldType == "json" or fieldType == "auto") then
        return json.encode(value)
    end
    return value
end

--- Note: oxmysql may return DATE/DATETIME/TIMESTAMP columns as Unix timestamp
--- numbers instead of formatted strings.
---@param value any
---@param fieldType? OrvexFieldType
---@return any
function Serializer.decode(value, fieldType)
    if fieldType == "json" and type(value) == "string" then
        return json.decode(value)
    end

    if fieldType == "auto" and looksLikeJSON(value) then
        local ok, decoded = pcall(json.decode, value)
        if ok then return decoded end
    end

    if fieldType == "date" and type(value) == "number" then
        return os.date("!%Y-%m-%d", value)
    end

    if (fieldType == "datetime" or fieldType == "timestamp") and type(value) == "number" then
        return os.date("!%Y-%m-%d %H:%M:%S", value)
    end

    return value
end

OrvexSerializer = Serializer
return Serializer
