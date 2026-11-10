-- core/model/nested.lua
-- Nested writes: `Model.createWith(data)` creates a row and the rows of
-- its hasOne / hasMany / belongsToMany relations.

local Query       = OrvexQuery or require("core.query")
local Helpers     = OrvexHelpers or require("utils.helpers")
local Relations   = OrvexRelations or require("core.relations")
local Logger      = OrvexLogger or require("utils.logger")
local Transaction = OrvexTransaction or require("core.transaction")

local ensure = Helpers.ensure

---@class OrvexModelNested
local Nested = {}

-- ─── Pure helpers ──────────────────────────────────────────────────

--- Nested data of a relation as an array of rows (hasOne takes one row).
---@param rel OrvexRelationDef
---@param relData any
---@return table[]
local function nestedRows(rel, relData)
    ensure(type(relData) == "table", rel.type .. " nested data must be a table")
    if rel.type == Relations.HAS_ONE then return { relData } end
    return relData
end

--- Queues multi-row inserts. insertMany takes its column list from the
--- first row, so rows are grouped by key set to never drop a column.
---@param tx OrvexTransaction
---@param targetTable string
---@param rows table[] encoded rows
local function queueInserts(tx, targetTable, rows)
    local groups, order = {}, {}
    for _, row in ipairs(rows) do
        local signature = table.concat(Helpers.sortedKeys(row), ",")
        if not groups[signature] then
            groups[signature] = {}
            order[#order + 1] = signature
        end
        local group = groups[signature]
        group[#group + 1] = row
    end
    for _, signature in ipairs(order) do
        local q = Query.insertMany(targetTable, groups[signature])
        Logger.query(q.sql, q.params)
        tx:addRaw(q.sql, q.params)
    end
end

---@param entry { model: OrvexModel, key: any }
local function deleteCreated(entry)
    local model = entry.model
    local q = Query.delete(model._tableName, { [model._primaryKey] = entry.key })
    Logger.query(q.sql, q.params)
    model._adapter:scalar(q.sql, q.params)
    model._cache:invalidateTable(model._tableName)
end

--- Compensates a failed nested write: the transaction cannot include the
--- rows whose generated id it needs, so they are deleted, newest first.
--- Every delete is attempted; the ones that fail are reported.
---@param created { model: OrvexModel, key: any }[]
---@return string[] leftovers `table#key: error` of the rows still in the database
local function removeCreated(created)
    local leftovers = {}
    for i = #created, 1, -1 do
        local entry = created[i]
        if entry.key ~= nil then
            local ok, err = pcall(deleteCreated, entry)
            if not ok then
                leftovers[#leftovers + 1] = ("%s#%s: %s")
                    :format(entry.model._tableName, tostring(entry.key), tostring(err))
            end
        end
    end
    return leftovers
end

---@param tableName string
---@param cause any
---@param leftovers string[]
---@return string
local function nestedFailureMessage(tableName, cause, leftovers)
    if #leftovers == 0 then
        return ("createWith('%s'): nested rows were not written, created rows removed: %s")
            :format(tableName, tostring(cause))
    end
    return ("createWith('%s'): nested rows were not written: %s; these created rows could not be removed: %s")
        :format(tableName, tostring(cause), table.concat(leftovers, "; "))
end

-- ─── Installation ──────────────────────────────────────────────────

---@param M OrvexModel
---@param ctx OrvexInstanceContext
function Nested.install(M, ctx)
    local relations, primaryKey = ctx.relations, ctx.primaryKey

    ---@param data table<string, any>
    ---@return table mainData
    ---@return table<string, any> nestedData keyed by relation name
    local function splitNestedData(data)
        local mainData, nestedData = {}, {}
        for k, v in pairs(data) do
            if relations[k] then
                nestedData[k] = v
            else
                mainData[k] = v
            end
        end
        return mainData, nestedData
    end

    --- Validates every nested row up front so invalid data writes nothing.
    --- belongsTo entries are ignored, as they always were.
    ---@param nestedData table<string, any>
    local function validateNested(nestedData)
        for relName, relData in pairs(nestedData) do
            local rel = relations[relName]
            if rel.type ~= Relations.BELONGS_TO then
                rel.model._prepareInsertRows(nestedRows(rel, relData))
            end
        end
    end

    ---@param instance OrvexInstance
    ---@param rel OrvexRelationDef
    ---@return any
    local function parentKeyOf(instance, rel)
        return instance[rel.localKey or primaryKey]
    end

    --- Child rows go through the child model's beforeCreate hooks once the
    --- foreign key is set, as create() would.
    ---@param tx OrvexTransaction
    ---@param instance OrvexInstance
    ---@param rel OrvexRelationDef
    ---@param relData any
    ---@return table[] rows the rows queued, for afterBulkCreate
    local function queueChildRows(tx, instance, rel, relData)
        local parentKey = parentKeyOf(instance, rel)
        local rows = {}
        for i, childRow in ipairs(nestedRows(rel, relData)) do
            local child = Helpers.shallowCopy(childRow)
            child[rel.foreignKey] = parentKey
            rows[i] = child
        end
        local childModel = rel.model
        rows = childModel._beforeBulkCreate(rows)
        queueInserts(tx, childModel._tableName, childModel._prepareInsertRows(rows))
        return rows
    end

    --- Related rows need their id for the pivot, so they are created one by
    --- one (and recorded for rollback); the pivot rows are batched.
    ---@param tx OrvexTransaction
    ---@param instance OrvexInstance
    ---@param rel OrvexRelationDef
    ---@param relData table[]
    ---@param created { model: OrvexModel, key: any }[]
    local function queuePivotRows(tx, instance, rel, relData, created)
        local related = rel.model
        local pivotRows = {}
        for i, relatedData in ipairs(relData) do
            local relatedKey = related.create(relatedData)[related._primaryKey]
            created[#created + 1] = { model = related, key = relatedKey }
            pivotRows[i] = {
                [rel.foreignKey] = parentKeyOf(instance, rel),
                [rel.otherKey]   = relatedKey,
            }
        end
        queueInserts(tx, rel.pivot, pivotRows)
    end

    --- Writes every nested row in one transaction, then invalidates the
    --- caches of the tables it touched.
    ---@param instance OrvexInstance
    ---@param nestedData table<string, any>
    ---@param created { model: OrvexModel, key: any }[]
    ---@return { model: OrvexModel, rows: table[] }[] childBatches the hasOne / hasMany rows written
    local function writeNested(instance, nestedData, created)
        local tx = Transaction.new(ctx.adapter)
        local touched, childBatches = {}, {}
        for relName, relData in pairs(nestedData) do
            local rel = relations[relName]
            if rel.type == Relations.BELONGS_TO_MANY then
                queuePivotRows(tx, instance, rel, relData, created)
                touched[#touched + 1] = { cache = ctx.cache, table = rel.pivot }
            elseif rel.type ~= Relations.BELONGS_TO then
                local rows = queueChildRows(tx, instance, rel, relData)
                childBatches[#childBatches + 1] = { model = rel.model, rows = rows }
                touched[#touched + 1] = { cache = rel.model._cache, table = rel.model._tableName }
            end
        end

        assert(tx:commit(), "transaction failed")
        for _, entry in ipairs(touched) do
            entry.cache:invalidateTable(entry.table)
        end
        return childBatches
    end

    --- Creates the row, then its nested hasOne / hasMany / belongsToMany
    --- rows. Nested rows are written with multi-row inserts in a single
    --- transaction; if it fails, the rows created so far are removed and
    --- the error is raised. Not fully atomic: the parent and the related
    --- belongsToMany rows are created before that transaction, so they are
    --- visible to other queries until it commits or they are removed.
    ---@param data table<string, any>
    ---@return OrvexInstance
    function M.createWith(data)
        local mainData, nestedData = splitNestedData(data)
        validateNested(nestedData)

        local instance = M.create(mainData)
        local created = { { model = M, key = instance[primaryKey] } }

        local ok, result = pcall(writeNested, instance, nestedData, created)
        if not ok then
            error(nestedFailureMessage(ctx.tableName, result, removeCreated(created)), 2)
        end
        -- Fired once everything is committed: a failing hook must not
        -- trigger the compensation of rows that are already written.
        for _, batch in ipairs(result) do
            batch.model._afterBulkCreate(batch.rows)
        end
        return instance
    end
end

OrvexModelNested = Nested
return Nested
