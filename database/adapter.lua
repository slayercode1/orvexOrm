-- database/adapter.lua

---@class OrvexAdapter
---@field driver OrvexDriver
local Adapter = {}
Adapter.__index = Adapter

---@param driver OrvexDriver
---@return OrvexAdapter
function Adapter.new(driver)
    assert(driver, "Adapter requires a driver")
    assert(driver.execute, "Driver must implement :execute()")
    assert(driver.scalar, "Driver must implement :scalar()")
    return setmetatable({ driver = driver }, Adapter)
end

---@param query string
---@param params any[]
---@return table[]
function Adapter:execute(query, params)
    return self.driver:execute(query, params)
end

---@param query string
---@param params any[]
---@return any
function Adapter:scalar(query, params)
    return self.driver:scalar(query, params)
end

--- Fallback: execute queries one by one if driver lacks transaction support.
--- WARNING: this fallback is NOT atomic — a failing query does not roll back
--- the previous ones. Drivers should implement :transaction() whenever possible.
---@param queries OrvexTransactionQuery[]
---@return boolean success
function Adapter:transaction(queries)
    if self.driver.transaction then
        return self.driver:transaction(queries)
    end
    for _, q in ipairs(queries) do
        local ok = pcall(self.driver.scalar, self.driver, q.query, q.values)
        if not ok then return false end
    end
    return true
end

OrvexAdapter = Adapter
return Adapter
