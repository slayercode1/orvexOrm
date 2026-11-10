-- database/mysql.lua
-- MySQL driver for FiveM -- compatible with oxmysql and mysql-async.
--
-- Detection order (first match wins):
--   1. MySQL global from @oxmysql/lib/MySQL.lua      -> "oxmysql_global"
--   2. MySQL.Async global from @mysql-async/lib/MySQL.lua -> "mysql-async"
--   3. oxmysql resource started (sync exports)       -> "oxmysql_export"
--   4. mysql-async resource started (exports)        -> "mysql-async"
-- The default orvexorm fxmanifest loads neither lib, so 3 and 4 are the usual paths.
--
-- Every call yields the current thread: run it inside Citizen.CreateThread,
-- an event handler or another coroutine-backed context.

-- luacheck: read globals GetResourceState

local THREAD_REQUIRED = "OrvexORM: database calls yield and must run inside Citizen.CreateThread, "
    .. "an event handler or another thread"

local MYSQL_ASYNC_TRANSACTION_REQUIRED = "OrvexORM: atomic transactions need mysql-async >= 3.3 "
    .. "(MySQL.Async.transaction); upgrade mysql-async or switch to oxmysql"

local MYSQL_ASYNC_READ_FAILED = "OrvexORM: mysql-async returned no result for a read query "
    .. "(the query most likely failed): %s"

local Helpers = OrvexHelpers or require("utils.helpers")

local sqlVerb = Helpers.sqlVerb

---@param query string
---@return boolean
local function isReadQuery(query)
    return Helpers.isReadVerb(sqlVerb(query))
end

---@param result any
---@return boolean
local function isSuccess(result)
    return result ~= false and result ~= nil
end

---@param result any
---@return table
local function asTable(result)
    return type(result) == "table" and result or {}
end

-- ─── Resource detection ────────────────────────────────────────────

--- In FiveM `exports[resource]` always returns a proxy, so the resource state
--- is the only reliable signal. Outside FiveM (tests), probe the export itself.
---@param resource string
---@param exportName string
---@return boolean
local function hasExport(resource, exportName)
    if type(GetResourceState) == "function" and GetResourceState(resource) ~= "started" then
        return false
    end
    local ok, fn = pcall(function()
        return exports[resource] and exports[resource][exportName]
    end)
    return ok and fn ~= nil
end

---@return boolean
local function hasOxmysqlGlobal()
    return type(MySQL) == "table" and MySQL.prepare ~= nil
end

---@return boolean
local function hasMysqlAsyncGlobal()
    return type(MySQL) == "table" and type(MySQL.Async) == "table"
end

--- Same shape as the MySQL.Async global, backed by exports['mysql-async'].
---@return table
local function mysqlAsyncFromExports()
    local function forward(exportName)
        return function(...)
            return exports["mysql-async"][exportName](exports["mysql-async"], ...)
        end
    end
    return {
        fetchAll = forward("mysql_fetch_all"),
        execute = forward("mysql_execute"),
        insert = forward("mysql_insert"),
        transaction = forward("mysql_transaction"),
    }
end

-- ─── Await helpers ─────────────────────────────────────────────────

---@param err any
---@return boolean
local function isYieldError(err)
    local message = tostring(err)
    return message:find("yield", 1, true) ~= nil or message:find("scheduler", 1, true) ~= nil
end

--- Runs `fn`; outside a thread, turns the cryptic yield failure into a clear error.
--- A strict up-front check is avoided on purpose: a call whose result is already
--- available never yields and stays valid outside a thread.
---@param fn function
---@return any
local function runYielding(fn, ...)
    if coroutine.isyieldable() then
        return fn(...)
    end
    local outcome = table.pack(pcall(fn, ...))
    if outcome[1] then
        return table.unpack(outcome, 2, outcome.n)
    end
    if isYieldError(outcome[2]) then
        error(("%s (%s)"):format(THREAD_REQUIRED, tostring(outcome[2])), 0)
    end
    error(outcome[2], 0)
end

