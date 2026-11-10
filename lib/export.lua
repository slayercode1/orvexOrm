-- lib/export.lua
-- Exports the ORM via FiveM exports.
--
-- Kept for backward compatibility only. Export values cross resources
-- through msgpack, which drops metatables: rows returned by find/findAll,
-- User.query() builders and the `tx` of ORM.transaction lose their methods
-- in the calling resource. Use `server_script '@orvexorm/lib/import.lua'`
-- instead (see lib/import.lua), which loads a native OrvexORM there.

local Logger = OrvexLogger or require("utils.logger")

local LIMITED_EXPORT_WARNING = "exports.orvexorm:lib() returns a copy without metatables: instance, "
    .. "builder and transaction methods do not work across resources. "
    .. "Use server_script '@orvexorm/lib/import.lua' instead."

local warned = false

local function warnOnce()
    if warned then return end
    warned = true
    Logger.warn(LIMITED_EXPORT_WARNING)
end

exports('lib', function()
    warnOnce()
    return OrvexORM
end)

print(("^2[OrvexORM]^0 v%s loaded — ready to use"):format(OrvexORM.version))
