-- core/builder.lua

local Helpers   = OrvexHelpers or require("utils.helpers")
local CacheLib  = OrvexCache or require("utils.cache")

local assertId = Helpers.assertSafeIdentifier
local assertOp = Helpers.assertValidOperator
local ensure   = Helpers.ensure
local ensureBindable = Helpers.ensureBindable
local quoteId  = Helpers.quoteId
local quoteColumnList = Helpers.quoteColumnList

--- MySQL has no "OFFSET without LIMIT": the documented idiom is the largest
--- BIGINT UNSIGNED value as LIMIT.
local UNBOUNDED_LIMIT = "18446744073709551615"

---@alias OrvexWhereOperator "="|"!="|">"|"<"|">="|"<="|"LIKE"|"NOT LIKE"|"IN"|"NOT IN"|"BETWEEN"|"IS"|"IS NOT"

---@alias OrvexWhereValue string|number|boolean|OrvexOpMarker

---@class OrvexWhereEntry
---@field clause string
---@field params any[]
---@field or_flag? boolean

---@class OrvexBuilder
---@field MAX_PER_PAGE integer paginate() perPage ceiling (default 1000)
---@field MAX_IN_VALUES integer whereIn/whereNotIn list ceiling (default 10000)
---@field private _table string
---@field private _adapter OrvexAdapter
---@field private _wrapFn? fun(row: table): OrvexInstance
---@field private _selects string
---@field private _distinct boolean
---@field private _constraints OrvexWhereEntry[] always AND-ed in front of the user conditions
---@field private _wheres OrvexWhereEntry[] user conditions
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

--- Operator condition for table-form where: `{ money = Builder.op(">", 100) }`
--- (also ORM.op). A plain table value is never read as an operator.
Builder.op = Helpers.op

--- Upper bounds on caller-supplied sizes. Values often come from client net
--- events, so an unbounded perPage or IN list would let a player make the
--- server load or build arbitrarily large queries. Raise them on purpose if
--- a trusted use needs more.
Builder.MAX_PER_PAGE = 1000
Builder.MAX_IN_VALUES = 10000

---@param tableName string
---@param adapter OrvexAdapter
---@param wrapFn? fun(row: table): OrvexInstance
---@param cache? OrvexCache
---@return OrvexBuilder
function Builder.new(tableName, adapter, wrapFn, cache)
    assertId(tableName)
    local self = setmetatable({}, Builder)
    self._table     = tableName
    self._adapter   = adapter
    self._wrapFn    = wrapFn
    self._selects   = "*"
    self._distinct  = false
    self._constraints = {}
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

--- Independent copy: conditions added to the clone do not leak back.
---@return OrvexBuilder
function Builder:clone()
    local copy = setmetatable(Helpers.shallowCopy(self), Builder)
    copy._constraints  = Helpers.shallowCopy(self._constraints)
    copy._wheres       = Helpers.shallowCopy(self._wheres)
    copy._joins        = Helpers.shallowCopy(self._joins)
    copy._havingParams = Helpers.shallowCopy(self._havingParams)
    return copy
end

-- ─── Internal: argument validation ────────────────────────────────

---@param n any
---@param label string
---@return integer
local function toNonNegativeInteger(n, label)
    local number = tonumber(n)
    local integer = number and math.tointeger(number)
    assert(integer and integer >= 0, label .. " must be a non-negative integer")
    return integer
end

---@param n any
---@param label string
---@return integer
local function toPositiveInteger(n, label)
    local integer = toNonNegativeInteger(n, label)
    assert(integer >= 1, label .. " must be >= 1")
    return integer
end

---@param direction? string
---@param method string
---@return "ASC"|"DESC"
local function normalizeDirection(direction, method)
    direction = type(direction) == "string" and direction:upper() or direction or "ASC"
    assert(direction == "ASC" or direction == "DESC", method .. " direction must be ASC or DESC")
    return direction
end

---@param column string
---@return string
local function unqualified(column)
    return column:match("([^.]+)$")
end

-- ─── Internal: parse a single where condition ─────────────────────

