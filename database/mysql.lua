-- database/mysql.lua
-- MySQL driver for FiveM -- compatible with oxmysql and mysql-async.
-- Uses oxmysql SYNC exports when available, falls back to global MySQL API.

---@param query string
---@return string|nil verb
local function sqlVerb(query)
    local verb = query:match("^%s*(%a+)")
    return verb and verb:upper() or nil
end

---@param query string
---@return boolean
local function isReadQuery(query)
    local verb = sqlVerb(query)
    return verb == "SELECT" or verb == "DESCRIBE" or verb == "SHOW" or verb == "EXPLAIN"
end

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

---@param fn function
---@param query string
---@param params any[]
---@return any
local function awaitCallback(fn, query, params)
    local p = promise.new()
    fn(query, params, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end

function AutoDriver:execute(query, params)
    self:_detect()
    if self._mode == "oxmysql_export" then
        local result = exports.oxmysql:executeSync(query, params)
        return type(result) == "table" and result or {}
    elseif self._mode == "oxmysql_global" then
        -- MySQL.query always returns an array of rows for SELECT,
        -- unlike MySQL.prepare which flattens single-row/single-column results.
        local result = awaitCallback(MySQL.query, query, params)
        return type(result) == "table" and result or {}
    else
        local p = promise.new()
        if isReadQuery(query) then
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
    local verb = sqlVerb(query)
    if self._mode == "oxmysql_export" then
        if verb == "INSERT" then
            return exports.oxmysql:insertSync(query, params)
        elseif isReadQuery(query) then
            return exports.oxmysql:executeSync(query, params)
        else
            return exports.oxmysql:updateSync(query, params)
        end
    elseif self._mode == "oxmysql_global" then
        if verb == "INSERT" then
            return awaitCallback(MySQL.insert, query, params)
        elseif verb == "UPDATE" or verb == "DELETE" then
            return awaitCallback(MySQL.update, query, params)
        else
            return awaitCallback(MySQL.query, query, params)
        end
    else
        local p = promise.new()
        if verb == "INSERT" then
            MySQL.Async.insert(query, params, function(r) p:resolve(r) end)
        else
            MySQL.Async.execute(query, params, function(r) p:resolve(r) end)
        end
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
