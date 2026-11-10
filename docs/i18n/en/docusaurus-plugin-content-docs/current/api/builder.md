---
sidebar_position: 4
---

# Builder (Query Builder)

The Query Builder lets you build complex queries by chaining methods. You get one with `Model.query()`.

```lua
local builder = User.query()
```

:::info Identifiers and values
- **Values** always go through `?` parameters: never concatenated into the SQL.
- Column and table **names** are validated (letters, digits, `_` and `.` only, otherwise `Invalid SQL identifier`) then wrapped in backticks: `` `group` ``, `` `users`.`money` ``. MySQL reserved words (`group`, `key`, `order`, `rank`...) can therefore be used as column names.
- Operators are limited to `=`, `!=`, `<>`, `>`, `<`, `>=`, `<=`, `LIKE`, `NOT LIKE`, `IN`, `NOT IN`, `BETWEEN`, `IS`, `IS NOT`.
- `:whereRaw()`, `:having()`, `:whereExists()`, `:whereInSub()` and `:whereNotInSub()` are inserted **as is**: never put player data in them, pass it as parameters. `:whereIn()` / `:whereNotIn()` only accept an array, always bound as parameters: a string (for example a malformed client event payload) raises an error instead of being inserted as a subquery.

A model with `softDelete` adds the `deleted_at IS NULL` filter as a **constraint**: it is always combined with `AND` in front of your conditions, and an `orWhere` cannot bypass it.
:::

---

## Chainable methods

All these methods return the builder, so they can be chained.

### `:where(conditions)`

Adds a WHERE condition (joined with AND).

**4 ways to use it:**

```lua
-- 1. Simple equality (table)
:where({ job = "police" })

-- 2. Equality shortcut (2 arguments, implicit =)
:where("job", "police")

-- 3. With an operator (3 arguments), including IN / BETWEEN / IS
:where("money", ">", 1000)
:where("id", "IN", { 1, 2, 3 })
:where("money", "BETWEEN", { 500, 5000 })

-- 4. Operator inside the table
:where({ money = { ">", 1000 } })
:where({ job = { "LIKE", "%poli%" } })
:where({ id = { "IN", { 1, 2, 3 } } })
:where({ money = { "BETWEEN", { 500, 5000 } } })
:where({ status = { "!=", "banned" } })
:where({ job = { "IS", "NULL" } })
:where({ job = { "IS NOT", "NULL" } })
```

:::tip 2-argument shortcut
`:where("job", "police")` is equivalent to `:where({ job = "police" })`. It is shorter when you only have one condition.
:::

:::caution `nil` value
`:where("job", nil)` or `:where("job", "=", nil)` raises an error (`value is nil, use whereNull() / whereNotNull()`) instead of generating a silently wrong condition. Use `:whereNull("job")`. In the table form, a key set to `nil` does not exist in Lua and is therefore ignored.
:::

---

### `:orWhere(conditions)`

Adds a condition joined with OR. Same forms as `:where()`.

```lua
:where({ job = "police" })
:orWhere({ job = "medic" })
-- SQL: WHERE `job` = ? OR `job` = ?

-- On a model with softDelete, your conditions are grouped after the filter:
-- WHERE `deleted_at` IS NULL AND (`job` = ? OR `job` = ?)
```

:::caution AND / OR precedence
Your conditions are joined in the order you add them, and MySQL evaluates `AND` before `OR`: `:where(a):where(b):orWhere(c)` gives `a AND b OR c`, that is `(a AND b) OR c`. For another grouping, write it with `:whereRaw("(job = ? OR job = ?)", { "police", "medic" })`.
:::

---

### `:whereColumn(first, operator?, second)`

Compares two columns (no parameter).

```lua
:whereColumn("updated_at", ">", "created_at")
:whereColumn("users.identifier", "vehicles.owner")  -- implicit =
```

---

### `:orderBy(column, direction?)`

