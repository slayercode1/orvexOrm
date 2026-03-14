-- core/builder.lua
-- Chainable query builder.

local Helpers   = OrvexHelpers or require("utils.helpers")
local CacheLib  = OrvexCache or require("utils.cache")

local assertId = Helpers.assertSafeIdentifier
local assertOp = Helpers.assertValidOperator

---@alias OrvexWhereOperator "="|"!="|">"|"<"|">="|"<="|"LIKE"|"NOT LIKE"|"IN"|"NOT IN"|"BETWEEN"|"IS"|"IS NOT"

---@class OrvexWhereValue
---@field [1] OrvexWhereOperator  Operator
---@field [2] any                  Value (or table for IN/BETWEEN)

---@class OrvexWhereEntry
---@field clause string
---@field params any[]
---@field or_flag? boolean

---@class OrvexBuilder
---@field private _table string
---@field private _adapter OrvexAdapter
---@field private _wrapFn? fun(row: table): OrvexInstance
---@field private _selects string
---@field private _distinct boolean
---@field private _wheres OrvexWhereEntry[]
---@field private _joins string[]
---@field private _groupBy? string
---@field private _having? string
---@field private _havingParams any[]
---@field private _orderBy? string
---@field private _limit? integer
---@field private _offset? integer
---@field private _cache? OrvexCache
local Builder = {}
Builder.__index = Builder

--- Create a new query builder for a table.
---@param tableName string
---@param adapter OrvexAdapter
---@param wrapFn? fun(row: table): OrvexInstance
---@param cache? OrvexCache
---@return OrvexBuilder
function Builder.new(tableName, adapter, wrapFn, cache)
    local self = setmetatable({}, Builder)
    self._table     = tableName
    self._adapter   = adapter
    self._wrapFn    = wrapFn
    self._selects   = "*"
    self._distinct  = false
    self._wheres    = {}
    self._joins     = {}
    self._groupBy   = nil
    self._having    = nil
    self._havingParams = {}
    self._orderBy   = nil
    self._limit     = nil
    self._offset    = nil
    self._cache     = cache
    return self
end

-- ─── Internal: parse a single where condition ─────────────────────

