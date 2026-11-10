-- utils/cache.lua
--
-- Query result cache with TTL, bounded size (LRU eviction) and a per-table
-- index so a write only purges the entries of the tables it touches.

---@class OrvexCacheEntry
---@field key string
---@field value any
---@field expires number
---@field tables string[]
---@field prev OrvexCacheEntry
---@field next OrvexCacheEntry

---@class OrvexCache
---@field private _store table<string, OrvexCacheEntry>
---@field private _byTable table<string, table<string, true>>
---@field private _lru OrvexCacheEntry sentinel of the circular recency list
---@field private _count integer
---@field private _ttl number
---@field private _maxEntries integer
---@field private _nextSweep number
---@field private _enabled boolean
local Cache = {}
Cache.__index = Cache

local DEFAULT_TTL         = 60
local DEFAULT_MAX_ENTRIES = 1000

--- Index bucket for entries whose SQL names no recognisable table:
--- any table invalidation purges them, so they can never go stale.
local ANY_TABLE = "\0*"

local TABLE_KEYWORDS = { "from", "join", "into", "update" }

local TYPE_TAGS = { string = "s", number = "n", boolean = "b" }

-- ─── Keys ──────────────────────────────────────────────────────────

---@param sql string
---@param params any[]
---@return string|nil header nil when a parameter cannot be serialised
---@return string[] values
local function describeParams(sql, params)
    local header = { tostring(#sql) }
    local values = {}
    for i = 1, #params do
        local value = params[i]
        local tag = TYPE_TAGS[type(value)]
        if not tag then return nil, values end
        local text = tostring(value)
        header[i + 1] = tag .. #text
        values[i] = text
    end
    return table.concat(header, ","), values
end

--- Builds a collision-free key: a header holding the SQL length and the
--- type and length of each parameter, then the readable `sql:p1:p2` body.
--- Returns nil when a parameter is a table, function or userdata: such
--- queries are not cacheable (their string form is an address).
---@param sql string
---@param params? any[]
---@return string|nil
function Cache.makeKey(sql, params)
    local header, values = describeParams(sql, params or {})
    if not header then return nil end
    if #values == 0 then
        return header .. "|" .. sql
    end
    return header .. "|" .. sql .. ":" .. table.concat(values, ":")
end

-- ─── Table index ───────────────────────────────────────────────────

---@param identifier string e.g. users, `users`, db.users, `db`.`users`
---@return string
local function bareTableName(identifier)
    local name = identifier:gsub("`", "")
    return name:match("([^%.]+)$") or name
end

---@param key string
---@return string[]
local function tablesReferencedBy(key)
    local lowered, found, tables = key:lower(), {}, {}
    for _, keyword in ipairs(TABLE_KEYWORDS) do
        for identifier in lowered:gmatch("%f[%w_]" .. keyword .. "%s+([%w_$`%.]+)") do
            local name = bareTableName(identifier)
            if name ~= "" and not found[name] then
                found[name] = true
                tables[#tables + 1] = name
            end
        end
    end
    if #tables == 0 then tables[1] = ANY_TABLE end
    return tables
end

---@param tables? string|string[]
---@return string[]|nil
local function normaliseTables(tables)
    if tables == nil then return nil end
    if type(tables) == "string" then tables = { tables } end
    local normalised = {}
    for i, name in ipairs(tables) do
        normalised[i] = name:lower()
    end
    return normalised
end

-- ─── Construction ──────────────────────────────────────────────────

---@param opts? { ttl?: number, enabled?: boolean, maxEntries?: integer, sweepInterval?: number }
---@return OrvexCache
function Cache.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Cache)
    self._ttl           = opts.ttl or DEFAULT_TTL
    self._maxEntries    = opts.maxEntries or DEFAULT_MAX_ENTRIES
    self._sweepInterval = opts.sweepInterval
    self._enabled       = opts.enabled ~= false
    self._hits          = 0
    self._misses        = 0
    self:_reset()
    return self
end

---@private
function Cache:_reset()
    local sentinel = {}
    sentinel.prev, sentinel.next = sentinel, sentinel
    self._store     = {}
    self._byTable   = {}
    self._lru       = sentinel
    self._count     = 0
    self._nextSweep = 0
end

---@return boolean
function Cache:isEnabled()
    return self._enabled
end

-- ─── Recency list ──────────────────────────────────────────────────

local function unlink(entry)
    entry.prev.next = entry.next
    entry.next.prev = entry.prev
end

---@private
function Cache:_pushFront(entry)
    local head = self._lru
    entry.prev, entry.next = head, head.next
    head.next.prev = entry
    head.next = entry
end

---@private
---@return OrvexCacheEntry|nil
function Cache:_leastRecent()
    local tail = self._lru.prev
    if tail == self._lru then return nil end
    return tail
end

-- ─── Entry bookkeeping ─────────────────────────────────────────────

---@private
function Cache:_index(entry)
    for _, name in ipairs(entry.tables) do
        local bucket = self._byTable[name]
        if not bucket then
            bucket = {}
            self._byTable[name] = bucket
        end
        bucket[entry.key] = true
    end
end

---@private
function Cache:_unindex(entry)
    for _, name in ipairs(entry.tables) do
        local bucket = self._byTable[name]
        if bucket then
            bucket[entry.key] = nil
            if next(bucket) == nil then self._byTable[name] = nil end
        end
    end
end

---@private
---@param key string
function Cache:_remove(key)
    local entry = self._store[key]
    if not entry then return end
    self._store[key] = nil
    unlink(entry)
    self:_unindex(entry)
    self._count = self._count - 1
end

---@private
---@param keys table<string, true>|nil
function Cache:_removeAll(keys)
    if not keys then return end
    local toRemove = {}
    for key in pairs(keys) do
        toRemove[#toRemove + 1] = key
    end
    for _, key in ipairs(toRemove) do
        self:_remove(key)
    end
end

---@private
function Cache:_evictOverflow()
    while self._count > self._maxEntries do
        self:_remove(self:_leastRecent().key)
    end
end

---@private
---@param now number
function Cache:_sweepIfDue(now)
    if now < self._nextSweep then return end
    self:purgeExpired()
    self._nextSweep = now + math.max(1, self._sweepInterval or self._ttl)
end

-- ─── Public API ────────────────────────────────────────────────────

---@param key string|nil nil (uncacheable query) always misses silently
---@return any|nil value
---@return boolean hit
function Cache:get(key)
    if not self._enabled or key == nil then
        return nil, false
    end

    local entry = self._store[key]
    if not entry then
        self._misses = self._misses + 1
        return nil, false
    end

    if os.time() >= entry.expires then
        self:_remove(key)
        self._misses = self._misses + 1
        return nil, false
    end

    unlink(entry)
    self:_pushFront(entry)
    self._hits = self._hits + 1
    return entry.value, true
end

--- Tables are detected from the FROM/JOIN/INTO/UPDATE clauses of the key
--- when `tables` is omitted.
---@param key string|nil nil (uncacheable query) is ignored
---@param value any
---@param ttl? number
---@param tables? string|string[] tables the cached result depends on
function Cache:set(key, value, ttl, tables)
    if not self._enabled or key == nil then return end

    local now = os.time()
    self:_sweepIfDue(now)
    self:_remove(key)

    local entry = {
        key     = key,
        value   = value,
        expires = now + (ttl or self._ttl),
        tables  = normaliseTables(tables) or tablesReferencedBy(key),
    }
    self._store[key] = entry
    self:_pushFront(entry)
    self:_index(entry)
    self._count = self._count + 1
    self:_evictOverflow()
end

---@param key string
function Cache:invalidate(key)
    self:_remove(key)
end

---@param prefix string
function Cache:invalidatePrefix(prefix)
    local matching = {}
    for key in pairs(self._store) do
        if key:sub(1, #prefix) == prefix then
            matching[key] = true
        end
    end
    self:_removeAll(matching)
end

--- Purges entries reading `tableName` (exact name, JOINs and subqueries
--- included) and entries whose tables are unknown.
---@param tableName string
function Cache:invalidateTable(tableName)
    self:_removeAll(self._byTable[tableName:lower()])
    self:_removeAll(self._byTable[ANY_TABLE])
end

--- Removes every expired entry.
---@return integer removed
function Cache:purgeExpired()
    local now, expired, removed = os.time(), {}, 0
    for key, entry in pairs(self._store) do
        if now >= entry.expires then
            expired[key] = true
            removed = removed + 1
        end
    end
    self:_removeAll(expired)
    return removed
end

function Cache:flush()
    self:_reset()
end

---@param enabled boolean
function Cache:setEnabled(enabled)
    self._enabled = enabled
    if not enabled then
        self:flush()
    end
end

---@return { hits: integer, misses: integer, hitRate: number, entries: integer, maxEntries: integer }
function Cache:stats()
    local total = self._hits + self._misses
    return {
        hits       = self._hits,
        misses     = self._misses,
        hitRate    = total > 0 and (self._hits / total) or 0,
        entries    = self:size(),
        maxEntries = self._maxEntries,
    }
end

---@return integer
function Cache:size()
    return self._count
end

OrvexCache = Cache
return Cache
