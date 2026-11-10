-- core/model/crud.lua
-- Class-level reads and writes of a model: create, find, update, delete,
-- upsert, increment and their shortcuts.
--
-- Conventions: misuse (missing where clause, invalid data...) raises an
-- error located at the caller's line. A lookup that finds nothing returns
-- nil (find, first) or an empty list (findAll). update, delete,
-- forceDelete, restore, increment and decrement return the number of rows
-- the driver reports as affected (0: nothing changed); createMany and
-- upsert return true (an INSERT reports its insert id, not a row count).

local Query        = OrvexQuery or require("core.query")
local Serializer   = OrvexSerializer or require("utils.serializer")
local Helpers      = OrvexHelpers or require("utils.helpers")
local CacheLib     = OrvexCache or require("utils.cache")
local MigrationLib = OrvexMigration or require("core.migration")
local Logger       = OrvexLogger or require("utils.logger")
local Hooks        = OrvexModelHooks or require("core.model.hooks")
local Write        = OrvexModelWrite or require("core.model.write")
local Transaction  = OrvexTransaction or require("core.transaction")

local ensure  = Helpers.ensure
local raise   = Helpers.raise
local nowUtc  = Helpers.nowUtc

---@class OrvexModelCrud
local Crud = {}

-- ─── Pure helpers ──────────────────────────────────────────────────

