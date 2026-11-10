-- core/model.lua
-- Model factory. Each call to Model.new() returns a typed model class.
--
-- The class is assembled from focused modules:
--   core/model/hooks.lua      lifecycle hooks (event table and dispatch)
--   core/model/write.lua      shared write helpers (affected rows, validation)
--   core/model/instance.lua   instances: one shared metatable per model
--   core/model/querying.lua   builders, scopes, aggregates, read shortcuts
--   core/model/crud.lua       create / find / update / delete / upsert...
--   core/model/relations.lua  relation definitions, eager loading, whereHas
--   core/model/nested.lua     createWith (nested writes)
--
-- Conventions (errors, write results) are described in crud.lua, the
-- hooks each method fires in hooks.lua.

local SchemaLib      = OrvexSchema or require("core.schema")
local CacheLib       = OrvexCache or require("utils.cache")
local Hooks          = OrvexModelHooks or require("core.model.hooks")
local InstanceLib    = OrvexModelInstance or require("core.model.instance")
local Querying       = OrvexModelQuerying or require("core.model.querying")
local Crud           = OrvexModelCrud or require("core.model.crud")
local ModelRelations = OrvexModelRelations or require("core.model.relations")
local Nested         = OrvexModelNested or require("core.model.nested")

---@class OrvexModelFactory
local Model = {}

---@type string[]
Model.HOOK_EVENTS = Hooks.EVENTS

---@class OrvexModelOpts
---@field primaryKey? string
---@field adapter? OrvexAdapter
---@field cache? OrvexCache
---@field softDelete? boolean
---@field timestamps? boolean
---@field allowManagedColumns? boolean let callers set created_at / updated_at themselves (imports)
---@field hooks? OrvexHookMap one function per event (see lib/types/orvexorm.d.lua)
---@field scopes? table<string, fun(builder: OrvexBuilder)>
---@field relations? fun(model: OrvexModel)

---@class OrvexModel
---@field _tableName string
---@field _schema OrvexSchema
---@field _adapter OrvexAdapter
---@field _primaryKey string
---@field _cache OrvexCache
---@field _softDelete boolean
---@field _wrapRow fun(row: table): OrvexInstance
---@field _prepareInsertRows fun(rows: table[]): table[]
---@field _eagerLoad fun(instance: OrvexInstance, relationNames: string[])
---@field _eagerLoadMany fun(instances: OrvexInstance[], relationNames: string[])
---@field _pendingRelations? fun(model: OrvexModel)

---@param tableName string
---@param fields table<string, OrvexFieldType>
---@param adapter OrvexAdapter
---@param opts? OrvexModelOpts
---@param cache? OrvexCache
---@return OrvexInstanceContext
local function newContext(tableName, fields, adapter, opts, cache)
    local softDelete = opts.softDelete or false
    local timestamps = opts.timestamps or false
    return {
        tableName  = tableName,
        schema     = SchemaLib.new(fields, {
            timestamps = timestamps,
            softDelete = softDelete,
            allowManagedColumns = opts.allowManagedColumns,
        }),
        adapter    = adapter,
        cache      = cache or CacheLib.new({ enabled = false }),
        primaryKey = opts.primaryKey or "id",
        relations  = {},
        hooks      = {},
        softDelete = softDelete,
        timestamps = timestamps,
    }
end

---@param tableName string
---@param fields table<string, OrvexFieldType>
---@param adapter OrvexAdapter
---@param opts? OrvexModelOpts
---@param cache? OrvexCache
---@return OrvexModel
function Model.new(tableName, fields, adapter, opts, cache)
    opts = opts or {}
    local ctx = newContext(tableName, fields, adapter, opts, cache)

    -- The public methods are installed below (declared in lib/types/orvexorm.d.lua).
    ---@diagnostic disable: missing-fields
    ---@type OrvexModel
    local M = {
        _tableName  = ctx.tableName,
        _schema     = ctx.schema,
        _adapter    = ctx.adapter,
        _primaryKey = ctx.primaryKey,
        _cache      = ctx.cache,
        _softDelete = ctx.softDelete,
    }
    ---@diagnostic enable: missing-fields

    local class = InstanceLib.newClass(ctx)
    function M._wrapRow(row)
        return InstanceLib.wrap(row, class)
    end

    -- Order matters for user-named scopes: they are installed first, so a
    -- scope named like a built-in method is replaced by that method.
    Hooks.install(M, ctx.hooks, opts.hooks)
    Querying.installScopes(M, opts.scopes)
    ModelRelations.installDefinitions(M, ctx, opts.relations)
    Crud.install(M, ctx)
    ModelRelations.installQueries(M, ctx)
    Nested.install(M, ctx)
    Querying.install(M, ctx)

    return M
end

OrvexModelFactory = Model
return Model