Sorts the results. One sort at a time: a new call replaces the previous one.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `column` | `string` | — | Sort column |
| `direction` | `"ASC" \| "DESC"` | `"ASC"` | Sort direction (case-insensitive; any other value raises an error) |

```lua
:orderBy("money", "DESC")
:orderBy("name")  -- ASC by default
```

---

### `:orderByDesc(column)`

Shortcut for ORDER BY ... DESC.

```lua
:orderByDesc("money")
```

---

### `:orderByAsc(column)`

Shortcut for ORDER BY ... ASC.

```lua
:orderByAsc("name")
```

---

### `:latest(column?)`

Sorts by the given column, DESC. Default: `"created_at"`.

```lua
:latest()              -- ORDER BY created_at DESC
:latest("updated_at")  -- ORDER BY updated_at DESC
```

---

### `:oldest(column?)`

Sorts by the given column, ASC. Default: `"created_at"`.

```lua
:oldest()  -- ORDER BY created_at ASC
```

---

### `:limit(n)`

Limits the number of results. `n` must be an integer >= 0 (an integral number or a numeric string such as `"10"`); any other value raises an error, so player input can never reach the SQL.

```lua
:limit(10)
```

---

### `:offset(n)`

Skips the first N results (for pagination). Same rules as `:limit()`. Also works without `:limit()`.

```lua
:offset(20)
```

---

### `:select(columns)`

