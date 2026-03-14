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

-- ─── Sorted keys cache ─────────────────────────────────────────────
-- Caches sorted key lists by a fingerprint of the key set.
-- Avoids re-sorting the same key sets on every query.

local _sortedKeysCache = {}
local _sortedKeysCacheSize = 0
local _SORTED_KEYS_MAX = 256

---@param t table
---@return string
local function keyFingerprint(t)
    local keys = {}
    local n = 0
    for k in pairs(t) do
        n = n + 1
        keys[n] = k
    end
    table_sort(keys)
    return table.concat(keys, "\0")
end

---@param t table
---@return string[]
function Helpers.sortedKeys(t)
    local fp = keyFingerprint(t)
    local cached = _sortedKeysCache[fp]
    if cached then return cached end

    local keys = {}
    local n = 0
    for k in pairs(t) do
        n = n + 1
        keys[n] = k
    end
    table_sort(keys)

    if _sortedKeysCacheSize >= _SORTED_KEYS_MAX then
        _sortedKeysCache = {}
        _sortedKeysCacheSize = 0
    end

    _sortedKeysCache[fp] = keys
    _sortedKeysCacheSize = _sortedKeysCacheSize + 1
    return keys
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
