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
    local keys = sortedKeys(rows[1])
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
---@return OrvexQueryResult
function Query.update(table_name, data, where)
    assertId(table_name)
    local setKeys   = sortedKeys(data)
    local whereKeys = sortedKeys(where)
    validateKeys(setKeys)
    validateKeys(whereKeys)

    local params = {}
    local setParts = equalities(setKeys, data, params)
    local whereParts = equalities(whereKeys, where, params)

    return {
        sql = "UPDATE " .. quoteId(table_name) .. " SET " .. table_concat(setParts, ", ") .. " WHERE " .. table_concat(whereParts, " AND "),
        params = params,
    }
end

---@param table_name string
---@param where table<string, any>
---@return OrvexQueryResult
function Query.delete(table_name, where)
    assertId(table_name)
    local keys = sortedKeys(where)
    validateKeys(keys)
    assert(#keys > 0, "delete requires at least one WHERE condition")

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
    local keys = sortedKeys(where)
    validateKeys(keys)
    assert(#keys > 0, "restore requires at least one WHERE condition")

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
    local related, pivot = quoteId(relatedTable), quoteId(pivotTable)
    return {
        sql = "SELECT " .. related .. ".* FROM " .. related ..
              " INNER JOIN " .. pivot ..
              " ON " .. pivot .. "." .. quoteId(pivotOtherKey) .. " = " .. related .. "." .. quoteId(relatedPK) ..
              " WHERE " .. pivot .. "." .. quoteId(pivotForeignKey) .. " = ?",
        params = { foreignValue },
    }
end

---@param table_name string
---@param column string
---@param op string
---@param amount number
---@param where table<string, any>
---@return OrvexQueryResult
local function buildAdjust(table_name, column, op, amount, where)
    assertId(table_name)
    assertId(column)
    local whereKeys = sortedKeys(where)
    validateKeys(whereKeys)
    local params = { amount }
    local whereParts = equalities(whereKeys, where, params)
    local target = quoteId(column)
    return {
        sql = "UPDATE " .. quoteId(table_name) .. " SET " .. target .. " = " .. target .. " " .. op .. " ? WHERE " .. table_concat(whereParts, " AND "),
        params = params,
    }
end

function Query.increment(table_name, column, amount, where)
    return buildAdjust(table_name, column, "+", amount, where)
end

function Query.decrement(table_name, column, amount, where)
    return buildAdjust(table_name, column, "-", amount, where)
end

-- ─── Written tables (cache invalidation) ───────────────────────────

local READ_VERBS = { SELECT = true, SHOW = true, DESCRIBE = true, DESC = true, EXPLAIN = true }

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
    if READ_VERBS[upper:match("^(%a+)")] then return {} end

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
