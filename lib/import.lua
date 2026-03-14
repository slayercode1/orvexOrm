-- lib/import.lua
-- Include this file in your resource to get OrvexORM:
--
-- fxmanifest.lua:
--   dependency 'orvexorm'
--   server_script '@orvexorm/lib/import.lua'
--
-- Then in your scripts:
--   local User = OrvexORM.model("users", { ... })

if not OrvexORM then
    -- Fallback: get via exports
    OrvexORM = exports.orvexorm:lib()
end
