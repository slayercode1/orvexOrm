-- utils/helpers.lua

local table_sort = table.sort
local type = type
local tostring = tostring
local string_match = string.match
local string_upper = string.upper
local string_rep = string.rep

---@class OrvexHelpers
local Helpers = {}

---@param t table
---@return table
function Helpers.shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

-- ─── Time ──────────────────────────────────────────────────────────

--- Current UTC time in MySQL DATETIME format, as written to the
--- created_at / updated_at / deleted_at columns.
---@return string
function Helpers.nowUtc()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

-- ─── Sorted keys ───────────────────────────────────────────────────
-- Sorting is what keeps the generated SQL (and so the cache keys) stable.
-- A fresh array is returned on every call: callers may modify it.

---@param t table
---@return string[]
function Helpers.sortedKeys(t)
    local keys = {}
    local n = 0
    for k in pairs(t) do
        n = n + 1
        keys[n] = k
    end
    if n > 1 then table_sort(keys) end
    return keys
end

-- ─── Caller-facing errors ──────────────────────────────────────────
-- Misuse errors are raised at the first stack frame outside OrvexORM, so
-- the message points at the caller's line instead of into the library.

local getinfo = type(debug) == "table" and debug.getinfo or nil
local LIBRARY_ROOT = getinfo and getinfo(1, "S").source:match("^(.*)utils/helpers%.lua$")
local LIBRARY_DIRS = { "core/", "utils/", "database/", "lib/" }

---@param source string
---@return boolean
local function isLibrarySource(source)
    for _, dir in ipairs(LIBRARY_DIRS) do
        local prefix = LIBRARY_ROOT .. dir
        if source:sub(1, #prefix) == prefix then return true end
    end
    return false
end

--- Stack level (as seen from `Helpers.raise`) of the first caller frame
--- outside the library; 2 (the direct caller) when it cannot be told.
---@return integer
local function callerLevel()
    if not LIBRARY_ROOT then return 3 end
    -- Level 1 is callerLevel, 2 is Helpers.raise, 3 its caller.
    local level = 3
    while true do
        local info = getinfo(level, "S")
        if not info then return 3 end
        if not isLibrarySource(info.source) then return level end
        level = level + 1
    end
end

--- Raises `message` at the caller's position (see above).
---@param message string
function Helpers.raise(message)
    error(message, callerLevel() - 1)
end

--- `assert` counterpart of `Helpers.raise`.
---@param condition any
---@param message string
function Helpers.ensure(condition, message)
    if not condition then Helpers.raise(message) end
end

-- ─── Safe identifier cache ─────────────────────────────────────────

local _safeIdentifiers = {}

---@param name string
function Helpers.assertSafeIdentifier(name)
    if _safeIdentifiers[name] then return end
    assert(type(name) == "string" and string_match(name, "^[%w_.]+$"),
        ("Invalid SQL identifier: '%s'"):format(tostring(name)))
    _safeIdentifiers[name] = true
end

---@type table<string, boolean>
Helpers.VALID_OPERATORS = {
    ["="] = true, ["!="] = true, ["<>"] = true,
    [">"] = true, ["<"] = true, [">="] = true, ["<="] = true,
    ["LIKE"] = true, ["NOT LIKE"] = true,
    ["IN"] = true, ["NOT IN"] = true,
    ["BETWEEN"] = true, ["IS"] = true, ["IS NOT"] = true,
}

---@param op string
function Helpers.assertValidOperator(op)
    assert(Helpers.VALID_OPERATORS[string_upper(op)],
        ("Invalid SQL operator: '%s'"):format(tostring(op)))
end

-- ─── Identifier quoting ────────────────────────────────────────────

local _quotedIdentifiers = {}

---@param part string
---@return string
local function quotePart(part)
    if part == "*" then return part end
    return "`" .. part:gsub("`", "``") .. "`"
end

--- Backtick-quotes an identifier so reserved words (group, key, order...)
--- are valid column or table names. Each dot-separated part is quoted on
--- its own (`a.b` -> `a`.`b`) and `*` is left untouched (`t.*` -> `t`.*).
---@param name string
---@return string
function Helpers.quoteId(name)
    local cached = _quotedIdentifiers[name]
    if cached then return cached end
    assert(type(name) == "string" and name ~= "",
        ("Invalid SQL identifier: '%s'"):format(tostring(name)))

    local parts = {}
    for part in (name .. "."):gmatch("(.-)%.") do
        parts[#parts + 1] = quotePart(part)
    end
    local quoted = table.concat(parts, ".")
    _quotedIdentifiers[name] = quoted
    return quoted
end

---@param s string
---@return string `s` without leading and trailing whitespace
function Helpers.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local trim = Helpers.trim

--- Splits on commas that are outside parentheses and quotes.
---@param list string
---@return string[]
local function splitTopLevel(list)
    local entries, depth, quote, start = {}, 0, nil, 1
    for i = 1, #list do
        local c = list:sub(i, i)
        if quote then
            if c == quote then quote = nil end
        elseif c == "'" or c == '"' or c == "`" then
            quote = c
        elseif c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
        elseif c == "," and depth == 0 then
            entries[#entries + 1] = list:sub(start, i - 1)
            start = i + 1
        end
    end
    entries[#entries + 1] = list:sub(start)
    return entries
end

--- Bare words that are SQL literals or niladic functions, not columns.
local SQL_BARE_KEYWORDS = {
    NULL = true, TRUE = true, FALSE = true, DEFAULT = true,
    CURRENT_DATE = true, CURRENT_TIME = true, CURRENT_TIMESTAMP = true,
    CURRENT_USER = true, LOCALTIME = true, LOCALTIMESTAMP = true,
}

---@param column string
---@return boolean
local function isPlainColumn(column)
    if column == "*" then return true end
    if SQL_BARE_KEYWORDS[column:upper()] then return false end
    local name = string_match(column, "^[%a_][%w_]*$")
        or string_match(column, "^[%a_][%w_]*%.[%a_][%w_]*$")
        or string_match(column, "^[%a_][%w_]*%.%*$")
    return name ~= nil
end

--- Quotes every plain identifier of a comma-separated column list and keeps
--- any other entry (expressions, aliases, functions, literals) verbatim.
---@param columns string
---@return string
function Helpers.quoteColumnList(columns)
    local out = {}
    for i, entry in ipairs(splitTopLevel(columns)) do
        local column = trim(entry)
        out[i] = isPlainColumn(column) and Helpers.quoteId(column) or column
    end
    return table.concat(out, ", ")
end

-- ─── SQL string literals ───────────────────────────────────────────

--- Quotes `value` as a MySQL string literal for statements that cannot
--- take placeholders (DDL defaults, ENUM values). Backslashes are escaped
--- first: in the default sql_mode a backslash escapes the next quote.
---@param value any
---@return string
function Helpers.quoteLiteral(value)
    local escaped = tostring(value):gsub("\\", "\\\\"):gsub("'", "''")
    return "'" .. escaped .. "'"
end

-- ─── Placeholder cache ─────────────────────────────────────────────

local _placeholderCache = {}

---@param n integer
---@return string
function Helpers.placeholders(n)
    local cached = _placeholderCache[n]
    if cached then return cached end
    local s = string_rep("?, ", n):sub(1, -3)
    _placeholderCache[n] = s
    return s
end

OrvexHelpers = Helpers
return Helpers
