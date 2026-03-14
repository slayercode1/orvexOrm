-- database/mysql_async.lua
-- Concrete driver for mysql-async (FiveM MySQL library).

---@class OrvexMySQLAsyncDriver : OrvexDriver
local MySQLAsyncDriver = {}
MySQLAsyncDriver.__index = MySQLAsyncDriver

---@return OrvexMySQLAsyncDriver
function MySQLAsyncDriver.new()
    return setmetatable({}, MySQLAsyncDriver)
end

--- Execute a query and return the result set (rows).
--- Uses MySQL.Async.fetchAll for SELECT, MySQL.Async.execute for others.
---@param query string   SQL with `?` placeholders
---@param params any[]   Positional parameters
---@return table[]
function MySQLAsyncDriver:execute(query, params)
    local p = promise.new()

    local upper = query:upper():match("^%s*(%a+)")
    if upper == "SELECT" or upper == "DESCRIBE" or upper == "SHOW" then
        MySQL.Async.fetchAll(query, params, function(result)
            p:resolve(result or {})
        end)
    else
        MySQL.Async.execute(query, params, function(result)
            p:resolve(result or {})
        end)
    end

    return Citizen.Await(p)
end

--- Execute a query and return a scalar result.
--- For INSERT returns the insert id, for UPDATE/DELETE returns affected rows.
---@param query string
---@param params any[]
---@return any
function MySQLAsyncDriver:scalar(query, params)
    local p = promise.new()

    local upper = query:upper():match("^%s*(%a+)")
    if upper == "SELECT" or upper == "DESCRIBE" or upper == "SHOW" then
        MySQL.Async.fetchAll(query, params, function(result)
            if result and result[1] then
                -- Return the first column value of the first row
                for _, v in pairs(result[1]) do
                    p:resolve(v)
                    return
                end
            end
            p:resolve(nil)
        end)
    else
        MySQL.Async.execute(query, params, function(result)
            p:resolve(result)
        end)
    end

    return Citizen.Await(p)
end

--- Execute multiple queries atomically in a transaction.
--- mysql-async may not support MySQL.Async.transaction, so we use a
--- manual BEGIN/COMMIT/ROLLBACK approach as fallback.
---@param queries OrvexTransactionQuery[]  List of { query = "...", values = {...} }
---@return boolean success
function MySQLAsyncDriver:transaction(queries)
    -- Try native transaction support first
    if MySQL.Async.transaction then
        local p = promise.new()

        MySQL.Async.transaction(queries, function(success)
            p:resolve(success)
        end)

        local result = Citizen.Await(p)
        return result ~= false and result ~= nil
    end

    -- Fallback: manual BEGIN/COMMIT/ROLLBACK
    local ok = true

    -- BEGIN
    local pBegin = promise.new()
    MySQL.Async.execute("BEGIN", {}, function()
        pBegin:resolve(true)
    end)
    Citizen.Await(pBegin)

    -- Execute each query
    for _, q in ipairs(queries) do
        local pq = promise.new()
        MySQL.Async.execute(q.query, q.values or {}, function(result)
            pq:resolve(result)
        end)
        local res = Citizen.Await(pq)
        if res == nil or res == false then
            ok = false
            break
        end
    end

    -- COMMIT or ROLLBACK
    local pEnd = promise.new()
    if ok then
        MySQL.Async.execute("COMMIT", {}, function()
            pEnd:resolve(true)
        end)
    else
        MySQL.Async.execute("ROLLBACK", {}, function()
            pEnd:resolve(false)
        end)
    end
    Citizen.Await(pEnd)

    return ok
end

OrvexMySQLAsyncDriver = MySQLAsyncDriver
return MySQLAsyncDriver
