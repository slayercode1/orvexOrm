-- core/relations.lua

local Query   = OrvexQuery or require("core.query")
local Builder = OrvexBuilder or require("core.builder")
local Helpers = OrvexHelpers or require("utils.helpers")

---@alias OrvexRelationType "hasOne"|"hasMany"|"belongsTo"|"belongsToMany"

---@class OrvexRelationDef
---@field type OrvexRelationType
---@field model OrvexModel
---@field foreignKey string
---@field localKey? string
---@field ownerKey? string
---@field pivot? string
---@field otherKey? string

---@class OrvexRelations
local Relations = {}

Relations.HAS_ONE          = "hasOne"
Relations.HAS_MANY         = "hasMany"
Relations.BELONGS_TO       = "belongsTo"
Relations.BELONGS_TO_MANY  = "belongsToMany"

-- ─── Related rows lookup ───────────────────────────────────────────

--- Column of the lookup table that holds the parent's key: the related
--- table for hasOne/hasMany/belongsTo, the pivot for belongsToMany.
---@param rel OrvexRelationDef
---@return string qualified `table.column`
function Relations.lookupColumn(rel)
    if rel.type == Relations.BELONGS_TO_MANY then
        return rel.pivot .. "." .. rel.foreignKey
    elseif rel.type == Relations.BELONGS_TO then
        return rel.model._tableName .. "." .. rel.ownerKey
    end
    return rel.model._tableName .. "." .. rel.foreignKey
end

--- Raw-row builder over the related table: joined through the pivot for
--- belongsToMany, and without the related model's trashed rows. Shared by
--- relation loading, whereHas and countByRelation so they always agree.
---@param rel OrvexRelationDef
---@return OrvexBuilder
function Relations.relatedQuery(rel)
    local related = rel.model
    local relatedTable = related._tableName
    local b = Builder.new(relatedTable, related._adapter, nil, nil)

    if rel.type == Relations.BELONGS_TO_MANY then
        b:select(relatedTable .. ".*")
        b:innerJoin(rel.pivot, rel.pivot .. "." .. rel.otherKey, relatedTable .. "." .. related._primaryKey)
    end
    if related._softDelete then
        b:constrain(function(q) q:whereNull(relatedTable .. ".deleted_at") end)
    end
    return b
end

-- ─── Fetchers ──────────────────────────────────────────────────────
-- A nil key matches nothing: querying with it would drop the condition
-- and return unrelated rows, so the fetchers short-circuit instead. Any
-- other key must be a scalar: a table (an ORM.op marker or data a consumer
-- copied onto the instance) would change the lookup's condition.

---@param key any
---@param rel OrvexRelationDef
---@param column string
local function ensureKey(key, rel, column)
    Helpers.ensureBindable(key, ("%s relation key '%s'"):format(rel.type, column))
end

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance|nil
function Relations.fetchHasOne(instance, rel)
    local key = instance[rel.localKey]
    if key == nil then return nil end
    ensureKey(key, rel, rel.localKey)
    return rel.model.find({ [rel.foreignKey] = key })
end

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance[]
function Relations.fetchHasMany(instance, rel)
    local key = instance[rel.localKey]
    if key == nil then return {} end
    ensureKey(key, rel, rel.localKey)
    return rel.model.findAll({ [rel.foreignKey] = key })
end

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance|nil
function Relations.fetchBelongsTo(instance, rel)
    local key = instance[rel.foreignKey]
    if key == nil then return nil end
    ensureKey(key, rel, rel.foreignKey)
    return rel.model.find({ [rel.ownerKey] = key })
end

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance[]
function Relations.fetchBelongsToMany(instance, rel)
    local key = instance[rel.localKey]
    if key == nil then return {} end
    ensureKey(key, rel, rel.localKey)

    local rows = Relations.relatedQuery(rel):where(Relations.lookupColumn(rel), key):get()
    local results = {}
    for i, row in ipairs(rows) do
        results[i] = rel.model._wrapRow(row)
    end
    return results
end

-- ─── Pivot helpers ─────────────────────────────────────────────────
-- Both keys are required: a nil one would drop its condition, and detach
-- would then delete the links of every parent (or every related row).

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@param relatedInstance OrvexInstance|table
---@param method string
---@return table<string, any> pivot row identifying the link
local function pivotKeys(instance, rel, relatedInstance, method)
    local parentKey = instance[rel.localKey]
    local relatedKey = type(relatedInstance) == "table" and relatedInstance[rel.model._primaryKey] or nil
    Helpers.ensure(parentKey ~= nil,
        ("%s(): the parent has no '%s' value"):format(method, tostring(rel.localKey)))
    Helpers.ensure(relatedKey ~= nil,
        ("%s(): the related row has no '%s' value"):format(method, rel.model._primaryKey))
    Helpers.ensureBindable(parentKey, ("%s(): parent key '%s'"):format(method, tostring(rel.localKey)))
    Helpers.ensureBindable(relatedKey, ("%s(): related key '%s'"):format(method, rel.model._primaryKey))
    return {
        [rel.foreignKey] = parentKey,
        [rel.otherKey]   = relatedKey,
    }
end

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@param relatedInstance OrvexInstance|table
---@return boolean
function Relations.attach(instance, rel, relatedInstance)
    local q = Query.insert(rel.pivot, pivotKeys(instance, rel, relatedInstance, "attach"))
    rel.model._adapter:scalar(q.sql, q.params)
    return true
end

---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@param relatedInstance OrvexInstance|table
---@return boolean
function Relations.detach(instance, rel, relatedInstance)
    local q = Query.delete(rel.pivot, pivotKeys(instance, rel, relatedInstance, "detach"))
    rel.model._adapter:scalar(q.sql, q.params)
    return true
end

OrvexRelations = Relations
return Relations
