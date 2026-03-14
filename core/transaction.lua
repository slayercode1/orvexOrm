-- core/transaction.lua
-- Collects multiple queries and executes them atomically via MySQL.transaction.
-- If any query fails, all are rolled back.
--
-- Usage:
--   local tx = Transaction.new(adapter)
--   tx:insert("users", { identifier = "license:abc", money = 500 })
--   tx:update("users", { money = 1000 }, { identifier = "license:abc" })
--   tx:delete("vehicles", { owner = "license:abc" })
--   local success = tx:commit()

local Query   = OrvexQuery or require("core.query")
local Helpers = OrvexHelpers or require("utils.helpers")

---@class OrvexTransactionQuery
---@field query string
---@field values any[]

---@class OrvexTransaction
---@field private _adapter OrvexAdapter
---@field private _queries OrvexTransactionQuery[]
local Transaction = {}
Transaction.__index = Transaction

--- Create a new transaction builder.
---@param adapter OrvexAdapter
---@return OrvexTransaction
function Transaction.new(adapter)
    local self = setmetatable({}, Transaction)
    self._adapter = adapter
    self._queries = {}
    return self
end

--- Add a raw query to the transaction.
---@param sql string
---@param params any[]
---@return OrvexTransaction
function Transaction:addRaw(sql, params)
    self._queries[#self._queries + 1] = {
        query  = sql,
        values = params or {},
    }
    return self
end

--- Add an INSERT to the transaction.
---@param tableName string
---@param data table<string, any>
---@return OrvexTransaction
function Transaction:insert(tableName, data)
    local q = Query.insert(tableName, data)
    return self:addRaw(q.sql, q.params)
end

--- Add an UPDATE to the transaction.
---@param tableName string
---@param data table<string, any>
---@param where table<string, any>
---@return OrvexTransaction
function Transaction:update(tableName, data, where)
    local q = Query.update(tableName, data, where)
    return self:addRaw(q.sql, q.params)
end

--- Add a DELETE to the transaction.
---@param tableName string
---@param where table<string, any>
---@return OrvexTransaction
function Transaction:delete(tableName, where)
    local q = Query.delete(tableName, where)
    return self:addRaw(q.sql, q.params)
end

--- Add an UPSERT to the transaction.
---@param tableName string
---@param data table<string, any>
---@return OrvexTransaction
function Transaction:upsert(tableName, data)
    local q = Query.upsert(tableName, data)
    return self:addRaw(q.sql, q.params)
end

--- Get the list of queries (for testing/debugging).
---@return OrvexTransactionQuery[]
function Transaction:getQueries()
    return self._queries
end

--- Execute all queries atomically. Returns true on success, false on failure.
---@return boolean success
function Transaction:commit()
    if #self._queries == 0 then
        return true
    end
    return self._adapter:transaction(self._queries)
end

OrvexTransaction = Transaction
return Transaction