--- Parse a single key/value pair into a where entry.
---@param k string
---@param v any
---@param orFlag? boolean
---@return OrvexWhereEntry
local function parseWhereEntry(k, v, orFlag)
    assertId(k)
    if type(v) == "table" then
        local op  = v[1]:upper()
        local val = v[2]
        assertOp(op)

        if op == "IN" or op == "NOT IN" then
            assert(type(val) == "table" and #val > 0, op .. " requires a non-empty array")
            local places = string.rep("?, ", #val):sub(1, -3)
            return {
                clause = k .. " " .. op .. " (" .. places .. ")",
                params = val,
                or_flag = orFlag,
            }
        elseif op == "BETWEEN" then
            assert(type(val) == "table" and #val == 2, "BETWEEN requires a table with 2 values")
            return {
                clause = k .. " BETWEEN ? AND ?",
                params = { val[1], val[2] },
                or_flag = orFlag,
            }
        elseif op == "IS" or op == "IS NOT" then
            assert(val == "NULL", "IS/IS NOT only supports NULL")
            return {
                clause = k .. " " .. op .. " NULL",
                params = {},
                or_flag = orFlag,
            }
        else
            return {
                clause = k .. " " .. op .. " ?",
                params = { val },
                or_flag = orFlag,
            }
        end
    else
        return {
            clause = k .. " = ?",
            params = { v },
            or_flag = orFlag,
        }
    end
end

-- ─── Chainable methods ─────────────────────────────────────────────

--- Set the columns to select.
---@param columns string  e.g. "users.*, profiles.bio"
---@return OrvexBuilder
function Builder:select(columns)
    self._selects = columns
    return self
end

--- Enable DISTINCT on the query.
---@return OrvexBuilder
function Builder:distinct()
    self._distinct = true
    return self
end

--- Add a WHERE condition.
---@param field string|table<string, any|OrvexWhereValue>
---@param operator? OrvexWhereOperator|any
---@param value? any
---@return OrvexBuilder
function Builder:where(field, operator, value)
    if type(field) == "string" and operator ~= nil and value ~= nil then
        assertId(field)
        assertOp(operator)
        self._wheres[#self._wheres + 1] = {
            clause = field .. " " .. operator .. " ?",
            params = { value },
        }
        return self
    end

    -- Shortcut: :where("field", value) → implicit "="
    if type(field) == "string" and operator ~= nil and value == nil then
        assertId(field)
        self._wheres[#self._wheres + 1] = {
            clause = field .. " = ?",
            params = { operator },
        }
        return self
    end

    if type(field) == "table" then
        local keys = Helpers.sortedKeys(field)
        for _, k in ipairs(keys) do
            self._wheres[#self._wheres + 1] = parseWhereEntry(k, field[k])
        end
        return self
    end

    error("Invalid where() arguments")
end

--- Add an OR WHERE condition.
---@param field string|table<string, any|OrvexWhereValue>
---@param operator? OrvexWhereOperator|any
---@param value? any
---@return OrvexBuilder
function Builder:orWhere(field, operator, value)
    if type(field) == "string" and operator ~= nil and value ~= nil then
        assertId(field)
        assertOp(operator)
        self._wheres[#self._wheres + 1] = {
            clause = field .. " " .. operator .. " ?",
            params = { value },
            or_flag = true,
        }
        return self
    end

    -- Shortcut: :orWhere("field", value) → implicit "="
    if type(field) == "string" and operator ~= nil and value == nil then
        assertId(field)
        self._wheres[#self._wheres + 1] = {
            clause = field .. " = ?",
            params = { operator },
            or_flag = true,
        }
        return self
    end

    if type(field) == "table" then
        local keys = Helpers.sortedKeys(field)
        for _, k in ipairs(keys) do
            self._wheres[#self._wheres + 1] = parseWhereEntry(k, field[k], true)
        end
        return self
    end

    return self
end

--- Add a WHERE IN condition. Accepts an array of values OR a subquery string.
---@param column string
---@param valuesOrSQL string|any[]  Array of values or raw SQL subquery
---@param subParams? any[]          Only used when valuesOrSQL is a subquery string
---@return OrvexBuilder
function Builder:whereIn(column, valuesOrSQL, subParams)
    assertId(column)
    if type(valuesOrSQL) == "table" then
        assert(#valuesOrSQL > 0, "whereIn requires a non-empty array")
        local places = Helpers.placeholders(#valuesOrSQL)
        self._wheres[#self._wheres + 1] = {
            clause = column .. " IN (" .. places .. ")",
            params = valuesOrSQL,
        }
    else
        self._wheres[#self._wheres + 1] = {
            clause = column .. " IN (" .. valuesOrSQL .. ")",
            params = subParams or {},
        }
    end
    return self
end

--- Add a WHERE NOT IN condition. Accepts an array of values OR a subquery string.
---@param column string
---@param valuesOrSQL string|any[]
---@param subParams? any[]
---@return OrvexBuilder
function Builder:whereNotIn(column, valuesOrSQL, subParams)
    assertId(column)
    if type(valuesOrSQL) == "table" then
        assert(#valuesOrSQL > 0, "whereNotIn requires a non-empty array")
        local places = Helpers.placeholders(#valuesOrSQL)
        self._wheres[#self._wheres + 1] = {
            clause = column .. " NOT IN (" .. places .. ")",
            params = valuesOrSQL,
        }
    else
        self._wheres[#self._wheres + 1] = {
            clause = column .. " NOT IN (" .. valuesOrSQL .. ")",
            params = subParams or {},
        }
    end
    return self
end

--- Shortcut: WHERE column BETWEEN min AND max.
---@param column string
---@param min any
---@param max any
---@return OrvexBuilder
function Builder:whereBetween(column, min, max)
    assertId(column)
    self._wheres[#self._wheres + 1] = {
        clause = column .. " BETWEEN ? AND ?",
        params = { min, max },
    }
    return self
end

--- Shortcut: WHERE column NOT BETWEEN min AND max.
---@param column string
---@param min any
---@param max any
---@return OrvexBuilder
function Builder:whereNotBetween(column, min, max)
    assertId(column)
    self._wheres[#self._wheres + 1] = {
        clause = column .. " NOT BETWEEN ? AND ?",
        params = { min, max },
    }
    return self
end

--- Shortcut: WHERE column LIKE pattern.
---@param column string
---@param pattern string
---@return OrvexBuilder
function Builder:whereLike(column, pattern)
    assertId(column)
    self._wheres[#self._wheres + 1] = {
        clause = column .. " LIKE ?",
        params = { pattern },
    }
    return self
end

--- Add a WHERE NULL condition.
---@param column string
---@return OrvexBuilder
function Builder:whereNull(column)
    assertId(column)
    self._wheres[#self._wheres + 1] = {
        clause = column .. " IS NULL",
        params = {},
    }
    return self
end

--- Add a WHERE NOT NULL condition.
---@param column string
---@return OrvexBuilder
function Builder:whereNotNull(column)
    assertId(column)
    self._wheres[#self._wheres + 1] = {
        clause = column .. " IS NOT NULL",
        params = {},
    }
    return self
end

--- Add a LEFT JOIN clause.
---@param joinTable string
---@param col1 string
---@param col2 string
---@return OrvexBuilder
function Builder:leftJoin(joinTable, col1, col2)
    assertId(joinTable)
    assertId(col1)
    assertId(col2)
    self._joins[#self._joins + 1] = (
        "LEFT JOIN %s ON %s = %s"
    ):format(joinTable, col1, col2)
    return self
end

--- Add an INNER JOIN clause.
---@param joinTable string
---@param col1 string
---@param col2 string
---@return OrvexBuilder
function Builder:innerJoin(joinTable, col1, col2)
    assertId(joinTable)
    assertId(col1)
    assertId(col2)
    self._joins[#self._joins + 1] = (
        "INNER JOIN %s ON %s = %s"
    ):format(joinTable, col1, col2)
    return self
end

--- Add a RIGHT JOIN clause.
---@param joinTable string
---@param col1 string
---@param col2 string
---@return OrvexBuilder
function Builder:rightJoin(joinTable, col1, col2)
    assertId(joinTable)
    assertId(col1)
    assertId(col2)
    self._joins[#self._joins + 1] = (
        "RIGHT JOIN %s ON %s = %s"
    ):format(joinTable, col1, col2)
    return self
end

--- Set GROUP BY clause.
---@param columns string
---@return OrvexBuilder
function Builder:groupBy(columns)
    self._groupBy = columns
    return self
end

--- Set HAVING clause.
---@param clause string
---@param ... any
---@return OrvexBuilder
function Builder:having(clause, ...)
    self._having = clause
    self._havingParams = { ... }
    return self
end

--- Set ORDER BY clause.
---@param column string
---@param direction? "ASC"|"DESC"
---@return OrvexBuilder
function Builder:orderBy(column, direction)
    assertId(column)
    direction = direction or "ASC"
    assert(direction == "ASC" or direction == "DESC", "orderBy direction must be ASC or DESC")
    self._orderBy = column .. " " .. direction
    return self
end

--- Shortcut: ORDER BY column DESC.
---@param column string
---@return OrvexBuilder
function Builder:orderByDesc(column)
    assertId(column)
    self._orderBy = column .. " DESC"
    return self
end

--- Shortcut: ORDER BY column ASC.
---@param column string
---@return OrvexBuilder
function Builder:orderByAsc(column)
    assertId(column)
    self._orderBy = column .. " ASC"
    return self
end

--- Shortcut: ORDER BY created_at DESC (most recent first).
---@param column? string  Default "created_at"
---@return OrvexBuilder
function Builder:latest(column)
    column = column or "created_at"
    assertId(column)
    self._orderBy = column .. " DESC"
    return self
end

--- Shortcut: ORDER BY created_at ASC (oldest first).
---@param column? string  Default "created_at"
---@return OrvexBuilder
function Builder:oldest(column)
    column = column or "created_at"
    assertId(column)
    self._orderBy = column .. " ASC"
    return self
end

--- Set LIMIT.
---@param n integer
---@return OrvexBuilder
function Builder:limit(n)
    self._limit = n
    return self
end

--- Set OFFSET.
---@param n integer
---@return OrvexBuilder
function Builder:offset(n)
    self._offset = n
    return self
end

--- Cursor-based pagination: fetch rows after a given cursor value.
---@param column string
---@param value any
---@param direction? "ASC"|"DESC"
---@return OrvexBuilder
function Builder:after(column, value, direction)
    assertId(column)
    direction = direction or "ASC"
    local op = direction == "DESC" and "<" or ">"
    self._wheres[#self._wheres + 1] = {
        clause = column .. " " .. op .. " ?",
        params = { value },
    }
    self._orderBy = column .. " " .. direction
    return self
end

--- Cursor-based pagination: fetch rows before a given cursor value.
---@param column string
---@param value any
---@param direction? "ASC"|"DESC"
---@return OrvexBuilder
function Builder:before(column, value, direction)
    assertId(column)
    direction = direction or "ASC"
    local op = direction == "DESC" and ">" or "<"
    self._wheres[#self._wheres + 1] = {
        clause = column .. " " .. op .. " ?",
        params = { value },
    }
    self._orderBy = column .. " " .. direction
    return self
end

-- ─── SQL assembly ──────────────────────────────────────────────────

---@private
---@return string clause
---@return any[] params
function Builder:_buildWhere()
    if #self._wheres == 0 then
        return "", {}
    end

    local parts  = {}
    local params = {}

    for i, w in ipairs(self._wheres) do
        local connector = w.or_flag and "OR" or "AND"

        if i == 1 then
            parts[1] = w.clause
        else
            parts[#parts + 1] = connector .. " " .. w.clause
        end

        for _, p in ipairs(w.params) do
            params[#params + 1] = p
        end
    end

    return " WHERE " .. table.concat(parts, " "), params
end

---@private
---@param selectExpr? string
---@return string sql
---@return any[] params
function Builder:_buildSQL(selectExpr)
    selectExpr = selectExpr or self._selects

    local keyword = self._distinct and "SELECT DISTINCT " or "SELECT "
    local parts = { keyword .. selectExpr .. " FROM " .. self._table }

    for _, j in ipairs(self._joins) do
        parts[#parts + 1] = j
    end

    local whereSQL, params = self:_buildWhere()
    if whereSQL ~= "" then
        parts[#parts + 1] = whereSQL
    end

    if self._groupBy then
        parts[#parts + 1] = "GROUP BY " .. self._groupBy
    end

    if self._having then
        parts[#parts + 1] = "HAVING " .. self._having
        for _, p in ipairs(self._havingParams) do
            params[#params + 1] = p
        end
    end

    if self._orderBy then
        parts[#parts + 1] = "ORDER BY " .. self._orderBy
    end

    if self._limit then
        parts[#parts + 1] = "LIMIT " .. self._limit
    end
    if self._offset then
        parts[#parts + 1] = "OFFSET " .. self._offset
    end

    return table.concat(parts, " "), params
end

-- ─── Terminal methods ──────────────────────────────────────────────

---@private
function Builder:_cachedExecute(sql, params)
    if self._cache then
        local cacheKey = CacheLib.makeKey(sql, params)
        local cached, hit = self._cache:get(cacheKey)
        if hit then
            return cached or {}
        end

        local rows = self._adapter:execute(sql, params)
        self._cache:set(cacheKey, rows)
        return rows or {}
    end

    return self._adapter:execute(sql, params) or {}
end

--- Execute and return all matching rows as instances.
---@return OrvexInstance[]
function Builder:get()
    local sql, params = self:_buildSQL()
    local rows = self:_cachedExecute(sql, params)

    if self._wrapFn then
        local results = {}
        for i, row in ipairs(rows) do
            results[i] = self._wrapFn(row)
        end
        return results
    end

    return rows
end

--- Execute and return the first matching row, or nil.
---@return OrvexInstance|nil
function Builder:first()
    self._limit = 1
    local results = self:get()
    return results[1] or nil
end

--- Execute a COUNT(*) query.
---@return integer
function Builder:count()
    local sql, params = self:_buildSQL("COUNT(*) as cnt")
    local rows = self:_cachedExecute(sql, params)
    if rows[1] then return rows[1].cnt or 0 end
    return 0
end

--- Execute a SUM query.
---@param column string
---@return number
function Builder:sum(column)
    assertId(column)
    local sql, params = self:_buildSQL(("SUM(%s) as val"):format(column))
    local rows = self:_cachedExecute(sql, params)
    if rows[1] then return rows[1].val or 0 end
    return 0
end

--- Execute an AVG query.
---@param column string
---@return number
function Builder:avg(column)
    assertId(column)
    local sql, params = self:_buildSQL(("AVG(%s) as val"):format(column))
    local rows = self:_cachedExecute(sql, params)
    if rows[1] then return rows[1].val or 0 end
    return 0
end

--- Execute a MIN query.
---@param column string
---@return any
function Builder:min(column)
    assertId(column)
    local sql, params = self:_buildSQL(("MIN(%s) as val"):format(column))
    local rows = self:_cachedExecute(sql, params)
    if rows[1] then return rows[1].val end
    return nil
end

--- Execute a MAX query.
---@param column string
---@return any
function Builder:max(column)
    assertId(column)
    local sql, params = self:_buildSQL(("MAX(%s) as val"):format(column))
    local rows = self:_cachedExecute(sql, params)
    if rows[1] then return rows[1].val end
    return nil
end

--- Return an array of values for a single column.
---@param column string
---@return any[]
function Builder:pluck(column)
    assertId(column)
    local oldSelects = self._selects
    self._selects = column
    local sql, params = self:_buildSQL()
    local rows = self:_cachedExecute(sql, params)
    self._selects = oldSelects

    local values = {}
    for i, row in ipairs(rows) do
        values[i] = row[column]
    end
    return values
end

--- Check if any rows match the query. Returns true/false without fetching data.
---@return boolean
function Builder:exists()
    local sql, params = self:_buildSQL("1")
    -- Add LIMIT 1 for perf
    sql = sql .. " LIMIT 1"
    local rows = self:_cachedExecute(sql, params)
    return #rows > 0
end

--- Process results in chunks to avoid memory spikes on large datasets.
---@param size integer  Chunk size
---@param callback fun(rows: OrvexInstance[], chunkIndex: integer): boolean?  Return false to stop
function Builder:chunk(size, callback)
    assert(size > 0, "chunk size must be > 0")
    local chunkIndex = 0
    local currentOffset = self._offset or 0

    while true do
        self._limit = size
        self._offset = currentOffset
        local results = self:get()

        if #results == 0 then break end

        chunkIndex = chunkIndex + 1
        local shouldContinue = callback(results, chunkIndex)
        if shouldContinue == false then break end
        if #results < size then break end

        currentOffset = currentOffset + size
    end
end

--- Paginate results: returns { data, total, page, perPage, lastPage }.
---@param page integer  Page number (1-based)
---@param perPage? integer  Items per page (default 15)
---@return table { data: OrvexInstance[], total: integer, page: integer, perPage: integer, lastPage: integer }
function Builder:paginate(page, perPage)
    page = page or 1
    perPage = perPage or 15
    assert(page >= 1, "Page must be >= 1")
    assert(perPage >= 1, "perPage must be >= 1")

    -- Count total (clone wheres, no limit/offset/order)
    local countBuilder = Builder.new(self._table, self._adapter, nil, self._cache)
    countBuilder._wheres = self._wheres
    countBuilder._joins = self._joins
    countBuilder._distinct = self._distinct
    local total = countBuilder:count()

    -- Fetch page
    self._limit = perPage
    self._offset = (page - 1) * perPage
    local data = self:get()

    local lastPage = math.ceil(total / perPage)
    if lastPage < 1 then lastPage = 1 end

    return {
        data     = data,
        total    = total,
        page     = page,
        perPage  = perPage,
        lastPage = lastPage,
    }
end

--- Execute a WHERE EXISTS (subquery) condition — used for whereHas.
---@param subSQL string  Raw SQL subquery
---@param subParams? any[]
---@return OrvexBuilder
function Builder:whereExists(subSQL, subParams)
    self._wheres[#self._wheres + 1] = {
        clause = "EXISTS (" .. subSQL .. ")",
        params = subParams or {},
    }
    return self
end

--- Return the raw SQL and params without executing.
---@return string sql
---@return any[] params
function Builder:toSQL()
    return self:_buildSQL()
end

OrvexBuilder = Builder
return Builder
