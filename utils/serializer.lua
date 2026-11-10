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

--- Encodes json/auto table values of a row. Copies the row only when at
--- least one field actually needs encoding, otherwise returns it as-is.
---@param data table<string, any>
---@param encodeSet table<string, boolean>
---@return table<string, any>
function Serializer.encodeRow(data, encodeSet)
    if next(encodeSet) == nil then return data end

    local needsCopy = false
    for name in pairs(encodeSet) do
        if type(data[name]) == "table" then
            needsCopy = true
            break
        end
    end
    if not needsCopy then return data end

    local encoded = {}
    for k, v in pairs(data) do
        if encodeSet[k] and type(v) == "table" then
            encoded[k] = json.encode(v)
        else
            encoded[k] = v
        end
    end
    return encoded
end

--- utils/logger.lua loads after this file: resolve it on use.
---@return OrvexLogger|nil
local function logger()
    return OrvexLogger or (type(require) == "function" and require("utils.logger")) or nil
end

--- A malformed json column (written by raw SQL or an external tool) must
--- not make every read of its row raise: the raw string is kept, as for
--- 'auto', and a warning names the field (never its content).
---@param value string
---@param fieldName? string
---@return any
local function decodeJsonColumn(value, fieldName)
    local ok, decoded = pcall(json.decode, value)
    if ok then return decoded end
    local log = logger()
    if log then
        log.warn("Malformed JSON in a json column, the raw string is returned", { field = fieldName })
    end
    return value
end

--- Note: oxmysql may return DATE/DATETIME/TIMESTAMP columns as Unix timestamp
--- numbers instead of formatted strings.
---@param value any
---@param fieldType? OrvexFieldType
---@param fieldName? string named in the warning of a malformed json value
---@return any
function Serializer.decode(value, fieldType, fieldName)
    if fieldType == "json" and type(value) == "string" then
        return decodeJsonColumn(value, fieldName)
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
