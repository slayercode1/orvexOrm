-- utils/serializer.lua
-- Converts Lua tables <-> JSON strings for columns stored as JSON in MySQL.
-- Performance-optimized: uses byte checks instead of pattern matching.

local type = type
local string_byte = string.byte

-- Byte values for fast JSON detection
local BYTE_LBRACE  = string_byte("{")
local BYTE_LBRACKET = string_byte("[")

---@class OrvexSerializer
local Serializer = {}

--- Check if a string looks like JSON (starts with { or [).
---@param s string
---@return boolean
local function looksLikeJSON(s)
    if type(s) ~= "string" then return false end
    local b = string_byte(s)
    return b == BYTE_LBRACE or b == BYTE_LBRACKET
end

--- Encode a Lua value for database storage.
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

--- Decode a database value back into a Lua type.
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

    return value
end

OrvexSerializer = Serializer
return Serializer
