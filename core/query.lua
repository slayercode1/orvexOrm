-- core/query.lua
-- Pure SQL query builder. Returns { sql = "...", params = { ... } }.
-- Every function is stateless -- no side-effects, no database calls.

local Helpers = OrvexHelpers or require("utils.helpers")

local assertId = Helpers.assertSafeIdentifier
local quoteId = Helpers.quoteId
local sortedKeys = Helpers.sortedKeys
local placeholders = Helpers.placeholders
local table_concat = table.concat

---@param keys string[]
local function validateKeys(keys)
    for _, k in ipairs(keys) do
        assertId(k)
    end
end

---@param keys string[]
---@return string
local function columnList(keys)
    local quoted = {}
    for i, k in ipairs(keys) do
        quoted[i] = quoteId(k)
    end
    return table_concat(quoted, ", ")
end

--- Builds `` `k` = ? `` for each key and appends the matching values.
---@param keys string[]
---@param values table<string, any>
---@param params any[] appended in place
---@return string[]
local function equalities(keys, values, params)
    local parts = {}
    for i, k in ipairs(keys) do
        parts[i] = quoteId(k) .. " = ?"
        params[#params + 1] = values[k]
    end
    return parts
end

--- Where clauses here are equalities only: every value must be a scalar
--- the driver binds as data. A table (often a client's net-event argument)
--- or an ORM.op marker is refused before any SQL reaches the driver.
---@param method string
---@param keys string[]
---@param where table<string, any>
local function checkWhereValues(method, keys, where)
    for _, k in ipairs(keys) do
        local value = where[k]
        Helpers.ensure(not Helpers.isOp(value),
            ("%s where '%s': only equality is supported here, use Model.query():where() for ORM.op conditions")
                :format(method, k))
        Helpers.ensureBindable(value, ("%s where '%s'"):format(method, k))
    end
end

--- ` WHERE ...`: one equality per key (values appended to `params`),
--- then `col IS NULL` for each of `nullColumns` (the soft delete scope).
---@param keys string[]
---@param where table<string, any>
---@param params any[] appended in place
---@param nullColumns? string[]
---@return string
local function whereClause(keys, where, params, nullColumns)
    local parts = equalities(keys, where, params)
    for _, column in ipairs(nullColumns or {}) do
        assertId(column)
        parts[#parts + 1] = quoteId(column) .. " IS NULL"
    end
    return " WHERE " .. table_concat(parts, " AND ")
end

---@param method string
---@param where table<string, any>
---@return string[] keys
local function whereKeysOf(method, where)
    local keys = sortedKeys(where)
    validateKeys(keys)
    assert(#keys > 0, method .. " requires at least one WHERE condition")
    checkWhereValues(method, keys, where)
    return keys
end

--- Every row of a multi-row INSERT must have the same columns: the column
--- list comes from the first row (see `Query.groupByKeySet`).
---@param rows table[]
---@return string[] keys
local function sharedKeys(rows)
    local keys = sortedKeys(rows[1])
    local signature = table_concat(keys, ",")
    for i = 2, #rows do
        assert(table_concat(sortedKeys(rows[i]), ",") == signature,
            ("insertMany: row %d has a different key set than row 1 (group rows with Query.groupByKeySet)"):format(i))
    end
    return keys
end

---@class OrvexQueryResult
---@field sql string
---@field params any[]

---@class OrvexQuery
local Query = {}

---@param table_name string
---@param data table<string, any>
---@return OrvexQueryResult
function Query.insert(table_name, data)
    assertId(table_name)
    local keys = sortedKeys(data)
    validateKeys(keys)
    local params = {}
    for i, k in ipairs(keys) do
        params[i] = data[k]
    end

    return {
        sql = "INSERT INTO " .. quoteId(table_name) .. " (" .. columnList(keys) .. ") VALUES (" .. placeholders(#keys) .. ")",
        params = params,
    }
end

---@param table_name string
---@param rows table[]
---@return OrvexQueryResult
function Query.insertMany(table_name, rows)
    assertId(table_name)
    assert(#rows > 0, "insertMany requires at least one row")
    local keys = sharedKeys(rows)
    validateKeys(keys)
    local rowPlace = "(" .. placeholders(#keys) .. ")"

    local valueParts = {}
    local params = {}
    local pi = 0
    for ri, row in ipairs(rows) do
        valueParts[ri] = rowPlace
        for _, k in ipairs(keys) do
            pi = pi + 1
            params[pi] = row[k]
        end
    end

    return {
        sql = "INSERT INTO " .. quoteId(table_name) .. " (" .. columnList(keys) .. ") VALUES " .. table_concat(valueParts, ", "),
        params = params,
    }
end

--- Splits `rows` into groups that share the same key set, in first-seen
--- order, so each group is one insertMany that drops no column.
---@param rows table[]
---@return table[][]
function Query.groupByKeySet(rows)
    local groups, bySignature = {}, {}
    for _, row in ipairs(rows) do
        local signature = table_concat(sortedKeys(row), ",")
        local group = bySignature[signature]
        if not group then
            group = {}
            bySignature[signature] = group
            groups[#groups + 1] = group
        end
        group[#group + 1] = row
    end
    return groups
end

---@param limit any
---@return string
local function limitClause(limit)
    if limit == nil then return "" end
    assert(math.type(limit) == "integer" and limit > 0,
        ("select limit must be a positive integer, got '%s'"):format(tostring(limit)))
    return " LIMIT " .. limit
end

---@param table_name string
---@param where table<string, any>
---@param columns? string
---@param limit? integer
---@return OrvexQueryResult
function Query.select(table_name, where, columns, limit)
    assertId(table_name)
    local keys = sortedKeys(where)
    validateKeys(keys)
    checkWhereValues("select", keys, where)

    local sql = "SELECT " .. Helpers.quoteColumnList(columns or "*") .. " FROM " .. quoteId(table_name)
    local params = {}
    if #keys > 0 then
        sql = sql .. " WHERE " .. table_concat(equalities(keys, where, params), " AND ")
    end
    return { sql = sql .. limitClause(limit), params = params }
end

---@param table_name string
---@param data table<string, any>
---@param where table<string, any>
---@param nullColumns? string[] columns that must also be NULL, e.g. { "deleted_at" }
---@return OrvexQueryResult
function Query.update(table_name, data, where, nullColumns)
    assertId(table_name)
    local setKeys   = sortedKeys(data)
    validateKeys(setKeys)
    local whereKeys = whereKeysOf("update", where)

    local params = {}
    local setParts = equalities(setKeys, data, params)

    return {
        sql = "UPDATE " .. quoteId(table_name) .. " SET " .. table_concat(setParts, ", ")
            .. whereClause(whereKeys, where, params, nullColumns),
        params = params,
    }
end

---@param table_name string
---@param where table<string, any>
---@return OrvexQueryResult
function Query.delete(table_name, where)
    assertId(table_name)
    local keys = whereKeysOf("delete", where)

    local params = {}
    local clauses = equalities(keys, where, params)

    return {
        sql = "DELETE FROM " .. quoteId(table_name) .. " WHERE " .. table_concat(clauses, " AND "),
        params = params,
    }
end

--- Clears `deleted_at` on the soft-deleted rows matching `where`.
---@param table_name string
---@param where table<string, any>
---@return OrvexQueryResult
function Query.restore(table_name, where)
    assertId(table_name)
    local keys = whereKeysOf("restore", where)

    local params = {}
    local clauses = equalities(keys, where, params)

    return {
        sql = "UPDATE " .. quoteId(table_name) .. " SET `deleted_at` = NULL WHERE " .. table_concat(clauses, " AND "),
        params = params,
    }
end

---@param table_name string
---@param data table<string, any>
---@param updateFields? table<string, any>
---@return OrvexQueryResult
function Query.upsert(table_name, data, updateFields)
    assertId(table_name)
    local keys = sortedKeys(data)
    validateKeys(keys)
    local params = {}
    for i, k in ipairs(keys) do
        params[i] = data[k]
    end

    local upsertKeys = updateFields and sortedKeys(updateFields) or keys
    if updateFields then validateKeys(upsertKeys) end
    local updates = {}
    for i, k in ipairs(upsertKeys) do
        local column = quoteId(k)
        updates[i] = column .. " = VALUES(" .. column .. ")"
    end

    return {
        sql = "INSERT INTO " .. quoteId(table_name) .. " (" .. columnList(keys) .. ") VALUES (" .. placeholders(#keys)
            .. ") ON DUPLICATE KEY UPDATE " .. table_concat(updates, ", "),
        params = params,
    }
end

---@param relatedTable string
---@param pivotTable string
---@param pivotOtherKey string
---@param relatedPK string
---@param pivotForeignKey string
---@param foreignValue any
---@return OrvexQueryResult
function Query.selectJoin(relatedTable, pivotTable, pivotOtherKey, relatedPK, pivotForeignKey, foreignValue)
    assertId(relatedTable)
    assertId(pivotTable)
    assertId(pivotOtherKey)
    assertId(relatedPK)
    assertId(pivotForeignKey)
    Helpers.ensureBindable(foreignValue, "selectJoin foreign key")
    local related, pivot = quoteId(relatedTable), quoteId(pivotTable)
    return {
        sql = "SELECT " .. related .. ".* FROM " .. related ..
              " INNER JOIN " .. pivot ..
              " ON " .. pivot .. "." .. quoteId(pivotOtherKey) .. " = " .. related .. "." .. quoteId(relatedPK) ..
              " WHERE " .. pivot .. "." .. quoteId(pivotForeignKey) .. " = ?",
        params = { foreignValue },
    }
end

--- Name of the method that applies `op`: Query.increment or Query.decrement.
---@param op "+"|"-"
---@return "increment"|"decrement"
function Query.adjustMethod(op)
    return op == "+" and "increment" or "decrement"
end

---@param table_name string
---@param column string
---@param op "+"|"-"
---@param amount number
---@param where table<string, any>
---@param nullColumns? string[]
---@return OrvexQueryResult
local function buildAdjust(table_name, column, op, amount, where, nullColumns)
    assertId(table_name)
    assertId(column)
    local method = Query.adjustMethod(op)
    Helpers.ensure(Helpers.isFiniteNumber(amount),
        ("%s('%s'): the amount must be a finite number, got %s"):format(method, column, tostring(amount)))
    local whereKeys = whereKeysOf(method, where)
    local params = { amount }
    local target = quoteId(column)
    return {
        sql = "UPDATE " .. quoteId(table_name) .. " SET " .. target .. " = " .. target .. " " .. op .. " ?"
            .. whereClause(whereKeys, where, params, nullColumns),
        params = params,
    }
end

---@param nullColumns? string[] columns that must also be NULL, e.g. { "deleted_at" }
function Query.increment(table_name, column, amount, where, nullColumns)
    return buildAdjust(table_name, column, "+", amount, where, nullColumns)
end

---@param nullColumns? string[] columns that must also be NULL, e.g. { "deleted_at" }
function Query.decrement(table_name, column, amount, where, nullColumns)
    return buildAdjust(table_name, column, "-", amount, where, nullColumns)
end

-- ─── Written tables (cache invalidation) ───────────────────────────

--- `WITH cte AS (...) UPDATE / DELETE / INSERT ...` writes: such a
--- statement cannot be attributed to a table.
---@param upper string
---@return boolean
local function hasWriteVerb(upper)
    for _, verb in ipairs({ "INSERT", "UPDATE", "DELETE", "REPLACE" }) do
        if upper:find("%f[%w]" .. verb .. "%f[%W]") then return true end
    end
    return false
end

local IDENTIFIER = "([%w_$`%.]+)"

--- Single-table write forms, matched against the upper-cased statement.
local WRITE_FORMS = {
    "^INSERT%s+INTO%s+" .. IDENTIFIER,
    "^INSERT%s+IGNORE%s+INTO%s+" .. IDENTIFIER,
    "^REPLACE%s+INTO%s+" .. IDENTIFIER,
    "^DELETE%s+FROM%s+" .. IDENTIFIER,
    "^TRUNCATE%s+TABLE%s+" .. IDENTIFIER,
    "^TRUNCATE%s+" .. IDENTIFIER,
}

---@param identifier string e.g. users, `users`, `db`.`users`
---@return string
local function bareTableName(identifier)
    local name = identifier:gsub("`", "")
    return name:match("([^%.]+)$") or name
end

--- The table of `UPDATE <table> SET`, or nil for a multi-table UPDATE.
---@param upper string
---@param original string
---@return string|nil
local function updatedTable(upper, original)
    local first, last = upper:find("^UPDATE%s+")
    local setAt = upper:find("%sSET%s", last)
    if not first or not setAt then return nil end
    local target = upper:sub(last + 1, setAt - 1)
    if target:find(",", 1, true) or target:find("%f[%w]JOIN%f[%W]") then return nil end
    local identifier = original:sub(last + 1, setAt - 1):match("^" .. IDENTIFIER .. "%s*$")
    return identifier and bareTableName(identifier) or nil
end

---@param upper string
---@return boolean
local function isMultiTableDelete(upper)
    return upper:find("^DELETE") ~= nil
        and (upper:find("%f[%w]JOIN%f[%W]") ~= nil or upper:find("%f[%w]USING%f[%W]") ~= nil)
end

--- Tables a statement may modify, for cache invalidation: an empty list
--- for a read, nil when it cannot tell (DDL, procedures, joins, several
--- statements), in which case callers must flush every cached entry.
---@param sql string
---@return string[]|nil
function Query.writtenTables(sql)
    local statement = sql:gsub("^%s+", ""):gsub("[%s;]+$", "")
    if statement:find(";", 1, true) then return nil end

    local upper = statement:upper()
    local verb = Helpers.sqlVerb(statement)
    if verb == "WITH" then
        return not hasWriteVerb(upper) and {} or nil
    end
    if Helpers.isReadVerb(verb) then return {} end

    local updated = updatedTable(upper, statement)
    if updated then return { updated } end
    if isMultiTableDelete(upper) then return nil end

    for _, form in ipairs(WRITE_FORMS) do
        local start, finish = upper:find(form)
        if start then
            local identifier = statement:sub(start, finish):match(IDENTIFIER .. "$")
            return { bareTableName(identifier) }
        end
    end
    return nil
end

OrvexQuery = Query
return Query