Sets the columns to select (default: `"*"`), as a comma-separated **string** (whereas `find`'s `opts.select` takes an array). Plain names (`money`, `users.money`, `users.*`) are quoted; expressions (`COUNT(*) AS nb`, `SUM(money) AS total`) are kept as is: never build this string from player input.

```lua
:select("identifier, money")
:select("users.*, profiles.bio")
:select("job, COUNT(*) AS nb")
```

---

### `:leftJoin(table, col1, col2)`

Adds a LEFT JOIN.

```lua
:leftJoin("profiles", "profiles.user_id", "users.identifier")
```

---

### `:innerJoin(table, col1, col2)`

Adds an INNER JOIN.

```lua
:innerJoin("vehicles", "vehicles.owner_id", "users.identifier")
```

---

### `:rightJoin(table, col1, col2)`

Adds a RIGHT JOIN.

```lua
:rightJoin("users", "users.identifier", "vehicles.owner_id")
```

---

### `:groupBy(columns)`

Groups the results.

```lua
:groupBy("job")
:groupBy("job, department")
```

---

### `:having(clause, ...params)`

Filters the groups (used with `groupBy`).

```lua
:having("COUNT(*) > ?", 5)
:having("SUM(money) > ?", 10000)
```

---

### `:distinct()`

Turns the query into `SELECT DISTINCT`.

```lua
:distinct()
-- SQL: SELECT DISTINCT * FROM users ...
```

---

### `:whereNull(column)`

Keeps the rows where the column is NULL.

```lua
:whereNull("deleted_at")
-- SQL: WHERE deleted_at IS NULL
```

---

### `:whereNotNull(column)`

Keeps the rows where the column is not NULL.

```lua
:whereNotNull("email")
-- SQL: WHERE email IS NOT NULL
```

---

### `:whereIn(column, values)`

Filters with a list of values, bound as parameters. An empty list raises an error (`whereIn requires a non-empty array`): check `#values > 0` before calling. Any type other than an array raises an error: for a subquery, use `:whereInSub()`.

```lua
:whereIn("job", { "police", "medic", "fire" })
-- SQL: WHERE job IN (?, ?, ?)
```

---

### `:whereNotIn(column, values)`

Filters with NOT IN (array only, like `:whereIn()`).

```lua
:whereNotIn("id", { 1, 2, 3 })
-- SQL: WHERE id NOT IN (?, ?, ?)
```

---

### `:whereInSub(column, subSQL, params?)`

Filters with an IN subquery. `subSQL` is inserted as is: pass the values in `params`.

```lua
:whereInSub("id", "SELECT user_id FROM active_users WHERE last_login > ?", { "2024-01-01" })
-- SQL: WHERE id IN (SELECT user_id FROM active_users WHERE last_login > ?)
```

---

### `:whereNotInSub(column, subSQL, params?)`

Filters with a NOT IN subquery.

```lua
:whereNotInSub("id", "SELECT user_id FROM banned_users")
-- SQL: WHERE id NOT IN (SELECT user_id FROM banned_users)
```

---

### `:whereBetween(column, min, max)`

Shortcut for BETWEEN.

```lua
:whereBetween("money", 500, 5000)
-- SQL: WHERE money BETWEEN ? AND ?
```

---

### `:whereNotBetween(column, min, max)`

Shortcut for NOT BETWEEN.

```lua
:whereNotBetween("money", 0, 100)
-- SQL: WHERE money NOT BETWEEN ? AND ?
```

---

### `:whereLike(column, pattern)`

Shortcut for LIKE.

```lua
:whereLike("name", "%john%")
-- SQL: WHERE name LIKE ?
```

---

### `:whereExists(subSQL, params?)`

Filters with `WHERE EXISTS` (subquery).

```lua
:whereExists("SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.id")
-- SQL: WHERE EXISTS (SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.id)
```

---

### `:whereRaw(clause, params?)`

Adds a free SQL clause, wrapped in parentheses and combined with AND with the other conditions.

```lua
:whereRaw("money > ? OR job = ?", { 1000, "police" })
-- SQL: WHERE (money > ? OR job = ?)

:whereRaw("LOWER(name) = ?", { "john" })
-- SQL: WHERE (LOWER(name) = ?)
```

:::caution SQL injection
**Always** pass values through `params`, never by string concatenation. `:whereRaw("name = '" .. input .. "'")` is an open door to SQL injection.
:::

---

### `:after(column, value, direction?)`

Cursor pagination: fetches the rows after a given value, and sorts on that column. `direction` is `"ASC"` (default) or `"DESC"`; with `DESC`, "after" means "smaller".

```lua
-- Fetch the 10 players after ID 50
User.query():after("id", 50):limit(10):get()
-- SQL: WHERE `id` > ? ORDER BY `id` ASC LIMIT 10

User.query():after("id", 50, "DESC"):limit(10):get()
-- SQL: WHERE `id` < ? ORDER BY `id` DESC LIMIT 10
```

---

### `:before(column, value, direction?)`

Cursor pagination: fetches the rows before a given value.

```lua
User.query():before("id", 50):limit(10):get()
-- SQL: WHERE `id` < ? ORDER BY `id` ASC LIMIT 10
```

---

## Terminal methods

These methods **run** the query and return a result. They wait for the database: call them from a thread, an event or a command ([Async and threads](/docs/getting-started#async-and-threads)).

### `:get()` → `OrvexInstance[]`

Runs the query and returns every row.

```lua
local results = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :get()
```

---

### `:first()` → `OrvexInstance | nil`

Runs the query and returns the first row (adds `LIMIT 1` automatically).

```lua
local richest = User.query()
    :orderBy("money", "DESC")
    :first()
```

---

### `:count()` → `integer`

Counts the rows the query would return, ignoring `orderBy`, `limit` and `offset`. With `:distinct()`, `:groupBy()` or `:having()`, the query is counted as a derived table: `count()` returns the number of distinct rows or groups, not the number of raw rows. With the default select (`*`), the derived table selects the `groupBy` columns, or else `table.*` of the main table, to avoid the duplicate column names of a join.

```lua
local nb = User.query()
    :where({ job = "police" })
    :count()
```

---

### `:sum(column)` → `number`

Sums the values of a column.

```lua
local total = User.query()
    :where({ job = "police" })
    :sum("money")
```

---

### `:avg(column)` → `number`

Computes the average.

```lua
local avg = User.query():avg("money")
```

---

### `:min(column)` → `any`

Returns the minimum value.

```lua
local min = User.query():min("money")
```

---

### `:max(column)` → `any`

Returns the maximum value.

```lua
local max = User.query():max("money")
```

---

### `:pluck(column)` → `any[]`

Returns an array with the values of a single column. A qualified column (`"users.job"`) works too.

```lua
local jobs = User.query():pluck("job")
-- { "police", "medic", "firefighter" }
```

---

### `:exists()` → `boolean`

Checks whether at least one row matches. Does not load the data.

```lua
local hasCops = User.query():where("job", "police"):exists()
```

---

### `:chunk(size, callback)`

Processes the results in batches with `LIMIT` / `OFFSET`, to avoid loading everything into memory. The callback receives `(rows, chunkIndex)`; returning `false` stops the scan. Batches are not cached.

```lua
User.query():chunk(100, function(rows, chunkIndex)
    -- process the batch...
    return false -- return false to stop
end)
```

:::caution Prefer `chunkById` on large tables
With `OFFSET`, MySQL rereads every previous row for each batch: the cost grows with the table. And if the callback changes rows so that they no longer match the filter (or deletes them), the following batches **skip rows**.
:::

---

### `:chunkById(size, callback, column?)`

Processes in batches with **keyset** pagination: `WHERE column > lastKey ORDER BY column LIMIT size`. Constant cost per batch whatever the table size, and no row is skipped if the callback changes or deletes the batch's rows.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `size` | `integer` | — | Batch size (>= 1) |
| `callback` | `function(rows, chunkIndex)` | — | Returning `false` stops the scan |
| `column` | `string` | `"id"` | A **unique** column present in the selected columns (often the primary key) |

```lua
User.query():where("job", "police"):chunkById(200, function(cops)
    for _, cop in ipairs(cops) do cop:update({ money = 0 }) end
end, "identifier")
```

The builder's sort is replaced by the sort on `column`.

---

### `:paginate(page, perPage?)` → `table`

Paginates the results automatically (2 queries: a `count()` and the page). Returns an object with the data and the pagination metadata. The total is correct with `distinct`, `groupBy` and `having` too. `page` and `perPage` must be integers >= 1.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `page` | `integer` | — | Page number (starts at 1) |
| `perPage` | `integer` | `15` | Number of items per page |

```lua
local page = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :paginate(2, 10)

-- page.data     → OrvexInstance[] (the results)
-- page.total    → total number of records
-- page.page     → 2
-- page.perPage  → 10
-- page.lastPage → ceil(total / perPage)
```

---

### `:toSQL()` → `string, table`

Returns the generated SQL and the parameters **without running** the query.

```lua
local sql, params = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :toSQL()

print(sql)     -- SELECT * FROM `users` WHERE `job` = ? AND `money` > ?
print(params)  -- { "police", 500 }
```

---

### `:clone()` → `OrvexBuilder`

Returns an independent copy of the builder: conditions added to the copy do not affect the original.

```lua
local cops = User.query():where("job", "police")
local richCops = cops:clone():where("money", ">", 10000)
print(cops:count(), richCops:count())
```

---

## Full examples

### Leaderboard with pagination

```lua
-- Page 2 of the top players (10 per page)
local page2 = User.query()
    :where("money", ">", 0)
    :orderBy("money", "DESC")
    :limit(10)
    :offset(10)
    :get()
```

### Statistics per job

```lua
local stats = User.query()
    :select("job, COUNT(*) as nb, AVG(money) as avg_money")
    :groupBy("job")
    :having("COUNT(*) >= ?", 2)
    :orderBy("avg_money", "DESC")
    :get()
```

### Players with a profile (join)

```lua
local players = User.query()
    :select("users.*, profiles.bio, profiles.avatar")
    :leftJoin("profiles", "profiles.user_id", "users.identifier")
    :where({ job = { "IN", { "police", "medic" } } })
    :where({ money = { "BETWEEN", { 1000, 50000 } } })
    :orderBy("money", "DESC")
    :limit(20)
    :get()
```
