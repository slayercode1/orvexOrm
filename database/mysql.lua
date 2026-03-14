-- database/mysql.lua
-- MySQL driver for FiveM -- compatible with oxmysql and mysql-async.
-- Uses oxmysql SYNC exports when available, falls back to global MySQL API.

---@class OrvexAutoDriver : OrvexDriver
local AutoDriver = {}
AutoDriver.__index = AutoDriver
AutoDriver._mode = nil

function AutoDriver.new()
    return setmetatable({}, AutoDriver)
end

function AutoDriver:_detect()
    if self._mode then return end

    if type(MySQL) == "table" and MySQL.prepare then
        self._mode = "oxmysql_global"
        return
    end
    if type(MySQL) == "table" and MySQL.Async then
        self._mode = "mysql-async"
        return
    end

    local ok, _ = pcall(function()
        return exports.oxmysql and exports.oxmysql.executeSync
    end)
    if ok and exports.oxmysql and exports.oxmysql.executeSync then
        self._mode = "oxmysql_export"
        return
    end

    error("No MySQL library found. Ensure oxmysql or mysql-async is started before orvexorm.")
end

function AutoDriver:execute(query, params)
    self:_detect()
    if self._mode == "oxmysql_export" then
        local result = exports.oxmysql:executeSync(query, params)
        return type(result) == "table" and result or {}
    elseif self._mode == "oxmysql_global" then
        local p = promise.new()
        MySQL.prepare(query, params, function(result)
            if type(result) == "table" then
                p:resolve(result)
            else
                p:resolve({})
            end
        end)
        return Citizen.Await(p)
    else
        local p = promise.new()
        local upper = query:upper():match("^%s*(%a+)")
        if upper == "SELECT" or upper == "DESCRIBE" or upper == "SHOW" then
            MySQL.Async.fetchAll(query, params, function(r) p:resolve(r or {}) end)
        else
            MySQL.Async.execute(query, params, function(r)
                p:resolve(type(r) == "table" and r or {})
            end)
        end
        return Citizen.Await(p)
    end
end

function AutoDriver:scalar(query, params)
    self:_detect()
    if self._mode == "oxmysql_export" then
        local upper = query:upper():match("^%s*(%a+)")
        if upper == "INSERT" then
            return exports.oxmysql:insertSync(query, params)
        elseif upper == "SELECT" or upper == "DESCRIBE" or upper == "SHOW" then
            return exports.oxmysql:executeSync(query, params)
        else
            return exports.oxmysql:updateSync(query, params)
        end
    elseif self._mode == "oxmysql_global" then
        local p = promise.new()
        MySQL.prepare(query, params, function(result)
            p:resolve(result)
        end)
        return Citizen.Await(p)
    else
        local p = promise.new()
        MySQL.Async.execute(query, params, function(r) p:resolve(r) end)
        return Citizen.Await(p)
    end
end

function AutoDriver:transaction(queries)
    self:_detect()
    if self._mode == "oxmysql_export" then
        local result = exports.oxmysql:transactionSync(queries)
        return result ~= false and result ~= nil
    elseif self._mode == "oxmysql_global" then
        local p = promise.new()
        MySQL.transaction(queries, function(success) p:resolve(success) end)
        local result = Citizen.Await(p)
        return result ~= false and result ~= nil
    else
        local ok = true
        local pb = promise.new()
        MySQL.Async.execute("BEGIN", {}, function() pb:resolve(true) end)
        Citizen.Await(pb)
        for _, q in ipairs(queries) do
            local pq = promise.new()
            MySQL.Async.execute(q.query, q.values or {}, function(r) pq:resolve(r) end)
            if Citizen.Await(pq) == false then ok = false; break end
        end
        local pe = promise.new()
        MySQL.Async.execute(ok and "COMMIT" or "ROLLBACK", {}, function() pe:resolve(ok) end)
        Citizen.Await(pe)
        return ok
    end
end

OrvexMySQLDriver = AutoDriver
return AutoDriver
