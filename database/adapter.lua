-- database/adapter.lua

---@class OrvexAdapterOptions
---@field allowNonAtomicTransactions? boolean run transactions query by query when the driver has no :transaction()

---@class OrvexAdapter
---@field driver OrvexDriver
---@field allowNonAtomicTransactions boolean
local Adapter = {}
Adapter.__index = Adapter

local NON_ATOMIC_REFUSED = "OrvexORM: this driver has no :transaction(), so a transaction cannot be atomic. "
    .. "Implement driver:transaction(queries), or accept partial commits explicitly with "
    .. "Adapter.new(driver, { allowNonAtomicTransactions = true })"

---@param driver OrvexDriver
---@param opts? OrvexAdapterOptions
---@return OrvexAdapter
function Adapter.new(driver, opts)
    assert(driver, "Adapter requires a driver")
    assert(driver.execute, "Driver must implement :execute()")
    assert(driver.scalar, "Driver must implement :scalar()")
    return setmetatable({
        driver = driver,
        allowNonAtomicTransactions = (opts and opts.allowNonAtomicTransactions) == true,
    }, Adapter)
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

--- Delegates to driver:transaction(). A driver without it is refused unless the
--- adapter opts in with `allowNonAtomicTransactions = true`: the queries then run
--- one by one and are NOT atomic. A failing query does not roll back the ones
--- before it: the second result then reports that part of the batch was
--- committed, so the caller can drop what it cached for those tables.
---@param queries OrvexTransactionQuery[]
---@return boolean success
---@return boolean partiallyCommitted false on success or when nothing was committed
function Adapter:transaction(queries)
    if self.driver.transaction then
        return self.driver:transaction(queries), false
    end
    if not self.allowNonAtomicTransactions then
        error(NON_ATOMIC_REFUSED, 2)
    end
    for index, q in ipairs(queries) do
        local ok = pcall(self.driver.scalar, self.driver, q.query, q.values)
        if not ok then return false, index > 1 end
    end
    return true, false
end

OrvexAdapter = Adapter
return Adapter
