-- utils/cache.lua

---@class OrvexCacheEntry
---@field value any
---@field expires number

---@class OrvexCache
---@field private _store table<string, OrvexCacheEntry>
---@field private _ttl number
---@field private _enabled boolean
local Cache = {}
Cache.__index = Cache

---@param opts? { ttl?: number, enabled?: boolean }
---@return OrvexCache
function Cache.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Cache)
    self._store   = {}
    self._ttl     = opts.ttl or 60
    self._enabled = opts.enabled ~= false
    self._hits    = 0
    self._misses  = 0
    return self
end

---@return boolean
function Cache:isEnabled()
    return self._enabled
end

--- Optimized: builds string directly for common cases.
---@param sql string
---@param params any[]
---@return string
function Cache.makeKey(sql, params)
    if not params or #params == 0 then
        return sql
    end
    local n = #params
    if n == 1 then
        return sql .. ":" .. tostring(params[1])
    elseif n == 2 then
        return sql .. ":" .. tostring(params[1]) .. ":" .. tostring(params[2])
    elseif n == 3 then
        return sql .. ":" .. tostring(params[1]) .. ":" .. tostring(params[2]) .. ":" .. tostring(params[3])
    end
    local parts = { sql }
    for i = 1, n do
        parts[i + 1] = tostring(params[i])
    end
    return table.concat(parts, ":")
end

---@param key string
---@return any|nil value
---@return boolean hit
function Cache:get(key)
    if not self._enabled then
        return nil, false
    end

    local entry = self._store[key]
    if not entry then
        self._misses = self._misses + 1
        return nil, false
    end

    if os.time() >= entry.expires then
        self._store[key] = nil
        self._misses = self._misses + 1
        return nil, false
    end

    self._hits = self._hits + 1
    return entry.value, true
end

---@param key string
---@param value any
---@param ttl? number
function Cache:set(key, value, ttl)
    if not self._enabled then return end

    self._store[key] = {
        value   = value,
        expires = os.time() + (ttl or self._ttl),
    }
end

---@param key string
function Cache:invalidate(key)
    self._store[key] = nil
end

---@param prefix string
function Cache:invalidatePrefix(prefix)
    local toRemove = {}
    for k in pairs(self._store) do
        if k:sub(1, #prefix) == prefix then
            toRemove[#toRemove + 1] = k
        end
    end
    for _, k in ipairs(toRemove) do
        self._store[k] = nil
    end
end

--- Catches JOINs and subqueries that reference the table.
---@param tableName string
function Cache:invalidateTable(tableName)
    local toRemove = {}
    for k in pairs(self._store) do
        if k:find(tableName, 1, true) then
            toRemove[#toRemove + 1] = k
        end
    end
    for _, k in ipairs(toRemove) do
        self._store[k] = nil
    end
end

function Cache:flush()
    self._store = {}
end

---@param enabled boolean
function Cache:setEnabled(enabled)
    self._enabled = enabled
    if not enabled then
        self:flush()
    end
end

---@return { hits: integer, misses: integer, hitRate: number, entries: integer }
function Cache:stats()
    local total = self._hits + self._misses
    return {
        hits    = self._hits,
        misses  = self._misses,
        hitRate = total > 0 and (self._hits / total) or 0,
        entries = self:size(),
    }
end

---@return integer
function Cache:size()
    local count = 0
    for _ in pairs(self._store) do
        count = count + 1
    end
    return count
end

OrvexCache = Cache
return Cache
