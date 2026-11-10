-- .luacheckrc
-- Luacheck configuration for OrvexORM (FiveM server-only resource, Lua 5.4).
-- Run: luacheck .
-- Works with luacheck 1.x (CI) and 0.23 (pipelinecomponents/luacheck image).

-- luacheck 0.23 has no "lua54" std, so start from lua53 and declare the
-- Lua 5.4 additions explicitly. The result is the same under both versions.
std = "lua53"
local lua54Additions = { "warn", coroutine = { fields = { "close" } } }
max_line_length = 240
-- .lua, .lua-build and .luarocks are created inside the workspace by the CI Lua setup actions.
exclude_files = { "docs/**", "release/**", ".claude/**", ".lua/**", ".lua-build/**", ".luarocks/**" }

-- Natives and runtime globals provided by FiveM / oxmysql / ox_lib.
local fivemGlobals = {
    "MySQL", "Citizen", "CreateThread", "Wait", "SetTimeout",
    "exports", "promise", "json", "lib", "source",
    "GetConvar", "GetConvarInt", "GetResourceMetadata", "GetResourcePath",
    "GetCurrentResourceName", "LoadResourceFile", "SaveResourceFile",
    "SetHttpHandler", "RegisterCommand", "IsPlayerAceAllowed",
    "AddEventHandler", "RegisterNetEvent", "TriggerEvent", "GetGameTimer",
    "GetNumResourceMetadata", "GetResourceState", "IsDuplicityVersion",
}

-- Module globals OrvexORM itself publishes, because FiveM loads every
-- server_script into one shared environment without require().
local orvexGlobals = {
    "OrvexORM", "OrvexHelpers", "OrvexSerializer", "OrvexValidator",
    "OrvexCache", "OrvexErrors", "OrvexLogger", "OrvexMySQLDriver",
    "OrvexAdapter", "OrvexSchema", "OrvexQuery", "OrvexRelations",
    "OrvexBuilder", "OrvexTransaction", "OrvexMigration", "OrvexModelFactory",
    -- core/model/*.lua building blocks of the model factory
    "OrvexModelHooks", "OrvexModelInstance", "OrvexModelQuerying", "OrvexModelCrud",
    "OrvexModelRelations", "OrvexModelNested", "OrvexModelWrite",
}

local function concat(...)
    local result = {}
    for _, list in ipairs({ ... }) do
        for key, value in pairs(list) do
            if type(key) == "number" then result[#result + 1] = value else result[key] = value end
        end
    end
    return result
end

read_globals = concat(lua54Additions, fivemGlobals)
globals = orvexGlobals

-- fxmanifest.lua is a declarative manifest whose directives are globals.
files["fxmanifest.lua"] = {
    std = "min",
    read_globals = {
        "fx_version", "game", "games", "server_only", "name", "version",
        "author", "description", "repository", "lua54", "provide",
        "dependency", "dependencies", "files", "server_script", "server_scripts",
        "shared_script", "shared_scripts", "client_script", "client_scripts",
        "ui_page",
    },
}

-- Tests stub the FiveM runtime: they assign the natives as globals, stub
-- os.time, and use loose mock signatures and reused fixture names.
files["tests/**"] = {
    globals = concat(fivemGlobals, orvexGlobals),
    read_globals = lua54Additions,
    ignore = {
        "122/os",  -- os.time stubbed to control the clock
        "211",     -- unused fixture locals
        "212",     -- unused arguments in mock callbacks
        "213",     -- unused loop variables in warmup loops
        "231",     -- variables kept for readability of pcall results
        "311",     -- params reset between test blocks
        "421",     -- shadowing locals across test blocks
        "431",     -- shadowing upvalues across test blocks
    },
}

-- First-value extraction from a SHOW TABLES row: the loop runs once on purpose.
files["lib/studio.lua"] = { ignore = { "512" } }

-- TODO: remove once the unused `Helpers` import is dropped from core/transaction.lua.
files["core/transaction.lua"] = { ignore = { "211/Helpers" } }
