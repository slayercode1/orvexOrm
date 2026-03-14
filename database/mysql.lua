-- database/mysql.lua
-- Auto-detecting MySQL driver for FiveM.
-- Tries oxmysql (MySQL.prepare) first, then mysql-async (MySQL.Async).

---@class OrvexDriver
---@field execute fun(self: OrvexDriver, query: string, params: any[]): table[]
---@field scalar fun(self: OrvexDriver, query: string, params: any[]): any
---@field transaction fun(self: OrvexDriver, queries: OrvexTransactionQuery[]): boolean

-- ─── oxmysql driver (prepared statements) ───────────────────────────

---@class OrvexOxMySQLDriver : OrvexDriver
local OxMySQLDriver = {}
OxMySQLDriver.__index = OxMySQLDriver

function OxMySQLDriver.new()
    return setmetatable({}, OxMySQLDriver)
end

function OxMySQLDriver:execute(query, params)
    local p = promise.new()

    MySQL.prepare(query, params, function(result)
        p:resolve(result or {})
    end)

    return Citizen.Await(p)
end

function OxMySQLDriver:scalar(query, params)
    local p = promise.new()

    MySQL.prepare(query, params, function(result)
        p:resolve(result)
    end)

    return Citizen.Await(p)
end

function OxMySQLDriver:transaction(queries)
    local p = promise.new()

    MySQL.transaction(queries, function(success)
        p:resolve(success)
    end)

    local result = Citizen.Await(p)
    return result ~= false and result ~= nil
end

-- ─── Auto-detect and select driver ──────────────────────────────────

local MySQLDriver

if type(MySQL) == "table" and MySQL.prepare then
    -- oxmysql detected
    MySQLDriver = OxMySQLDriver
elseif type(MySQL) == "table" and MySQL.Async then
    -- mysql-async detected (driver loaded from database/mysql_async.lua)
    assert(OrvexMySQLAsyncDriver, "mysql-async detected but OrvexMySQLAsyncDriver not loaded. Ensure database/mysql_async.lua is loaded before database/mysql.lua")
    MySQLDriver = OrvexMySQLAsyncDriver
else
    -- No library found yet — will be checked when first used.
    -- This allows loading the ORM before MySQL is ready (common in FiveM resource boot order).
    MySQLDriver = OxMySQLDriver
end

OrvexMySQLDriver = MySQLDriver
return MySQLDriver
