-- tests/support/fivem_mock.lua
-- FiveM runtime double for the model-level suites. Requiring it installs the
-- globals the ORM expects (json, promise, Citizen, exports, MySQL) and a
-- MySQL driver that records every statement instead of running it.
-- Usage:
--   local Mock = require("tests.support.fivem_mock")
--   Mock.results[1] = { { id = 1 } }  -- rows returned by the 1st statement
--   ... Mock.log[1].sql, Mock.txLog[1] ...
--   Mock.reset()                       -- clears log, results and txLog in place

local Mock = {
    log     = {}, ---@type { sql: string, params: any[] }[] statements, in order
    results = {}, ---@type table<integer, any> result of the n-th statement
    txLog   = {}, ---@type table[] query batches sent to MySQL.transaction
}

-- Real JSON codec: escaping and array round-trips are exercised for real.
json = require("tests.support.json")

promise = {
    new = function()
        local p = { _value = nil }
        function p:resolve(v) self._value = v end
        return p
    end,
}

Citizen = { Await = function(p) return p._value end }

-- Every export resolves to a no-op: the driver falls back to the MySQL global.
exports = setmetatable({}, {
    __index = function()
        return setmetatable({}, {
            __index = function() return function() return nil end end,
        })
    end,
})

--- Driver call: logs the statement, then answers with the queued result,
--- or 1 (insert id / affected rows) and {} for a SELECT.
local function driverCall(query, params, cb)
    Mock.log[#Mock.log + 1] = { sql = query, params = params }
    local result = Mock.results[#Mock.log]
    if result ~= nil then return cb(result) end
    if query:match("^SELECT") then return cb({}) end
    return cb(1)
end

local function transaction(queries, cb)
    Mock.txLog[#Mock.txLog + 1] = queries
    cb(true)
end

MySQL = {
    prepare = driverCall,
    query = driverCall,
    insert = driverCall,
    update = driverCall,
    transaction = transaction,
    Async = {
        fetchAll = driverCall,
        execute = driverCall,
        insert = driverCall,
        transaction = transaction,
    },
}

---@param t table
local function clear(t)
    for k in pairs(t) do t[k] = nil end
end

--- Forgets what the driver recorded. Tables are cleared in place, so the
--- references a suite keeps to Mock.log / results / txLog stay valid.
function Mock.reset()
    clear(Mock.log)
    clear(Mock.results)
    clear(Mock.txLog)
end

return Mock
