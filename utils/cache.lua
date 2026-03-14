-- utils/cache.lua
-- In-memory TTL cache for query results.
-- Reduces database hits for frequently accessed data.

---@class OrvexCacheEntry
---@field value any
---@field expires number  os.time() when this entry expires

---@class OrvexCache
---@field private _store table<string, OrvexCacheEntry>
---@field private _ttl number  Default TTL in seconds
---@field private _enabled boolean
local Cache = {}
Cache.__index = Cache

--- Create a new cache instance.
---@param opts? { ttl?: number, enabled?: boolean }
---@return OrvexCache
function Cache.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Cache)
    self._store   = {}
    self._ttl     = opts.ttl or 60       -- default 60 seconds
    self._enabled = opts.enabled ~= false -- enabled by default
    return self
end

--- Generate a cache key from a SQL query and its params.
--- Optimized: builds string directly for common cases.
---@param sql string
---@param params any[]
---@return string
function Cache.makeKey(sql, params)
    if not params or #params == 0 then
        return sql
    end
    -- Fast path for 1-3 params (most common)
    local n = #params
    if n == 1 then
        return sql .. ":" .. tostring(params[1])
    elseif n == 2 then
        return sql .. ":" .. tostring(params[1]) .. ":" .. tostring(params[2])
    elseif n == 3 then
        return sql .. ":" .. tostring(params[1]) .. ":" .. tostring(params[2]) .. ":" .. tostring(params[3])
    end
    -- General case
    local parts = { sql }
    for i = 1, n do
        parts[i + 1] = tostring(params[i])
    end
    return table.concat(parts, ":")
end

--- Get a value from the cache. Returns nil if not found or expired.
---@param key string
---@return any|nil value
---@return boolean hit
function Cache:get(key)
    if not self._enabled then
        return nil, false
    end

    local entry = self._store[key]
    if not entry then
        return nil, false
    end

    if os.time() >= entry.expires then
        self._store[key] = nil
        return nil, false
    end

    return entry.value, true
end

--- Store a value in the cache.
---@param key string
---@param value any
---@param ttl? number  Override the default TTL for this entry
function Cache:set(key, value, ttl)
    if not self._enabled then return end

    self._store[key] = {
        value   = value,
        expires = os.time() + (ttl or self._ttl),
    }
end

--- Remove a specific key from the cache.
---@param key string
function Cache:invalidate(key)
    self._store[key] = nil
end

--- Remove all entries matching a pattern (table name prefix).
--- Used to invalidate all cached queries for a table after a write.
---@param prefix string  e.g. "SELECT * FROM users"
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

--- Remove all entries that mention a table name anywhere in the key.
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

--- Clear the entire cache.
function Cache:flush()
    self._store = {}
end

--- Enable or disable the cache.
---@param enabled boolean
function Cache:setEnabled(enabled)
    self._enabled = enabled
    if not enabled then
        self:flush()
    end
end

--- Get the number of entries currently in the cache.
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
