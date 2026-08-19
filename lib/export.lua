-- lib/export.lua
-- Exports the ORM via FiveM exports.

exports('lib', function()
    return OrvexORM
end)

local version = GetResourceMetadata and GetResourceMetadata(GetCurrentResourceName(), "version", 0) or OrvexORM.version
print(("^2[OrvexORM]^0 v%s loaded — ready to use"):format(version))
