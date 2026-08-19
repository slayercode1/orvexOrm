-- utils/logger.lua

---@class OrvexLogger
local Logger = { _enabled = false, _sink = nil }

local sensitiveKeys = {
    authorization = true, cookie = true, password = true, passwd = true,
    secret = true, token = true, accesstoken = true, refreshtoken = true,
    apikey = true, cardnumber = true, cvv = true, connectionstring = true,
}

local function sanitize(value, key, seen)
    local normalized = key and tostring(key):lower():gsub("[^%w]", "")
    if normalized and sensitiveKeys[normalized] then return "[REDACTED]" end
    if type(value) == "string" then
        local clean = value:gsub("([?&][Tt][Oo][Kk][Ee][Nn]=)[^&%s]+", "%1[REDACTED]")
        clean = clean:gsub("([Bb]earer%s+)[%w%._%-]+", "%1[REDACTED]")
        clean = clean:gsub("(mysql://[^:%s/]+:)[^@%s]+(@)", "%1[REDACTED]%2")
        clean = clean:gsub("([Pp]assword%s*[=:]%s*)[^,%s;]+", "%1[REDACTED]")
        return clean
    end
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return "[CIRCULAR]" end
    seen[value] = true
    local clean = {}
    for childKey, childValue in pairs(value) do clean[childKey] = sanitize(childValue, childKey, seen) end
    seen[value] = nil
    return clean
end

local function encode(value)
    if value == nil then return "null" end
    if type(value) == "boolean" or type(value) == "number" then return tostring(value) end
    if type(value) == "string" then
        local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    end
    if type(value) ~= "table" then return encode(tostring(value)) end
    local parts = {}
    for key, child in pairs(value) do parts[#parts + 1] = encode(tostring(key)) .. ":" .. encode(child) end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

local function emit(level, message, context)
    local event = sanitize(context or {})
    event.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    event.level = level
    event.message = sanitize(tostring(message))
    event.service = event.service or "orvexorm"
    local line = encode(event)
    local delivered = Logger._sink and pcall(Logger._sink, line, event)
    if not delivered then print(line) end
end

function Logger.setEnabled(enabled) Logger._enabled = enabled end
function Logger.setSink(sink) Logger._sink = sink end
function Logger.sanitize(value) return sanitize(value) end

function Logger.query(sql, params)
    if Logger._enabled then emit("debug", "Database query", { sql = sql, parameterCount = params and #params or 0 }) end
end

function Logger.info(message, context)
    if Logger._enabled then emit("info", message, context) end
end

function Logger.warn(message, context) emit("warn", message, context) end
function Logger.error(message, context) emit("error", message, context) end

OrvexLogger = Logger
return Logger
