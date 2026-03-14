-- core/relations.lua
-- Defines and resolves relations between models.

local Query = OrvexQuery or require("core.query")

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

-- ─── Fetchers ──────────────────────────────────────────────────────

--- Fetch a hasOne related instance.
---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance|nil
function Relations.fetchHasOne(instance, rel)
    return rel.model.find({ [rel.foreignKey] = instance[rel.localKey] })
end

--- Fetch all hasMany related instances.
---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance[]
function Relations.fetchHasMany(instance, rel)
    return rel.model.findAll({ [rel.foreignKey] = instance[rel.localKey] })
end

--- Fetch the parent (belongsTo) instance.
---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance|nil
function Relations.fetchBelongsTo(instance, rel)
    return rel.model.find({ [rel.ownerKey] = instance[rel.foreignKey] })
end

--- Fetch all belongsToMany related instances via a pivot table JOIN.
---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@return OrvexInstance[]
function Relations.fetchBelongsToMany(instance, rel)
    local q = Query.selectJoin(
        rel.model._tableName,
        rel.pivot,
        rel.otherKey,
        rel.model._primaryKey,
        rel.foreignKey,
        instance[rel.localKey]
    )
    local rows = rel.model._adapter:execute(q.sql, q.params)
    if not rows then return {} end

    local results = {}
    for i, row in ipairs(rows) do
        results[i] = rel.model._wrapRow(row)
    end
    return results
end

-- ─── Pivot helpers ─────────────────────────────────────────────────

--- Attach a related instance through the pivot table.
---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@param relatedInstance OrvexInstance
---@return boolean
function Relations.attach(instance, rel, relatedInstance)
    local data = {
        [rel.foreignKey] = instance[rel.localKey],
        [rel.otherKey]   = relatedInstance[rel.model._primaryKey],
    }
    local q = Query.insert(rel.pivot, data)
    rel.model._adapter:scalar(q.sql, q.params)
    return true
end

--- Detach a related instance from the pivot table.
---@param instance OrvexInstance
---@param rel OrvexRelationDef
---@param relatedInstance OrvexInstance
---@return boolean
function Relations.detach(instance, rel, relatedInstance)
    local where = {
        [rel.foreignKey] = instance[rel.localKey],
        [rel.otherKey]   = relatedInstance[rel.model._primaryKey],
    }
    local q = Query.delete(rel.pivot, where)
    rel.model._adapter:scalar(q.sql, q.params)
    return true
end

OrvexRelations = Relations
return Relations
