-- tests/test_model_hooks_scopes.lua
-- Model hooks and scopes, declared by method or inline, and findOrCreate / updateOrCreate.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_model_hooks_scopes.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local mockResults = Mock.results
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

-- ─── Test: Hooks ──────────────────────────────────────────────────

T.section("Hooks")

reset()
local hookLog = {}
local HookUser = ORM.model("hook_users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

HookUser.beforeCreate(function(data)
    hookLog[#hookLog + 1] = "beforeCreate"
end)
HookUser.afterCreate(function(instance)
    hookLog[#hookLog + 1] = "afterCreate:" .. instance.identifier
end)

local hu = HookUser.create({ identifier = "license:hook1", money = 100 })
T.eq(hookLog[1], "beforeCreate", "hooks: beforeCreate fired")
T.eq(hookLog[2], "afterCreate:license:hook1", "hooks: afterCreate fired with instance")

-- Test update hooks
HookUser.beforeUpdate(function(instance, data)
    hookLog[#hookLog + 1] = "beforeUpdate"
end)
HookUser.afterUpdate(function(instance)
    hookLog[#hookLog + 1] = "afterUpdate"
end)

reset()
hu:update({ money = 200 })
T.eq(hookLog[3], "beforeUpdate", "hooks: beforeUpdate fired")
T.eq(hookLog[4], "afterUpdate", "hooks: afterUpdate fired")

-- Test delete hooks
HookUser.beforeDelete(function(instance)
    hookLog[#hookLog + 1] = "beforeDelete"
end)
HookUser.afterDelete(function(instance)
    hookLog[#hookLog + 1] = "afterDelete"
end)

reset()
hu:delete()
T.eq(hookLog[5], "beforeDelete", "hooks: beforeDelete fired")
T.eq(hookLog[6], "afterDelete", "hooks: afterDelete fired")

-- ─── Test: Scopes ──────────────────────────────────────────────────

T.section("Scopes")

local ScopeUser = ORM.model("scope_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

ScopeUser.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

ScopeUser.scope("cops", function(b)
    b:where({ job = "police" })
end)

local scopeSQL = ScopeUser.scoped("rich"):toSQL()
T.match(scopeSQL, "`money` > %?", "scopes: rich scope applies WHERE")

local scopeSQL2 = ScopeUser.scoped("cops"):toSQL()
T.match(scopeSQL2, "`job` = %?", "scopes: cops scope applies WHERE")

-- ─── Test: findOrCreate / updateOrCreate ──────────────────────────

T.section("findOrCreate / updateOrCreate")

reset()
-- findOrCreate: not found → creates
mockResults[1] = {} -- find returns empty
local foc, created = ScopeUser.findOrCreate(
    { identifier = "license:new" },
    { money = 500, job = "unemployed" }
)
T.eq(created, true, "findOrCreate: returns created=true when new")
T.eq(foc.identifier, "license:new", "findOrCreate: instance has correct id")

-- findOrCreate: found → returns existing
reset()
mockResults[1] = { { identifier = "license:existing", money = 999, job = "police" } }
local foc2, created2 = ScopeUser.findOrCreate(
    { identifier = "license:existing" },
    { money = 0, job = "none" }
)
T.eq(created2, false, "findOrCreate: returns created=false when found")
T.eq(foc2.money, 999, "findOrCreate: returns existing data")

-- updateOrCreate: not found → creates
reset()
mockResults[1] = {} -- find returns empty
local uoc, uCreated = ScopeUser.updateOrCreate(
    { identifier = "license:uoc" },
    { money = 300, job = "medic" }
)
T.eq(uCreated, true, "updateOrCreate: returns created=true when new")
T.eq(uoc.job, "medic", "updateOrCreate: has correct data")

-- updateOrCreate: found → updates
reset()
mockResults[1] = { { identifier = "license:uoc2", money = 100, job = "unemployed" } }
local uoc2, uCreated2 = ScopeUser.updateOrCreate(
    { identifier = "license:uoc2" },
    { money = 5000, job = "ceo" }
)
T.eq(uCreated2, false, "updateOrCreate: returns created=false when found")
T.eq(uoc2.money, 5000, "updateOrCreate: updated data locally")

-- ─── Test: Scopes as direct methods ─────────────────────────────

T.section("Scopes as direct methods")

local ScopedModel = ORM.model("scoped_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

ScopedModel.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

ScopedModel.scope("cops", function(b)
    b:where({ job = "police" })
end)

-- Direct method call
local richSQL = ScopedModel.rich():toSQL()
T.match(richSQL, "`money` > %?", "scope method: rich() works directly")

local copsSQL = ScopedModel.cops():toSQL()
T.match(copsSQL, "`job` = %?", "scope method: cops() works directly")

-- Chain scoped builder
local chainSQL = ScopedModel.rich():where({ job = "police" }):toSQL()
T.match(chainSQL, "`money` > %?", "scope method: chainable with where")
T.match(chainSQL, "`job` = %?", "scope method: has chained where")

-- ─── Test: Inline hooks ─────────────────────────────────────────

T.section("Inline hooks")

reset()
local inlineHookLog = {}
local InlineHookUser = ORM.model("inline_hook_users", {
    identifier = "string",
    money      = "number",
}, {
    primaryKey = "identifier",
    hooks = {
        beforeCreate = function(data)
            inlineHookLog[#inlineHookLog + 1] = "inline_beforeCreate"
        end,
        afterCreate = function(instance)
            inlineHookLog[#inlineHookLog + 1] = "inline_afterCreate"
        end,
    },
})

InlineHookUser.create({ identifier = "license:inline1", money = 100 })
T.eq(inlineHookLog[1], "inline_beforeCreate", "inline hooks: beforeCreate fired")
T.eq(inlineHookLog[2], "inline_afterCreate", "inline hooks: afterCreate fired")

-- ─── Test: Inline scopes ────────────────────────────────────────

T.section("Inline scopes")

local InlineScopeUser = ORM.model("inline_scope_users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, {
    primaryKey = "identifier",
    scopes = {
        wealthy = function(b) b:where("money", ">", 50000) end,
        active = function(b) b:where({ job = ORM.op("!=", "unemployed") }) end,
    },
})

local wealthySQL = InlineScopeUser.wealthy():toSQL()
T.match(wealthySQL, "`money` > %?", "inline scopes: wealthy() works")

local activeSQL = InlineScopeUser.active():toSQL()
T.match(activeSQL, "`job` != %?", "inline scopes: active() works")

-- Also accessible via scoped()
local scopedSQL = InlineScopeUser.scoped("wealthy"):toSQL()
T.match(scopedSQL, "`money` > %?", "inline scopes: scoped() also works")

T.finish()