--- Entries of `findOpts.select`: an array, or a comma-separated string
--- like the builder's `select()` takes.
---@param selectOpt string|string[]
---@return string[]
local function selectEntries(selectOpt)
    if type(selectOpt) == "table" then return selectOpt end
    ensure(type(selectOpt) == "string", "findOpts.select must be an array or a comma-separated string")
    local entries = {}
    for entry in selectOpt:gmatch("[^,]+") do
        entries[#entries + 1] = Helpers.trim(entry)
    end
    return entries
end

--- Builds the quoted column list of `findOpts.select`. Entries must be
--- plain identifiers: they often come from callers forwarding client input.
---@param selectOpt? string|string[]
---@param pk string
---@return string
local function buildColumns(selectOpt, pk)
    if not selectOpt then return "*" end
    local cols = {}
    local hasPK = false
    for _, c in ipairs(selectEntries(selectOpt)) do
        Helpers.assertSafeIdentifier(c)
        cols[#cols + 1] = Helpers.quoteId(c)
        if c == pk then hasPK = true end
    end
    if not hasPK then cols[#cols + 1] = Helpers.quoteId(pk) end
    return table.concat(cols, ", ")
end

--- Table values (ORM.op markers) need the query builder, which also
--- refuses plain tables: they are never read as `{ operator, value }`.
---@param where table<string, any>
---@return boolean
local function hasOperatorValues(where)
    for _, v in pairs(where) do
        if type(v) == "table" then return true end
    end
    return false
end

--- findOrCreate / updateOrCreate insert the where as data when nothing
--- matches, so it must hold plain equality values.
---@param where any
---@param method string
local function requireEqualities(where, method)
    ensure(type(where) == "table", method .. "() requires a where table")
    for k, v in pairs(where) do
        ensure(not Helpers.isOp(v),
            ("%s(): where '%s' must be a plain value, not ORM.op (the where is also the created row)")
                :format(method, tostring(k)))
    end
end

--- Class-level writes refuse an empty where: it would hit every row.
---@param where any
---@param method string
local function requireWhere(where, method)
    ensure(type(where) == "table" and next(where) ~= nil, method .. "() requires a where clause")
end

---@param base table<string, any>
---@param extra? table<string, any>
---@return table<string, any> a copy of `base` with `extra` merged in
local function merged(base, extra)
    local out = Helpers.shallowCopy(base)
    if extra then
        for k, v in pairs(extra) do out[k] = v end
    end
    return out
end

---@param where table<string, any>
---@return string `k=v, ...` in key order
local function describeWhere(where)
    local parts = {}
    for _, k in ipairs(Helpers.sortedKeys(where)) do
        parts[#parts + 1] = k .. "=" .. tostring(where[k])
    end
    return table.concat(parts, ", ")
end

-- ─── Writes ────────────────────────────────────────────────────────

---@param M OrvexModel
---@param ctx OrvexInstanceContext
---@param execWrite fun(q: OrvexQueryResult): integer
local function installCreate(M, ctx, execWrite)
    local tableName, schema, hooks = ctx.tableName, ctx.schema, ctx.hooks

    --- Validates and stamps a row about to be inserted. Works on a copy: the
    --- caller's table is often a reused template and must stay untouched.
    ---@param data table<string, any>
    ---@return table row validated copy, with timestamps
    ---@return table encoded row ready to bind
    local function prepareInsert(data)
        local row = Helpers.shallowCopy(data)
        Write.validate(row, schema.allFields)
        if ctx.timestamps then
            local stamp = nowUtc()
            row.created_at = row.created_at or stamp
            row.updated_at = row.updated_at or stamp
        end
        return row, Serializer.encodeRow(row, schema.encodeSet)
    end
    --- Validated, stamped and encoded copies of `rows`, ready for insertMany.
    ---@param rows table[]
    ---@return table[]
    function M._prepareInsertRows(rows)
        local encodedRows = {}
        for i, data in ipairs(rows) do
            local _, encoded = prepareInsert(data)
            encodedRows[i] = encoded
        end
        return encodedRows
    end

    ---@param data table<string, any>
    ---@return OrvexInstance
    function M.create(data)
        Write.refuseManagedColumns(data, schema, "create")
        data = Helpers.shallowCopy(data)
        Hooks.fire(hooks, "beforeCreate", data)

        local row, encoded = prepareInsert(data)
        local q = Query.insert(tableName, encoded)
        Logger.query(q.sql, q.params)
        local insertId = ctx.adapter:scalar(q.sql, q.params)

        if row[ctx.primaryKey] == nil and insertId then
            row[ctx.primaryKey] = insertId
        end

        ctx.cache:invalidateTable(tableName)

        local instance = M._wrapRow(row)
        Hooks.fire(hooks, "afterCreate", instance)
        return instance
    end

    --- Copies of `rows` passed through the beforeCreate hooks, which may
    --- modify them. Shared by createMany and the rows createWith batches.
    ---@param rows table[]
    ---@return table[]
    function M._beforeBulkCreate(rows)
        local copies = {}
        for i, data in ipairs(rows) do
            copies[i] = Helpers.shallowCopy(data)
            Hooks.fire(hooks, "beforeCreate", copies[i])
        end
        return copies
    end

    ---@param rows table[] the rows returned by `_beforeBulkCreate`
    function M._afterBulkCreate(rows)
        Hooks.fire(hooks, "afterBulkCreate", rows)
    end

    --- Rows with different key sets need one INSERT each (an insertMany
    --- takes its columns from its first row); they run in one transaction,
    --- which invalidates the model's cache once it commits.
    ---@param groups table[][] encoded rows grouped by key set
    local function insertGroups(groups)
        if #groups == 1 then
            execWrite(Query.insertMany(tableName, groups[1]))
            return
        end
        local tx = Transaction.new(ctx.adapter, ctx.cache)
        Write.queueInsertGroups(tx, tableName, groups)
        ensure(tx:commit(), ("createMany('%s'): the transaction failed"):format(tableName))
    end

    --- Inserts every row in one multi-row INSERT (one per key set, in a
    --- transaction, when rows have different columns). Fires beforeCreate
    --- on a copy of each row, then afterBulkCreate once (no instance is built).
    ---@param rows table[]
    ---@return boolean
    function M.createMany(rows)
        ensure(type(rows) == "table" and #rows > 0, "createMany requires at least one row")
        for _, row in ipairs(rows) do
            Write.refuseManagedColumns(row, schema, "createMany")
        end
        local copies = M._beforeBulkCreate(rows)
        insertGroups(Query.groupByKeySet(M._prepareInsertRows(copies)))
        M._afterBulkCreate(copies)
        return true
    end

    ---@param data table<string, any>
    ---@return boolean
    function M.upsert(data)
        Write.refuseManagedColumns(data, schema, "upsert")
        data = Helpers.shallowCopy(data)
        Hooks.fire(hooks, "beforeUpsert", data)
        local row, encoded = prepareInsert(data)

        local updateFields
        if ctx.timestamps then
            -- On duplicate rows, keep the original created_at
            updateFields = {}
            for k in pairs(row) do
                if k ~= "created_at" then updateFields[k] = true end
            end
            if next(updateFields) == nil then updateFields = nil end
        end

        execWrite(Query.upsert(tableName, encoded, updateFields))
        Hooks.fire(hooks, "afterUpsert", row)
        return true
    end
end

---@param M OrvexModel
---@param ctx OrvexInstanceContext
---@param execWrite fun(q: OrvexQueryResult): integer
local function installUpdateDelete(M, ctx, execWrite)
    local tableName, schema, hooks = ctx.tableName, ctx.schema, ctx.hooks

    --- Class writes on a soft delete model leave trashed rows alone. An
    --- explicit `deleted_at` condition targets them on purpose, as in find.
    ---@param where table<string, any>
    ---@return string[]|nil nullColumns
    local function liveRowsOnly(where)
        if ctx.softDelete and where.deleted_at == nil then return { "deleted_at" } end
        return nil
    end

    --- Argument order: data first, as in `Instance:update(data)`.
    --- `updateWhere(where, data)` is the where-first alias; both are kept
    --- for backward compatibility.
    ---@param data table<string, any>
    ---@param where table<string, any>
    ---@return integer affected rows the driver reports changed (0: none)
    function M.update(data, where)
        requireWhere(where, "update")
        Write.refuseManagedColumns(data, schema, "update")

        data = Helpers.shallowCopy(data)
        Hooks.fire(hooks, "beforeBulkUpdate", data, where)
        Write.validate(data, schema.allFields)

        if ctx.timestamps then
            data.updated_at = data.updated_at or nowUtc()
        end

        local encoded = Serializer.encodeRow(data, schema.encodeSet)
        local affected = execWrite(Query.update(tableName, encoded, where, liveRowsOnly(where)))
        Hooks.fire(hooks, "afterBulkUpdate", data, where, affected)
        return affected
    end

    ---@param where table<string, any>
    ---@param q OrvexQueryResult
    ---@return integer affected
    local function bulkDelete(where, q)
        Hooks.fire(hooks, "beforeBulkDelete", where)
        local affected = execWrite(q)
        Hooks.fire(hooks, "afterBulkDelete", where, affected)
        return affected
    end

    --- Soft-deletes (sets deleted_at) when the model uses soft delete.
    ---@param where table<string, any>
    ---@return integer affected
    function M.delete(where)
        requireWhere(where, "delete")
        if ctx.softDelete then
            return bulkDelete(where, Query.update(tableName, { deleted_at = nowUtc() }, where, liveRowsOnly(where)))
        end
        return bulkDelete(where, Query.delete(tableName, where))
    end

    ---@param where table<string, any>
    ---@return integer affected
    function M.forceDelete(where)
        requireWhere(where, "forceDelete")
        return bulkDelete(where, Query.delete(tableName, where))
    end

    ---@param where table<string, any>
    ---@return integer affected
    function M.restore(where)
        ensure(ctx.softDelete, "restore() requires soft delete to be enabled")
        requireWhere(where, "restore")
        return execWrite(Query.restore(tableName, where))
    end

    ---@param method "increment"|"decrement"
    ---@return integer affected
    local function classAdjust(column, amount, where, method)
        requireWhere(where, method)
        return execWrite(Query[method](tableName, column, amount, where, liveRowsOnly(where)))
    end

    --- The amount is required here, unlike `Instance:increment(column, amount?)`
    --- where it defaults to 1.
    ---@param column string
    ---@param amount number
    ---@param where table<string, any>
    ---@return integer affected
    function M.increment(column, amount, where)
        return classAdjust(column, amount, where, "increment")
    end

    ---@param column string
    ---@param amount number
    ---@param where table<string, any>
    ---@return integer affected
    function M.decrement(column, amount, where)
        return classAdjust(column, amount, where, "decrement")
    end

    --- Where-first alias of `update(data, where)`; note the swapped order.
    ---@param where table<string, any>
    ---@param data table<string, any>
    ---@return integer affected
    function M.updateWhere(where, data)
        return M.update(data, where)
    end

    ---@param where table<string, any>
    ---@return integer affected
    function M.deleteWhere(where)
        return M.delete(where)
    end
end

-- ─── Reads ─────────────────────────────────────────────────────────

---@param M OrvexModel
---@param ctx OrvexInstanceContext
local function installFind(M, ctx)
    local tableName, primaryKey, cache = ctx.tableName, ctx.primaryKey, ctx.cache

    --- Operator values and soft delete filtering need the query builder;
    --- plain equality lookups take the prebuilt, cached fast path.
    ---@param where table<string, any>
    ---@return boolean
    local function needsBuilder(where)
        return ctx.softDelete or hasOperatorValues(where)
    end

    --- An explicit `deleted_at` condition means the caller is looking at
    --- trashed rows on purpose, so the soft delete filter is not added.
    ---@param where table<string, any>
    ---@param columns string
    ---@return OrvexBuilder
    local function builderFor(where, columns)
        local b = where.deleted_at == nil and M.query() or M.withTrashed()
        if columns ~= "*" then b:select(columns) end
        if next(where) then b:where(where) end
        return b
    end

    ---@param where table<string, any>
    ---@param columns string
    ---@param limit? integer
    ---@return table[] rows
    ---@return boolean shared true when the rows live in the cache
    local function selectRows(where, columns, limit)
        local q = Query.select(tableName, where, columns, limit)

        local cacheKey = CacheLib.makeKey(q.sql, q.params)
        local cached, hit = cache:get(cacheKey)
        if hit then return cached or {}, true end

        Logger.query(q.sql, q.params)
        local rows = ctx.adapter:execute(q.sql, q.params) or {}
        cache:set(cacheKey, rows)
        return rows, cache:isEnabled()
    end

    --- Wraps copies of shared rows: wrapping decodes JSON and attaches a
    --- metatable in place, which would corrupt the cached rows.
    ---@param rows table[]
    ---@param shared boolean
    ---@return OrvexInstance[]
    local function wrapRows(rows, shared)
        local results = {}
        for i, row in ipairs(rows) do
            results[i] = M._wrapRow(shared and Helpers.shallowCopy(row) or row)
        end
        return results
    end

    ---@param where? table<string, any> omitted: the first row
    ---@param findOpts? { select?: string[], include?: string[] }
    ---@return OrvexInstance|nil
    function M.find(where, findOpts)
        where = where or {}
        findOpts = findOpts or {}
        local columns = buildColumns(findOpts.select, primaryKey)

        local instance
        if needsBuilder(where) then
            instance = builderFor(where, columns):first()
        else
            instance = wrapRows(selectRows(where, columns, 1))[1]
        end

        if instance and findOpts.include then
            M._eagerLoad(instance, findOpts.include)
        end
        return instance
    end

    --- `findOpts.select` takes an array of column names, whereas the query
    --- builder's `:select()` takes a comma-separated string.
    ---@param where? table<string, any> omitted: every row
    ---@param findOpts? { select?: string[], include?: string[] }
    ---@return OrvexInstance[]
    function M.findAll(where, findOpts)
        where = where or {}
        findOpts = findOpts or {}
        local columns = buildColumns(findOpts.select, primaryKey)

        local results
        if needsBuilder(where) then
            results = builderFor(where, columns):get()
        else
            results = wrapRows(selectRows(where, columns))
        end

        if findOpts.include and #results > 0 then
            M._eagerLoadMany(results, findOpts.include)
        end
        return results
    end

    ---@param findOpts? { select?: string[], include?: string[] }
    ---@return OrvexInstance[]
    function M.all(findOpts)
        return M.findAll({}, findOpts)
    end

    ---@param where table<string, any>
    ---@param findOpts? { select?: string[], include?: string[] }
    ---@return OrvexInstance
    function M.findOrFail(where, findOpts)
        where = where or {}
        local result = M.find(where, findOpts)
        if not result then
            raise(("Record not found in '%s' where %s"):format(tableName, describeWhere(where)))
        end
        return result
    end

    ---@param where table<string, any>
    ---@param defaults? table<string, any>
    ---@return OrvexInstance instance
    ---@return boolean created
    function M.findOrCreate(where, defaults)
        requireEqualities(where, "findOrCreate")
        local existing = M.find(where)
        if existing then
            return existing, false
        end
        return M.create(merged(where, defaults)), true
    end

    ---@param where table<string, any>
    ---@param data table<string, any>
    ---@return OrvexInstance instance
    ---@return boolean created
    function M.updateOrCreate(where, data)
        requireEqualities(where, "updateOrCreate")
        local existing = M.find(where)
        if existing then
            existing:update(data)
            return existing, false
        end
        return M.create(merged(where, data)), true
    end
end

--- Installs the CRUD methods on a model class.
---@param M OrvexModel
---@param ctx OrvexInstanceContext
function Crud.install(M, ctx)
    ---@param q OrvexQueryResult
    ---@return integer affected
    local function execWrite(q)
        return Write.run(ctx.adapter, ctx.cache, ctx.tableName, q)
    end

    installCreate(M, ctx, execWrite)
    installFind(M, ctx)
    installUpdateDelete(M, ctx, execWrite)

    function M.flushCache()
        ctx.cache:invalidateTable(ctx.tableName)
    end

    --- Automatically adds created_at/updated_at when timestamps=true
    --- and deleted_at when softDelete=true.
    function M.sync()
        MigrationLib.sync(ctx.tableName, ctx.schema.allFields, ctx.primaryKey, ctx.adapter)
    end
end

OrvexModelCrud = Crud
return Crud
