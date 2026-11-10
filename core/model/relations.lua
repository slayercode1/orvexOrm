-- core/model/relations.lua
-- Relations of a model class: definitions, batched eager loading,
-- whereHas and countByRelation. Fetching one instance's relation lives in
-- core/relations.lua.

local Relations = OrvexRelations or require("core.relations")
local Helpers   = OrvexHelpers or require("utils.helpers")
local Logger    = OrvexLogger or require("utils.logger")

local ensure = Helpers.ensure

---@class OrvexModelRelations
local ModelRelations = {}

---@class OrvexHasOneOpts
---@field foreignKey string
---@field localKey? string

---@class OrvexHasManyOpts
---@field foreignKey string
---@field localKey? string

---@class OrvexBelongsToOpts
---@field foreignKey string
---@field ownerKey? string

---@class OrvexBelongsToManyOpts
---@field pivot string
---@field foreignKey string
---@field otherKey string
---@field localKey? string

local PIVOT_KEY_ALIAS = "__pivot_fk"

-- ─── Pure helpers ──────────────────────────────────────────────────

---@param instances OrvexInstance[]
---@param key string
---@return any[] keys distinct, in first-seen order
local function collectKeys(instances, key)
    local keys, seen = {}, {}
    for _, inst in ipairs(instances) do
        local kv = inst[key]
        if kv ~= nil and not seen[kv] then
            seen[kv] = true
            keys[#keys + 1] = kv
        end
    end
    return keys
end

---@param rel OrvexRelationDef
---@return boolean
local function isToMany(rel)
    return rel.type == Relations.HAS_MANY or rel.type == Relations.BELONGS_TO_MANY
end

---@param byKey table
---@param key any
---@param value any
local function appendTo(byKey, key, value)
    local bucket = byKey[key]
    if not bucket then bucket = {}; byKey[key] = bucket end
    bucket[#bucket + 1] = value
end

--- belongsToMany: one JOIN query for every parent. The pivot key is
--- selected to group the rows, then stripped before wrapping them.
---@param rel OrvexRelationDef
---@param keys any[]
---@return table byKey
local function loadThroughPivot(rel, keys)
    local lookupColumn = Relations.lookupColumn(rel)
    local selectExpr = ("%s.*, %s AS %s"):format(
        rel.model._tableName, Helpers.quoteId(lookupColumn), PIVOT_KEY_ALIAS
    )
    local sql, params = Relations.relatedQuery(rel):whereIn(lookupColumn, keys):_buildSQL(selectExpr)
    Logger.query(sql, params)

    local byKey = {}
    for _, row in ipairs(rel.model._adapter:execute(sql, params) or {}) do
        local fk = row[PIVOT_KEY_ALIAS]
        row[PIVOT_KEY_ALIAS] = nil
        appendTo(byKey, fk, rel.model._wrapRow(row))
    end
    return byKey
end

-- ─── Installation ──────────────────────────────────────────────────

--- Relation definitions: `hasOne`, `hasMany`, `belongsTo`, `belongsToMany`
--- and `applyRelations` for the deferred `opts.relations` callback.
---@param M OrvexModel
---@param ctx OrvexInstanceContext
---@param deferred? fun(model: OrvexModel) `opts.relations`
function ModelRelations.installDefinitions(M, ctx, deferred)
    local relations, primaryKey = ctx.relations, ctx.primaryKey

    ---@param name string
    ---@param relType OrvexRelationType
    ---@param relatedModel OrvexModel
    ---@param ropts? OrvexHasOneOpts|OrvexHasManyOpts
    local function defineLocal(name, relType, relatedModel, ropts)
        ropts = ropts or {}
        relations[name] = {
            type       = relType,
            model      = relatedModel,
            foreignKey = ropts.foreignKey,
            localKey   = ropts.localKey or primaryKey,
        }
    end

    function M.hasOne(name, relatedModel, ropts)
        defineLocal(name, Relations.HAS_ONE, relatedModel, ropts)
    end

    function M.hasMany(name, relatedModel, ropts)
        defineLocal(name, Relations.HAS_MANY, relatedModel, ropts)
    end

    function M.belongsTo(name, relatedModel, ropts)
        ropts = ropts or {}
        relations[name] = {
            type       = Relations.BELONGS_TO,
            model      = relatedModel,
            foreignKey = ropts.foreignKey,
            ownerKey   = ropts.ownerKey or relatedModel._primaryKey,
        }
    end

    function M.belongsToMany(name, relatedModel, ropts)
        ropts = ropts or {}
        ensure(ropts.pivot, "belongsToMany requires a pivot table name")
        relations[name] = {
            type       = Relations.BELONGS_TO_MANY,
            model      = relatedModel,
            pivot      = ropts.pivot,
            foreignKey = ropts.foreignKey,
            otherKey   = ropts.otherKey,
            localKey   = ropts.localKey or primaryKey,
        }
    end

    -- Deferred: registered via opts.relations callback after all models are created.
    if deferred then
        M._pendingRelations = deferred
    end

    function M.applyRelations()
        if M._pendingRelations then
            M._pendingRelations(M)
            M._pendingRelations = nil
        end
    end
end

--- Eager loading, whereHas and countByRelation.
---@param M OrvexModel
---@param ctx OrvexInstanceContext
function ModelRelations.installQueries(M, ctx)
    local relations, primaryKey, tableName = ctx.relations, ctx.primaryKey, ctx.tableName

    --- Resolves which parent column a relation reads (`sourceKey`) and which
    --- column of the lookup table holds it (`lookupKey`, unqualified; the
    --- qualified form is `Relations.lookupColumn`).
    ---@param rel OrvexRelationDef
    ---@return { sourceKey: string, lookupKey: string }
    local function relationShape(rel)
        if rel.type == Relations.BELONGS_TO then
            return { sourceKey = rel.foreignKey, lookupKey = rel.ownerKey }
        end
        return { sourceKey = rel.localKey or primaryKey, lookupKey = rel.foreignKey }
    end

    ---@param name string
    ---@return OrvexRelationDef
    local function requireRelation(name)
        local rel = relations[name]
        ensure(rel, ("Unknown relation '%s'"):format(name))
        return rel
    end

    --- hasOne / hasMany / belongsTo: one whereIn query, rows indexed by the
    --- lookup key (a list per key for hasMany, the first row otherwise).
    ---@param rel OrvexRelationDef
    ---@param keys any[]
    ---@return table byKey
    local function loadDirect(rel, keys)
        local lookupKey = relationShape(rel).lookupKey
        local byKey = {}
        for _, r in ipairs(rel.model.query():whereIn(lookupKey, keys):get()) do
            local fk = r[lookupKey]
            if isToMany(rel) then
                appendTo(byKey, fk, r)
            elseif byKey[fk] == nil then
                byKey[fk] = r
            end
        end
        return byKey
    end

    ---@param instance OrvexInstance
    ---@param relationNames string[]
    function M._eagerLoad(instance, relationNames)
        for _, name in ipairs(relationNames) do
            if relations[name] then
                instance[name] = instance:get(name)
            end
        end
    end

    ---@param instances OrvexInstance[]
    ---@param name string
    ---@param rel OrvexRelationDef
    local function eagerLoadRelation(instances, name, rel)
        local sourceKey = relationShape(rel).sourceKey
        local keys = collectKeys(instances, sourceKey)
        local byKey = {}
        if #keys > 0 then
            local load = rel.type == Relations.BELONGS_TO_MANY and loadThroughPivot or loadDirect
            byKey = load(rel, keys)
        end

        local toMany = isToMany(rel)
        for _, inst in ipairs(instances) do
            local kv = inst[sourceKey]
            local loaded = kv ~= nil and byKey[kv] or nil
            if toMany then loaded = loaded or {} end
            inst[name] = loaded
        end
    end

    --- Batched eager loading: one query per relation instead of one per
    --- instance (avoids N+1).
    ---@param instances OrvexInstance[]
    ---@param relationNames string[]
    function M._eagerLoadMany(instances, relationNames)
        for _, name in ipairs(relationNames) do
            local rel = relations[name]
            if rel then eagerLoadRelation(instances, name, rel) end
        end
    end

    ---@param relationName string
    ---@param callback? fun(builder: OrvexBuilder)
    ---@return OrvexBuilder
    function M.whereHas(relationName, callback)
        local rel = requireRelation(relationName)

        -- The correlation is a constraint so that an orWhere in the callback
        -- stays tied to the parent row: `corr AND (cb1 OR cb2)`.
        local inner = Relations.relatedQuery(rel)
        inner:constrain(function(q)
            q:whereColumn(Relations.lookupColumn(rel), tableName .. "." .. relationShape(rel).sourceKey)
        end)
        if callback then callback(inner) end
        local subSQL, subParams = inner:_buildSQL("1")

        local b = M.query()
        b:whereExists(subSQL, subParams)
        return b
    end

    --- Related row counts per key, in a single GROUP BY query.
    ---@param rel OrvexRelationDef
    ---@param keys any[]
    ---@return table<any, integer>
    local function countRelated(rel, keys)
        local lookupColumn = Relations.lookupColumn(rel)
        local sql, params = Relations.relatedQuery(rel)
            :whereIn(lookupColumn, keys)
            :groupBy(lookupColumn)
            :_buildSQL(Helpers.quoteId(lookupColumn) .. " AS fk, COUNT(*) AS cnt")
        Logger.query(sql, params)

        local byKey = {}
        for _, row in ipairs(ctx.adapter:execute(sql, params) or {}) do
            if row.fk ~= nil then
                byKey[row.fk] = tonumber(row.cnt) or 0
            end
        end
        return byKey
    end

    --- Uses a single GROUP BY query for all instances instead of one
    --- COUNT query per instance (avoids N+1).
    ---@param relationName string
    ---@param where? table<string, any>
    ---@return { instance: OrvexInstance, count: integer }[]
    function M.countByRelation(relationName, where)
        local rel = requireRelation(relationName)
        ensure(rel.type ~= Relations.BELONGS_TO, "countByRelation not supported for belongsTo")

        local b = M.query()
        if where then b:where(where) end
        local results = b:get()

        local counts = {}
        if #results == 0 then return counts end

        local sourceKey = relationShape(rel).sourceKey
        local keys = collectKeys(results, sourceKey)
        local byKey = #keys > 0 and countRelated(rel, keys) or {}

        for _, inst in ipairs(results) do
            local kv = inst[sourceKey]
            local cnt = (kv ~= nil and byKey[kv]) or 0
            inst["_count_" .. relationName] = cnt
            counts[#counts + 1] = { instance = inst, count = cnt }
        end

        return counts
    end
end

OrvexModelRelations = ModelRelations
return ModelRelations
