-- tests/support/json.lua
-- Spec-compliant JSON codec standing in for FiveM's `json` global in tests.
-- Encoding follows FiveM's behaviour where tests depend on it: an empty
-- table encodes as "[]", and object keys are sorted so the output is
-- deterministic. Decoding maps JSON null to nil, like FiveM.
--
-- Usage: json = require("tests.support.json")

local JSON = {}

-- ─── Encoder ───────────────────────────────────────────────────────

local SHORT_ESCAPES = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escapeChar(char)
    return SHORT_ESCAPES[char] or ("\\u%04x"):format(char:byte())
end

local function encodeString(value)
    return '"' .. value:gsub('[%c"\\]', escapeChar) .. '"'
end

local function encodeNumber(value)
    if value ~= value or value == math.huge or value == -math.huge then
        error("JSON cannot encode NaN or infinity")
    end
    if math.type(value) == "integer" then return tostring(value) end
    return ("%.17g"):format(value)
end

local function isArray(value)
    local count = 0
    for key in pairs(value) do
        if math.type(key) ~= "integer" or key < 1 then return false end
        count = count + 1
    end
    return count == #value
end

local encodeValue

local function encodeArray(value)
    local parts = {}
    for index = 1, #value do parts[index] = encodeValue(value[index]) end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encodeObject(value)
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then
            error("JSON object keys must be strings or numbers, got " .. type(key))
        end
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    local parts = {}
    for index, key in ipairs(keys) do
        local item = value[key]
        if item == nil then item = value[tonumber(key)] end
        parts[index] = encodeString(key) .. ":" .. encodeValue(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function encodeValue(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then return encodeNumber(value) end
    if kind == "string" then return encodeString(value) end
    if kind == "table" then
        if isArray(value) then return encodeArray(value) end
        return encodeObject(value)
    end
    error("JSON cannot encode a " .. kind)
end

---@param value any
---@return string
function JSON.encode(value)
    return encodeValue(value)
end

-- ─── Decoder ───────────────────────────────────────────────────────

local LITERAL_WORDS = { "true", "false", "null" }
local LITERAL_VALUES = { ["true"] = true, ["false"] = false } -- null decodes to nil

local UNESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
    f = "\f", n = "\n", r = "\r", t = "\t",
}

local function decodeError(text, position, message)
    error(("JSON decode error at %d: %s near '%s'"):format(position, message, text:sub(position, position + 10)), 0)
end

local function skipWhitespace(text, position)
    return text:find("[^ \t\r\n]", position) or #text + 1
end

local decodeAt

local function decodeUnicodeEscape(text, position)
    local hex = text:match("^%x%x%x%x", position)
    if not hex then decodeError(text, position, "invalid \\u escape") end
    local codepoint = tonumber(hex, 16)
    local nextPosition = position + 4
    local isHighSurrogate = codepoint >= 0xD800 and codepoint <= 0xDBFF
    local low = isHighSurrogate and text:match("^\\u(%x%x%x%x)", nextPosition)
    if low then
        codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (tonumber(low, 16) - 0xDC00)
        nextPosition = nextPosition + 6
    end
    return utf8.char(codepoint), nextPosition
end

local function decodeString(text, position)
    local parts = {}
    local cursor = position + 1
    while true do
        local char = text:sub(cursor, cursor)
        if char == "" then decodeError(text, position, "unterminated string") end
        if char == '"' then return table.concat(parts), cursor + 1 end
        if char:byte() < 0x20 then decodeError(text, cursor, "raw control character in string") end
        if char == "\\" then
            local escape = text:sub(cursor + 1, cursor + 1)
            if escape == "u" then
                parts[#parts + 1], cursor = decodeUnicodeEscape(text, cursor + 2)
            elseif UNESCAPES[escape] then
                parts[#parts + 1], cursor = UNESCAPES[escape], cursor + 2
            else
                decodeError(text, cursor, "invalid escape")
            end
        else
            parts[#parts + 1], cursor = char, cursor + 1
        end
    end
end

local function decodeNumber(text, position)
    local literal = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
    local value = literal and math.tointeger(tonumber(literal)) or tonumber(literal or "")
    if value == nil then decodeError(text, position, "invalid number") end
    return value, position + #literal
end

local function decodeLiteral(text, position)
    for _, word in ipairs(LITERAL_WORDS) do
        if text:sub(position, position + #word - 1) == word then
            return LITERAL_VALUES[word], position + #word
        end
    end
    decodeError(text, position, "unexpected token")
end

local function decodeSequence(text, position, closer, readItem)
    local cursor = skipWhitespace(text, position + 1)
    if text:sub(cursor, cursor) == closer then return cursor + 1 end
    while true do
        cursor = readItem(cursor)
        cursor = skipWhitespace(text, cursor)
        local separator = text:sub(cursor, cursor)
        if separator == closer then return cursor + 1 end
        if separator ~= "," then decodeError(text, cursor, "expected ',' or '" .. closer .. "'") end
        cursor = skipWhitespace(text, cursor + 1)
    end
end

local function decodeArray(text, position)
    local result, count = {}, 0
    local nextPosition = decodeSequence(text, position, "]", function(cursor)
        local value
        value, cursor = decodeAt(text, cursor)
        count = count + 1
        result[count] = value
        return cursor
    end)
    return result, nextPosition
end

local function decodeObject(text, position)
    local result = {}
    local nextPosition = decodeSequence(text, position, "}", function(cursor)
        if text:sub(cursor, cursor) ~= '"' then decodeError(text, cursor, "expected a string key") end
        local key, value
        key, cursor = decodeString(text, cursor)
        cursor = skipWhitespace(text, cursor)
        if text:sub(cursor, cursor) ~= ":" then decodeError(text, cursor, "expected ':'") end
        value, cursor = decodeAt(text, skipWhitespace(text, cursor + 1))
        result[key] = value
        return cursor
    end)
    return result, nextPosition
end

local DECODERS = { ['"'] = decodeString, ["["] = decodeArray, ["{"] = decodeObject }

function decodeAt(text, position)
    position = skipWhitespace(text, position)
    local char = text:sub(position, position)
    local decoder = DECODERS[char]
    if decoder then return decoder(text, position) end
    if char:match("[-%d]") then return decodeNumber(text, position) end
    return decodeLiteral(text, position)
end

---@param text string
---@return any
function JSON.decode(text)
    if type(text) ~= "string" then error("JSON.decode expects a string, got " .. type(text)) end
    local value, position = decodeAt(text, 1)
    position = skipWhitespace(text, position)
    if position <= #text then decodeError(text, position, "trailing characters") end
    return value
end

return JSON