---@param fn function callback-style API: fn(query, params, cb)
---@param query any
---@param params any
---@return any
local function awaitCallback(fn, query, params)
    local p = promise.new()
    fn(query, params, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end

--- Calls an @oxmysql/lib function. Its `.await` form raises on SQL errors, whereas
--- the callback form never calls back on error and would hang the thread.
---@param fn table|function
---@param query any
---@param params any
---@return any
local function oxmysqlAwait(fn, query, params)
    if type(fn) == "table" and fn.await then
        return fn.await(query, params)
    end
    return awaitCallback(fn, query, params)
end

--- oxmysql's transaction takes the callback as its second argument.
---@param queries OrvexTransactionQuery[]
---@return any
local function oxmysqlTransaction(queries)
    local transaction = MySQL.transaction
    if type(transaction) == "table" and transaction.await then
        return transaction.await(queries)
    end
    local p = promise.new()
    transaction(queries, function(success) p:resolve(success) end)
    return Citizen.Await(p)
end

--- mysql-async names the per-query bind values `parameters`, oxmysql's shim `values`.
---@param queries OrvexTransactionQuery[]
---@return table[]
local function toMysqlAsyncQueries(queries)
    local converted = {}
    for i, q in ipairs(queries) do
        local values = q.values or {}
        converted[i] = { query = q.query, values = values, parameters = values }
    end
    return converted
end

--- mysql-async fetchAll gives {} for an empty result, so nil means the query
--- failed. Raising keeps a transient failure from being cached as "no rows".
---@param async table MySQL.Async-shaped API
---@param query string
---@param params any
---@return table[] rows
local function mysqlAsyncFetchAll(async, query, params)
    local rows = awaitCallback(async.fetchAll, query, params)
    if rows == nil then
        error(MYSQL_ASYNC_READ_FAILED:format(query), 0)
    end
    return rows
end

-- ─── Driver ────────────────────────────────────────────────────────

---@class OrvexAutoDriver : OrvexDriver
local AutoDriver = {}
AutoDriver.__index = AutoDriver
AutoDriver._mode = nil

function AutoDriver.new()
    return setmetatable({}, AutoDriver)
end

function AutoDriver:_detect()
    if self._mode then return end

    if hasOxmysqlGlobal() then
        self._mode = "oxmysql_global"
    elseif hasMysqlAsyncGlobal() then
        self._mode, self._async = "mysql-async", MySQL.Async
    elseif hasExport("oxmysql", "executeSync") then
        self._mode = "oxmysql_export"
    elseif hasExport("mysql-async", "mysql_execute") then
        self._mode, self._async = "mysql-async", mysqlAsyncFromExports()
    else
        error("No MySQL library found. Ensure oxmysql or mysql-async is started before orvexorm.")
    end
end

-- oxmysql_global keeps MySQL.query (text protocol) rather than MySQL.prepare /
-- MySQL.rawExecute (binary protocol): prepare flattens single-row/single-column
-- results, both treat a table parameter as a batch of parameter sets, the binary
-- protocol rejects some statements (DDL used by migrations) and typed numeric
-- binds, and no measurement shows a gain for this ORM's workload.

function AutoDriver:_execute(query, params)
    self:_detect()
    if self._mode == "oxmysql_export" then
        return asTable(exports.oxmysql:executeSync(query, params))
    elseif self._mode == "oxmysql_global" then
        return asTable(oxmysqlAwait(MySQL.query, query, params))
    elseif isReadQuery(query) then
        return asTable(mysqlAsyncFetchAll(self._async, query, params))
    else
        return asTable(awaitCallback(self._async.execute, query, params))
    end
end

function AutoDriver:_scalar(query, params)
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
            return oxmysqlAwait(MySQL.insert, query, params)
        elseif verb == "UPDATE" or verb == "DELETE" then
            return oxmysqlAwait(MySQL.update, query, params)
        else
            return oxmysqlAwait(MySQL.query, query, params)
        end
    elseif verb == "INSERT" then
        return awaitCallback(self._async.insert, query, params)
    elseif isReadQuery(query) then
        return mysqlAsyncFetchAll(self._async, query, params)
    else
        return awaitCallback(self._async.execute, query, params)
    end
end

--- mysql-async runs each execute() on its pool, so a manual BEGIN/COMMIT would not
--- share a connection: only its native transaction is atomic.
function AutoDriver:_mysqlAsyncTransaction(queries)
    local transaction = self._async.transaction
    if type(transaction) ~= "function" then
        error(MYSQL_ASYNC_TRANSACTION_REQUIRED, 0)
    end
    local p = promise.new()
    transaction(toMysqlAsyncQueries(queries), {}, function(success) p:resolve(success) end)
    return isSuccess(Citizen.Await(p))
end

function AutoDriver:_transaction(queries)
    self:_detect()
    if self._mode == "oxmysql_export" then
        return isSuccess(exports.oxmysql:transactionSync(queries))
    elseif self._mode == "oxmysql_global" then
        return isSuccess(oxmysqlTransaction(queries))
    else
        return self:_mysqlAsyncTransaction(queries)
    end
end

---@param query string
---@param params any[]
---@return table[]
function AutoDriver:execute(query, params)
    return runYielding(self._execute, self, query, params)
end

---@param query string
---@param params any[]
---@return any
function AutoDriver:scalar(query, params)
    return runYielding(self._scalar, self, query, params)
end

---@param queries OrvexTransactionQuery[]
---@return boolean success
function AutoDriver:transaction(queries)
    return runYielding(self._transaction, self, queries)
end

OrvexMySQLDriver = AutoDriver
return AutoDriver