--- Copy of an IN / BETWEEN array whose elements are all bindable. `#`
--- must match the ipairs count: a nil hole would leave more placeholders
--- than bound values and shift every later parameter.
---@param field string
---@param op string
---@param values any[]
---@return any[]
local function bindableList(field, op, values)
    local list = {}
    for i, element in ipairs(values) do
        ensureBindable(element, ("%s('%s') element %d"):format(op, field, i))
        list[i] = element
    end
    ensure(#list == #values, ("%s('%s'): the array has a nil hole"):format(op, field))
    return list
end

---@param field string
---@param operator string
---@param value any
---@return string clause
---@return any[] params
local function buildCondition(field, operator, value)
    assertId(field)
    assert(type(operator) == "string", ("Invalid SQL operator: '%s'"):format(tostring(operator)))
    local op = operator:upper()
    assertOp(op)
    local column = quoteId(field)

    if op == "IN" or op == "NOT IN" then
        assert(type(value) == "table" and #value > 0, op .. " requires a non-empty array")
        local list = bindableList(field, op, value)
        return column .. " " .. op .. " (" .. Helpers.placeholders(#list) .. ")", list
    elseif op == "BETWEEN" then
        assert(type(value) == "table" and #value == 2, "BETWEEN requires a table with 2 values")
        return column .. " BETWEEN ? AND ?", bindableList(field, op, value)
    elseif op == "IS" or op == "IS NOT" then
        assert(value == "NULL", "IS/IS NOT only supports NULL (use whereNull / whereNotNull)")
        return column .. " " .. op .. " NULL", {}
    end
    ensureBindable(value, ("where('%s', '%s')"):format(field, op))
    return column .. " " .. op .. " ?", { value }
end

--- Equality on `field`, or the condition of an ORM.op marker. Any other
--- table is refused: it is usually data a client shaped as `{ op, value }`.
---@param field string
---@param value any
---@return string clause
---@return any[] params
local function equalityOrMarker(field, value)
    if Helpers.isOp(value) then
        return buildCondition(field, value.operator, value.value)
    end
    ensure(type(value) ~= "table",
        ("where('%s'): a plain table is not a value; build operator conditions with ORM.op(operator, value)")
            :format(field))
    return buildCondition(field, "=", value)
end

---@param self OrvexBuilder
---@param orFlag boolean
---@param clause string
---@param params any[]
local function pushWhere(self, orFlag, clause, params)
    self._wheres[#self._wheres + 1] = { clause = clause, params = params, or_flag = orFlag or nil }
    return self
end

---@param self OrvexBuilder
---@param clause string
---@param params any[]
local function andWhere(self, clause, params)
    return pushWhere(self, false, clause, params)
end

--- Shared implementation of where() / orWhere(). The argument count tells
--- `where(field, value)` apart from `where(field, operator, nil)`: an explicit
--- nil value is an error rather than a silent `field = operator`.
---@param self OrvexBuilder
---@param method string
---@param orFlag? boolean
---@param field string|table
---@param ... any operator?, value
---@return OrvexBuilder
local function addWhere(self, method, orFlag, field, ...)
    local argc = select("#", ...)

    if type(field) == "table" then
        for _, k in ipairs(Helpers.sortedKeys(field)) do
            pushWhere(self, orFlag, equalityOrMarker(k, field[k]))
        end
        return self
    end

    assert(type(field) == "string" and argc >= 1, ("Invalid %s() arguments"):format(method))

    if argc == 1 then
        local value = ...
        assert(value ~= nil, ("%s('%s'): value is nil, use whereNull() / whereNotNull() for NULL checks")
            :format(method, field))
        return pushWhere(self, orFlag, equalityOrMarker(field, value))
    end

    local operator, value = ...
    assert(value ~= nil, ("%s('%s'): value is nil, use whereNull() / whereNotNull() for NULL checks")
        :format(method, field))
    return pushWhere(self, orFlag, buildCondition(field, operator, value))
end

-- ─── Chainable methods ─────────────────────────────────────────────

---@param columns string
---@return OrvexBuilder
function Builder:select(columns)
    self._selects = columns
    return self
end

---@return OrvexBuilder
function Builder:distinct()
    self._distinct = true
    return self
end

---@param field string|table<string, OrvexWhereValue>
---@param operator? OrvexWhereOperator|any
---@param value? any
---@return OrvexBuilder
function Builder:where(field, ...)
    return addWhere(self, "where", false, field, ...)
end

---@param field string|table<string, OrvexWhereValue>
---@param operator? OrvexWhereOperator|any
---@param value? any
---@return OrvexBuilder
function Builder:orWhere(field, ...)
    return addWhere(self, "orWhere", true, field, ...)
end

--- Registers every condition added by `apply` as a constraint: constraints
--- are AND-ed in front of the user conditions, which are parenthesised, so
--- an orWhere can never bypass them (soft delete, whereHas correlation...).
---@param apply fun(builder: OrvexBuilder)
---@return OrvexBuilder
function Builder:constrain(apply)
    local userWheres = self._wheres
    self._wheres = self._constraints
    local ok, err = pcall(apply, self)
    self._wheres = userWheres
    if not ok then error(err, 0) end
    return self
end

--- Operators that compare two columns; IN, BETWEEN or IS would build
--- malformed SQL.
local COLUMN_OPERATORS = { ["="] = true, ["!="] = true, ["<>"] = true,
    [">"] = true, ["<"] = true, [">="] = true, ["<="] = true }

--- Compares two columns: `whereColumn(a, b)` or `whereColumn(a, op, b)`.
---@param first string
---@param operator "="|"!="|"<>"|">"|"<"|">="|"<="|string
---@param second? string
---@return OrvexBuilder
function Builder:whereColumn(first, operator, second)
    if second == nil then
        operator, second = "=", operator
    end
    assertId(first)
    assertId(second)
    ensure(COLUMN_OPERATORS[operator],
        ("whereColumn(): '%s' is not a comparison operator (=, !=, <>, >, <, >=, <=)"):format(tostring(operator)))
    return andWhere(self, quoteId(first) .. " " .. operator .. " " .. quoteId(second), {})
end

--- Escape hatch for conditions the builder cannot express.
--- The clause is inserted verbatim: NEVER interpolate user input into it,
--- always pass values through `params`.
---@param clause string
---@param params? any[]
---@return OrvexBuilder
function Builder:whereRaw(clause, params)
    return andWhere(self, "(" .. clause .. ")", params or {})
end

--- Values are always bound as placeholders: a string is never read as a
--- subquery, since whereIn values often come from client net events. Use
--- whereInSub() / whereNotInSub() for a subquery.
---@param self OrvexBuilder
---@param method string
---@param operator "IN"|"NOT IN"
---@param column string
---@param values any[]
local function addIn(self, method, operator, column, values)
    assertId(column)
    assert(type(values) == "table",
        ("%s('%s') requires an array of values, got %s (use %sSub() for a subquery)")
            :format(method, column, type(values), method))
    assert(#values > 0, method .. " requires a non-empty array")
    assert(#values <= Builder.MAX_IN_VALUES,
        ("%s('%s') accepts at most %d values (Builder.MAX_IN_VALUES), got %d")
            :format(method, column, Builder.MAX_IN_VALUES, #values))
    return andWhere(self, buildCondition(column, operator, values))
end

--- The subquery is inserted verbatim: NEVER interpolate user input into it,
--- always pass values through `subParams`.
---@param self OrvexBuilder
---@param method string
---@param operator "IN"|"NOT IN"
---@param column string
---@param subSQL string
---@param subParams? any[]
local function addInSub(self, method, operator, column, subSQL, subParams)
    assertId(column)
    assert(type(subSQL) == "string", ("%s('%s') requires a SQL string"):format(method, column))
    return andWhere(self, quoteId(column) .. " " .. operator .. " (" .. subSQL .. ")", subParams or {})
end

---@param column string
---@param values any[]
---@return OrvexBuilder
function Builder:whereIn(column, values)
    return addIn(self, "whereIn", "IN", column, values)
end

---@param column string
---@param values any[]
---@return OrvexBuilder
function Builder:whereNotIn(column, values)
    return addIn(self, "whereNotIn", "NOT IN", column, values)
end

--- `column IN (subSQL)`.
---@param column string
---@param subSQL string
---@param subParams? any[]
---@return OrvexBuilder
function Builder:whereInSub(column, subSQL, subParams)
    return addInSub(self, "whereInSub", "IN", column, subSQL, subParams)
end

--- `column NOT IN (subSQL)`.
---@param column string
---@param subSQL string
---@param subParams? any[]
---@return OrvexBuilder
function Builder:whereNotInSub(column, subSQL, subParams)
    return addInSub(self, "whereNotInSub", "NOT IN", column, subSQL, subParams)
end

---@param self OrvexBuilder
---@param operator "BETWEEN"|"NOT BETWEEN"
local function addBetween(self, operator, column, min, max)
    assertId(column)
    ensureBindable(min, ("%s('%s') min"):format(operator, column))
    ensureBindable(max, ("%s('%s') max"):format(operator, column))
    return andWhere(self, quoteId(column) .. " " .. operator .. " ? AND ?", { min, max })
end

---@param column string
---@param min any
---@param max any
---@return OrvexBuilder
function Builder:whereBetween(column, min, max)
    return addBetween(self, "BETWEEN", column, min, max)
end

---@param column string
---@param min any
---@param max any
---@return OrvexBuilder
function Builder:whereNotBetween(column, min, max)
    return addBetween(self, "NOT BETWEEN", column, min, max)
end

---@param column string
---@param pattern string
---@return OrvexBuilder
function Builder:whereLike(column, pattern)
    return andWhere(self, buildCondition(column, "LIKE", pattern))
end

---@param column string
---@return OrvexBuilder
function Builder:whereNull(column)
    return andWhere(self, buildCondition(column, "IS", "NULL"))
end

---@param column string
---@return OrvexBuilder
function Builder:whereNotNull(column)
    return andWhere(self, buildCondition(column, "IS NOT", "NULL"))
end

---@param self OrvexBuilder
---@param kind "LEFT"|"INNER"|"RIGHT"
local function addJoin(self, kind, joinTable, col1, col2)
    assertId(joinTable)
    assertId(col1)
    assertId(col2)
    self._joins[#self._joins + 1] = ("%s JOIN %s ON %s = %s"):format(
        kind, quoteId(joinTable), quoteId(col1), quoteId(col2)
    )
    return self
end

---@param joinTable string
---@param col1 string
---@param col2 string
---@return OrvexBuilder
function Builder:leftJoin(joinTable, col1, col2)
    return addJoin(self, "LEFT", joinTable, col1, col2)
end

---@param joinTable string
---@param col1 string
---@param col2 string
---@return OrvexBuilder
function Builder:innerJoin(joinTable, col1, col2)
    return addJoin(self, "INNER", joinTable, col1, col2)
end

---@param joinTable string
---@param col1 string
---@param col2 string
---@return OrvexBuilder
function Builder:rightJoin(joinTable, col1, col2)
    return addJoin(self, "RIGHT", joinTable, col1, col2)
end

---@param columns string
---@return OrvexBuilder
function Builder:groupBy(columns)
    self._groupBy = columns
    return self
end

---@param clause string
---@param ... any
---@return OrvexBuilder
function Builder:having(clause, ...)
    self._having = clause
    self._havingParams = { ... }
    return self
end

---@param self OrvexBuilder
---@param column string
---@param direction "ASC"|"DESC"
local function setOrder(self, column, direction)
    assertId(column)
    self._orderBy = quoteId(column) .. " " .. direction
    return self
end

---@param column string
---@param direction? "ASC"|"DESC"
---@return OrvexBuilder
function Builder:orderBy(column, direction)
    return setOrder(self, column, normalizeDirection(direction, "orderBy"))
end

---@param column string
---@return OrvexBuilder
function Builder:orderByDesc(column)
    return setOrder(self, column, "DESC")
end

---@param column string
---@return OrvexBuilder
function Builder:orderByAsc(column)
    return setOrder(self, column, "ASC")
end

---@param column? string
---@return OrvexBuilder
function Builder:latest(column)
    return setOrder(self, column or "created_at", "DESC")
end

---@param column? string
---@return OrvexBuilder
function Builder:oldest(column)
    return setOrder(self, column or "created_at", "ASC")
end

--- Accepts integral numbers or numeric strings; anything else raises, so
--- client input can never reach the SQL text.
---@param n integer
---@return OrvexBuilder
function Builder:limit(n)
    self._limit = toNonNegativeInteger(n, "limit")
    return self
end

---@param n integer
---@return OrvexBuilder
function Builder:offset(n)
    self._offset = toNonNegativeInteger(n, "offset")
    return self
end

---@param self OrvexBuilder
---@param method string
---@param ascendingOp ">"|"<"
---@param descendingOp ">"|"<"
local function addCursor(self, method, column, value, direction, ascendingOp, descendingOp)
    direction = normalizeDirection(direction, method)
    local op = direction == "DESC" and descendingOp or ascendingOp
    andWhere(self, buildCondition(column, op, value))
    return setOrder(self, column, direction)
end

---@param column string
---@param value any
---@param direction? "ASC"|"DESC"
---@return OrvexBuilder
function Builder:after(column, value, direction)
    return addCursor(self, "after", column, value, direction, ">", "<")
end

---@param column string
---@param value any
---@param direction? "ASC"|"DESC"
---@return OrvexBuilder
function Builder:before(column, value, direction)
    return addCursor(self, "before", column, value, direction, "<", ">")
end

---@param subSQL string
---@param subParams? any[]
---@return OrvexBuilder
function Builder:whereExists(subSQL, subParams)
    return andWhere(self, "EXISTS (" .. subSQL .. ")", subParams or {})
end

-- ─── SQL assembly ──────────────────────────────────────────────────

---@param entries OrvexWhereEntry[]
---@param params any[] appended in place
---@return string
local function joinConditions(entries, params)
    local parts = {}
    for i, w in ipairs(entries) do
        if i == 1 then
            parts[1] = w.clause
        else
            parts[#parts + 1] = (w.or_flag and "OR " or "AND ") .. w.clause
        end
        for _, p in ipairs(w.params) do
            params[#params + 1] = p
        end
    end
    return table.concat(parts, " ")
end

--- Builds `WHERE c1 AND c2 AND (user conditions)`; the user conditions are
--- only parenthesised when constraints exist and there is more than one.
---@private
---@return string clause starts with " WHERE " or is empty
---@return any[] params
function Builder:_buildWhere()
    local params = {}
    local constraints = joinConditions(self._constraints, params)
    local userConditions = joinConditions(self._wheres, params)

    if constraints == "" and userConditions == "" then
        return "", params
    end
    if constraints == "" then
        return " WHERE " .. userConditions, params
    end
    if userConditions == "" then
        return " WHERE " .. constraints, params
    end
    if #self._wheres > 1 then
        userConditions = "(" .. userConditions .. ")"
    end
    return " WHERE " .. constraints .. " AND " .. userConditions, params
end

--- FROM, joins, WHERE, GROUP BY and HAVING: everything but the select list
--- and the paging clauses.
---@private
---@return string sql starts with " FROM "
---@return any[] params
function Builder:_buildBody()
    local parts = { " FROM " .. quoteId(self._table) }

    for _, j in ipairs(self._joins) do
        parts[#parts + 1] = " " .. j
    end

    local whereSQL, params = self:_buildWhere()
    parts[#parts + 1] = whereSQL

    if self._groupBy then
        parts[#parts + 1] = " GROUP BY " .. quoteColumnList(self._groupBy)
    end

    if self._having then
        parts[#parts + 1] = " HAVING " .. self._having
        for _, p in ipairs(self._havingParams) do
            params[#params + 1] = p
        end
    end

    return table.concat(parts), params
end

---@private
---@return string
function Builder:_buildPaging()
    local parts = {}
    if self._orderBy then
        parts[#parts + 1] = " ORDER BY " .. self._orderBy
    end
    if self._limit then
        parts[#parts + 1] = " LIMIT " .. self._limit
    elseif self._offset then
        parts[#parts + 1] = " LIMIT " .. UNBOUNDED_LIMIT
    end
    if self._offset then
        parts[#parts + 1] = " OFFSET " .. self._offset
    end
    return table.concat(parts)
end

---@private
---@param selectExpr string
---@return string
function Builder:_selectClause(selectExpr)
    local keyword = self._distinct and "SELECT DISTINCT " or "SELECT "
    return keyword .. quoteColumnList(selectExpr)
end

---@private
---@param selectExpr? string
---@return string sql
---@return any[] params
function Builder:_buildSQL(selectExpr)
    local body, params = self:_buildBody()
    return self:_selectClause(selectExpr or self:_defaultSelect()) .. body .. self:_buildPaging(), params
end

--- A model query wraps every row as an instance of its own table, keyed by
--- the row's primary key. With joins, `*` would let a joined table's
--- same-named column (`id`...) overwrite it, and the instance's writes
--- would hit another row: the default select becomes `table`.*.
---@private
---@return string
function Builder:_defaultSelect()
    if self._selects == "*" and self._wrapFn and #self._joins > 0 then
        return self._table .. ".*"
    end
    return self._selects
end

--- Select list of the derived table a count wraps. A `*` select would
--- copy same-named columns of joined tables into it, which MySQL rejects
--- (duplicate column name): it becomes the group-by columns, or the main
--- table's columns.
---@private
---@return string
function Builder:_countedSelect()
    if self._selects ~= "*" then return self._selects end
    return self._groupBy or (self._table .. ".*")
end

--- Counts the rows the query would return, ignoring ORDER BY / LIMIT /
--- OFFSET. DISTINCT, GROUP BY and HAVING change what a "row" is, so the
--- query is then counted as a derived table.
---@private
---@return string sql
---@return any[] params
function Builder:_buildCountSQL()
    local body, params = self:_buildBody()
    if self._distinct or self._groupBy or self._having then
        local inner = self:_selectClause(self:_countedSelect()) .. body
        return "SELECT COUNT(*) AS cnt FROM (" .. inner .. ") AS t", params
    end
    return "SELECT COUNT(*) AS cnt" .. body, params
end

-- ─── Terminal methods ──────────────────────────────────────────────

---@private
function Builder:_cachedExecute(sql, params)
    if self._cache and self._cache:isEnabled() then
        local cacheKey = CacheLib.makeKey(sql, params)
        local cached, hit = self._cache:get(cacheKey)
        if hit then
            return cached or {}, true
        end

        local rows = self._adapter:execute(sql, params)
        self._cache:set(cacheKey, rows)
        return rows or {}, true
    end

    return self._adapter:execute(sql, params) or {}, false
end

---@return OrvexInstance[]
function Builder:get()
    local sql, params = self:_buildSQL()
    local rows, shared = self:_cachedExecute(sql, params)

    if self._wrapFn then
        local results = {}
        -- When rows live in the cache, wrap copies: wrapping decodes JSON
        -- fields and attaches a metatable in place, which would corrupt
        -- the cached entry for subsequent hits.
        if shared then
            for i, row in ipairs(rows) do
                results[i] = self._wrapFn(Helpers.shallowCopy(row))
            end
        else
            for i, row in ipairs(rows) do
                results[i] = self._wrapFn(row)
            end
        end
        return results
    end

    return rows
end

---@return OrvexInstance|nil
function Builder:first()
    self._limit = 1
    local results = self:get()
    return results[1] or nil
end

---@return integer
function Builder:count()
    local sql, params = self:_buildCountSQL()
    local rows = self:_cachedExecute(sql, params)
    if rows[1] then return tonumber(rows[1].cnt) or 0 end
    return 0
end

--- Runs `FN(column)` over the filtered rows (paging is ignored).
--- MySQL may return strings for aggregate results via the text protocol,
--- hence the tonumber().
---@param self OrvexBuilder
---@param fn "SUM"|"AVG"|"MIN"|"MAX"
---@param column string
---@return any
local function aggregate(self, fn, column)
    assertId(column)
    local body, params = self:_buildBody()
    local sql = ("SELECT %s(%s) AS val"):format(fn, quoteId(column)) .. body
    local rows = self:_cachedExecute(sql, params)
    local value = rows[1] and rows[1].val
    return tonumber(value) or value
end

---@param column string
---@return number
function Builder:sum(column)
    return aggregate(self, "SUM", column) or 0
end

---@param column string
---@return number
function Builder:avg(column)
    return aggregate(self, "AVG", column) or 0
end

---@param column string
---@return any
function Builder:min(column)
    return aggregate(self, "MIN", column)
end

---@param column string
---@return any
function Builder:max(column)
    return aggregate(self, "MAX", column)
end

--- MySQL names a `table.column` result after the bare column.
---@param column string
---@return any[]
function Builder:pluck(column)
    assertId(column)
    local sql, params = self:_buildSQL(column)
    local rows = self:_cachedExecute(sql, params)

    local key = unqualified(column)
    local values = {}
    for i, row in ipairs(rows) do
        values[i] = row[key]
    end
    return values
end

---@return boolean
function Builder:exists()
    local probe = self:clone()
    probe._limit = 1
    local sql, params = probe:_buildSQL("1")
    local rows = self:_cachedExecute(sql, params)
    return #rows > 0
end

--- Scans run on uncached clones: caching every chunk of a full-table scan
--- would only evict useful entries.
---@private
---@return OrvexBuilder
function Builder:_scanner()
    local scanner = self:clone()
    scanner._cache = nil
    return scanner
end

--- A limit set on the builder bounds the whole scan: `remaining` rows are
--- still to read (nil: no limit).
---@param size integer
---@param remaining? integer
---@return integer
local function pageSize(size, remaining)
    if remaining and remaining < size then return remaining end
    return size
end

--- OFFSET-based chunking. Prefer chunkById on large tables: each chunk
--- makes MySQL skip every previous row. A limit set on the builder caps
--- the total number of rows scanned.
---@param size integer
---@param callback fun(rows: OrvexInstance[], chunkIndex: integer): boolean?
function Builder:chunk(size, callback)
    size = toPositiveInteger(size, "chunk size")
    local scanner = self:_scanner()
    local chunkIndex = 0
    local currentOffset = self._offset or 0
    local remaining = self._limit

    while remaining ~= 0 do
        local limit = pageSize(size, remaining)
        scanner._limit = limit
        scanner._offset = currentOffset
        local results = scanner:get()

        if #results == 0 then break end

        chunkIndex = chunkIndex + 1
        local shouldContinue = callback(results, chunkIndex)
        if shouldContinue == false then break end
        if #results < limit then break end

        currentOffset = currentOffset + limit
        if remaining then remaining = remaining - limit end
    end
end

--- Keyset chunking: `WHERE column > lastKey ORDER BY column LIMIT size`.
--- Constant cost per chunk whatever the table size. `column` must be unique
--- and present in the selected columns. A limit set on the builder caps
--- the total number of rows scanned; an offset is refused (keyset pages
--- do not skip rows).
---@param size integer
---@param callback fun(rows: OrvexInstance[], chunkIndex: integer): boolean?
---@param column? string defaults to "id"
function Builder:chunkById(size, callback, column)
    size = toPositiveInteger(size, "chunkById size")
    ensure(self._offset == nil, "chunkById() cannot be combined with offset(): use where(column, '>', key) instead")
    column = column or "id"
    assertId(column)
    local key = unqualified(column)
    local lastKey = nil
    local chunkIndex = 0
    local remaining = self._limit

    while remaining ~= 0 do
        local page = self:_scanner()
        if lastKey ~= nil then
            page:constrain(function(q) q:where(column, ">", lastKey) end)
        end
        setOrder(page, column, "ASC")
        local limit = pageSize(size, remaining)
        page._limit = limit
        local results = page:get()

        if #results == 0 then break end

        chunkIndex = chunkIndex + 1
        if callback(results, chunkIndex) == false then break end
        if #results < limit then break end
        if remaining then remaining = remaining - limit end

        lastKey = results[#results][key]
        assert(lastKey ~= nil, ("chunkById: column '%s' is missing from the results"):format(key))
    end
end

---@param page integer
---@param perPage? integer
---@return table
function Builder:paginate(page, perPage)
    page = toPositiveInteger(page or 1, "Page")
    perPage = toPositiveInteger(perPage or 15, "perPage")
    ensure(perPage <= Builder.MAX_PER_PAGE,
        ("paginate(): perPage must be at most %d (Builder.MAX_PER_PAGE), got %d")
            :format(Builder.MAX_PER_PAGE, perPage))
    -- Lua integers wrap: a huge page would give a negative (or zero) OFFSET.
    ensure(page - 1 <= math.maxinteger // perPage,
        ("paginate(): page %d is too large for perPage %d"):format(page, perPage))

    local total = self:count()

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

---@return string sql
---@return any[] params
function Builder:toSQL()
    return self:_buildSQL()
end

OrvexBuilder = Builder
return Builder
