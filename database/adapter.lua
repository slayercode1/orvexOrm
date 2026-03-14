-- database/adapter.lua
-- Abstraction layer for database drivers.

---@class OrvexAdapter
---@field driver OrvexDriver
local Adapter = {}
Adapter.__index = Adapter

--- Create a new adapter that delegates to a concrete driver.
---@param driver OrvexDriver  Must implement :execute(), :scalar(), and :transaction()
---@return OrvexAdapter
function Adapter.new(driver)
    assert(driver, "Adapter requires a driver")
    assert(driver.execute, "Driver must implement :execute()")
    assert(driver.scalar, "Driver must implement :scalar()")
    return setmetatable({ driver = driver }, Adapter)
end

--- Run a query that returns rows (SELECT).
---@param query string
---@param params any[]
---@return table[]
function Adapter:execute(query, params)
    return self.driver:execute(query, params)
end

--- Run a query that returns a single scalar (INSERT id, affected rows, etc.).
---@param query string
---@param params any[]
---@return any
function Adapter:scalar(query, params)
    return self.driver:scalar(query, params)
end

--- Execute multiple queries atomically in a transaction.
---@param queries OrvexTransactionQuery[]
---@return boolean success
function Adapter:transaction(queries)
    if self.driver.transaction then
        return self.driver:transaction(queries)
    end
    -- Fallback: execute queries one by one (no atomicity guarantee)
    for _, q in ipairs(queries) do
        self.driver:scalar(q.query, q.values)
    end
    return true
end

OrvexAdapter = Adapter
return Adapter
