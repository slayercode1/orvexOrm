-- utils/logger.lua

---@class OrvexLogger
local Logger = {}

Logger._enabled = false

---@param enabled boolean
function Logger.setEnabled(enabled)
    Logger._enabled = enabled
end

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

---@param msg string
function Logger.info(msg)
    if not Logger._enabled then return end
    print("[OrvexORM] " .. msg)
end

OrvexLogger = Logger
return Logger
