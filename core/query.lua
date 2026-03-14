-- core/query.lua
-- Pure SQL query builder.  Returns { sql = "...", params = { ... } }.
-- Every function is stateless — no side-effects, no database calls.
-- Performance-optimized: cached placeholders, reduced allocations.

local Helpers = OrvexHelpers or require("utils.helpers")

local assertId = Helpers.assertSafeIdentifier
local sortedKeys = Helpers.sortedKeys
local placeholders = Helpers.placeholders
local table_concat = table.concat

--- Validate all keys in a table as safe SQL identifiers.
---@param keys string[]
local function validateKeys(keys)
    for _, k in ipairs(keys) do
        assertId(k)
    end
end

---@class OrvexQueryResult
---@field sql string
---@field params any[]

---@class OrvexQuery
local Query = {}

--- Build an INSERT query.
---@param table_name string
---@param data table<string, any>
---@return OrvexQueryResult
function Query.insert(table_name, data)
    assertId(table_name)
    local keys = sortedKeys(data)
    validateKeys(keys)
    local n = #keys
    local cols   = table_concat(keys, ", ")
    local places = placeholders(n)

    local params = {}
    for i, k in ipairs(keys) do
        params[i] = data[k]
    end

    return {
        sql = "INSERT INTO `" .. table_name .. "` (" .. cols .. ") VALUES (" .. places .. ")",
        params = params,
    }
end

--- Build a batch INSERT query (multiple rows).
---@param table_name string
---@param rows table[]
---@return OrvexQueryResult
function Query.insertMany(table_name, rows)
    assertId(table_name)
    assert(#rows > 0, "insertMany requires at least one row")
    local keys = sortedKeys(rows[1])
    validateKeys(keys)
    local n = #keys
    local cols = table_concat(keys, ", ")
    local rowPlace = "(" .. placeholders(n) .. ")"

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
        sql = "INSERT INTO `" .. table_name .. "` (" .. cols .. ") VALUES " .. table_concat(valueParts, ", "),
        params = params,
    }
end

--- Build a SELECT query.
---@param table_name string
---@param where table<string, any>
---@param columns? string
---@return OrvexQueryResult
function Query.select(table_name, where, columns)
    assertId(table_name)
    columns = columns or "*"
    local keys = sortedKeys(where)
    validateKeys(keys)

    if #keys == 0 then
        return { sql = "SELECT " .. columns .. " FROM `" .. table_name .. "`", params = {} }
    end

    local clauses = {}
    local params = {}
    for i, k in ipairs(keys) do
        clauses[i] = k .. " = ?"
        params[i]  = where[k]
    end

    return {
        sql = "SELECT " .. columns .. " FROM `" .. table_name .. "` WHERE " .. table_concat(clauses, " AND "),
        params = params,
    }
end

--- Build an UPDATE query.
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

    local setParts = {}
    local params = {}
    local pi = 0
    for i, k in ipairs(setKeys) do
        setParts[i] = k .. " = ?"
        pi = pi + 1
        params[pi] = data[k]
    end

    local whereParts = {}
    for i, k in ipairs(whereKeys) do
        whereParts[i] = k .. " = ?"
        pi = pi + 1
        params[pi] = where[k]
    end

    return {
        sql = "UPDATE `" .. table_name .. "` SET " .. table_concat(setParts, ", ") .. " WHERE " .. table_concat(whereParts, " AND "),
        params = params,
    }
end

--- Build a DELETE query.
---@param table_name string
---@param where table<string, any>
---@return OrvexQueryResult
function Query.delete(table_name, where)
    assertId(table_name)
    local keys = sortedKeys(where)
    validateKeys(keys)
    assert(#keys > 0, "delete requires at least one WHERE condition")

    local clauses = {}
    local params = {}
    for i, k in ipairs(keys) do
        clauses[i] = k .. " = ?"
        params[i]  = where[k]
    end

    return {
        sql = "DELETE FROM `" .. table_name .. "` WHERE " .. table_concat(clauses, " AND "),
        params = params,
    }
end

--- Build an UPSERT query.
---@param table_name string
---@param data table<string, any>
---@param updateFields? table<string, any>
---@return OrvexQueryResult
function Query.upsert(table_name, data, updateFields)
    assertId(table_name)
    local keys = sortedKeys(data)
    validateKeys(keys)
    local n = #keys
    local cols   = table_concat(keys, ", ")
    local places = placeholders(n)

    local params = {}
    for i, k in ipairs(keys) do
        params[i] = data[k]
    end

    local upsertKeys = updateFields and sortedKeys(updateFields) or keys
    if updateFields then validateKeys(upsertKeys) end
    local updates = {}
    for i, k in ipairs(upsertKeys) do
        updates[i] = k .. " = VALUES(" .. k .. ")"
    end

    return {
        sql = "INSERT INTO `" .. table_name .. "` (" .. cols .. ") VALUES (" .. places .. ") ON DUPLICATE KEY UPDATE " .. table_concat(updates, ", "),
        params = params,
    }
end

--- Build a SELECT with INNER JOIN (belongsToMany pivot).
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
    return {
        sql = "SELECT " .. relatedTable .. ".* FROM " .. relatedTable ..
              " INNER JOIN " .. pivotTable ..
              " ON " .. pivotTable .. "." .. pivotOtherKey .. " = " .. relatedTable .. "." .. relatedPK ..
              " WHERE " .. pivotTable .. "." .. pivotForeignKey .. " = ?",
        params = { foreignValue },
    }
end

--- Build an INCREMENT or DECREMENT query.
---@param table_name string
---@param column string
---@param op string  "+" or "-"
---@param amount number
---@param where table<string, any>
---@return OrvexQueryResult
local function buildAdjust(table_name, column, op, amount, where)
    assertId(table_name)
    assertId(column)
    local whereKeys = sortedKeys(where)
    validateKeys(whereKeys)
    local params = { amount }
    local whereParts = {}
    for i, k in ipairs(whereKeys) do
        whereParts[i] = k .. " = ?"
        params[i + 1] = where[k]
    end
    return {
        sql = "UPDATE `" .. table_name .. "` SET " .. column .. " = " .. column .. " " .. op .. " ? WHERE " .. table_concat(whereParts, " AND "),
        params = params,
    }
end

function Query.increment(table_name, column, amount, where)
    return buildAdjust(table_name, column, "+", amount, where)
end

function Query.decrement(table_name, column, amount, where)
    return buildAdjust(table_name, column, "-", amount, where)
end

OrvexQuery = Query
return Query
