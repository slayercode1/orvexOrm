-- lib/export.lua
-- Exports the ORM as a global and via FiveM exports.

local ORM = require("core.orm")

OrvexORM = ORM

exports('lib', function()
    return ORM
end)

print("^2[OrvexORM]^0 v1.0.0 loaded — ready to use")
