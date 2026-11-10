-- core/transaction.lua
-- Collects multiple queries and executes them atomically via MySQL.transaction.
-- When given a cache, it records the tables its queries write and
-- invalidates them once the commit succeeds.

local Query = OrvexQuery or require("core.query")

---@class OrvexTransactionQuery
---@field query string
---@field values any[]

---@class OrvexTransaction
---@field private _adapter OrvexAdapter
---@field private _queries OrvexTransactionQuery[]
---@field private _cache? OrvexCache
---@field private _touched table<string, boolean> tables written by the queued queries
---@field private _touchesUnknown boolean a queued query writes tables that cannot be told
local Transaction = {}
Transaction.__index = Transaction

---@param adapter OrvexAdapter
---@param cache? OrvexCache invalidated after a successful commit
---@return OrvexTransaction
function Transaction.new(adapter, cache)
    local self = setmetatable({}, Transaction)
    self._adapter = adapter
    self._queries = {}
    self._cache = cache
    self._touched = {}
    self._touchesUnknown = false
    return self
end

--- Invalidates what `sql` may have written: its tables, or the whole
--- cache when they cannot be told.
---@param cache? OrvexCache
---@param sql string
function Transaction.invalidateWritten(cache, sql)
    if not cache then return end
    local tables = Query.writtenTables(sql)
    if not tables then
        cache:flush()
        return
    end
    for _, name in ipairs(tables) do
        cache:invalidateTable(name)
    end
end

---@param self OrvexTransaction
---@param sql string
local function recordWrite(self, sql)
    if not self._cache then return end
    local tables = Query.writtenTables(sql)
    if not tables then
        self._touchesUnknown = true
        return
    end
    for _, name in ipairs(tables) do
        self._touched[name] = true
    end
end

---@param self OrvexTransaction
local function invalidateTouched(self)
    if not self._cache then return end
    if self._touchesUnknown then
        self._cache:flush()
        return
    end
    for name in pairs(self._touched) do
        self._cache:invalidateTable(name)
    end
end

---@param sql string
---@param params any[]
---@return OrvexTransaction
function Transaction:addRaw(sql, params)
    self._queries[#self._queries + 1] = {
        query  = sql,
        values = params or {},
    }
    recordWrite(self, sql)
    return self
end

---@param tableName string
---@param data table<string, any>
---@return OrvexTransaction
function Transaction:insert(tableName, data)
    local q = Query.insert(tableName, data)
    return self:addRaw(q.sql, q.params)
end

---@param tableName string
---@param data table<string, any>
---@param where table<string, any>
---@return OrvexTransaction
function Transaction:update(tableName, data, where)
    local q = Query.update(tableName, data, where)
    return self:addRaw(q.sql, q.params)
end

---@param tableName string
---@param where table<string, any>
---@return OrvexTransaction
function Transaction:delete(tableName, where)
    local q = Query.delete(tableName, where)
    return self:addRaw(q.sql, q.params)
end

---@param tableName string
---@param data table<string, any>
---@return OrvexTransaction
function Transaction:upsert(tableName, data)
    local q = Query.upsert(tableName, data)
    return self:addRaw(q.sql, q.params)
end

---@return OrvexTransactionQuery[]
function Transaction:getQueries()
    return self._queries
end

--- A failed commit changed nothing, so the cache is only invalidated on success.
---@return boolean success
function Transaction:commit()
    if #self._queries == 0 then
        return true
    end
    local success = self._adapter:transaction(self._queries)
    if success then invalidateTouched(self) end
    return success
end

OrvexTransaction = Transaction
return Transaction
