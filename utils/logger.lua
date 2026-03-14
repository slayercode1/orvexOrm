-- utils/logger.lua
-- Simple debug logger for SQL queries.
-- Performance-optimized: zero overhead when disabled.

---@class OrvexLogger
local Logger = {}

--- Global debug flag.
Logger._enabled = false

--- Enable or disable debug logging.
---@param enabled boolean
function Logger.setEnabled(enabled)
    Logger._enabled = enabled
end

--- Log a SQL query if debug mode is on.
---@param sql string
---@param params? any[]
function Logger.query(sql, params)
    if not Logger._enabled then return end
    if params and #params > 0 then
        local parts = {}
        for i, p in ipairs(params) do
            parts[i] = tostring(p)
        end
        print("[OrvexORM] " .. sql .. " [" .. table.concat(parts, ", ") .. "]")
    else
        print("[OrvexORM] " .. sql)
    end
end

--- Log a message if debug mode is on.
---@param msg string
function Logger.info(msg)
    if not Logger._enabled then return end
    print("[OrvexORM] " .. msg)
end

OrvexLogger = Logger
return Logger
