---
sidebar_position: 4
---

# Builder (Query Builder)

The Query Builder lets you build complex queries by chaining methods. You get it with `Model.query()`.

```lua
local builder = User.query()
```

---

## Chainable methods

All these methods return the builder, which allows you to chain them.

### `:where(conditions)`

Adds a WHERE condition (joined by AND).

**3 ways to use it:**

```lua
-- 1. Simple equality
:where({ job = "police" })

-- 2. With operator
:where("money", ">", 1000)

-- 3. Operator in table
:where({ money = { ">", 1000 } })
:where({ job = { "LIKE", "%poli%" } })
:where({ id = { "IN", { 1, 2, 3 } } })
:where({ money = { "BETWEEN", { 500, 5000 } } })
:where({ status = { "!=", "banned" } })
:where({ job = { "IS", "NULL" } })
:where({ job = { "IS NOT", "NULL" } })
```

---

### `:orWhere(conditions)`

Adds a condition joined by OR.

```lua
:where({ job = "police" })
:orWhere({ job = "medic" })
-- SQL: WHERE job = ? OR job = ?
```

---

### `:orderBy(column, direction?)`

Sorts the results.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `column` | `string` | — | Sort column |
| `direction` | `"ASC" \| "DESC"` | `"ASC"` | Sort direction |

```lua
:orderBy("money", "DESC")
:orderBy("name")  -- ASC by default
```

---

### `:limit(n)`

Limits the number of results.

```lua
:limit(10)
```

---

### `:offset(n)`

Skips the first N results (for pagination).

```lua
:offset(20)
```

---

### `:select(columns)`

Specifies the columns to select (default: `"*"`).

```lua
:select("identifier, money")
:select("users.*, profiles.bio")
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

Enables `SELECT DISTINCT` on the query.

```lua
:distinct()
-- SQL: SELECT DISTINCT * FROM users ...
```

---

### `:whereNull(column)`

Filters rows where the column is NULL.

```lua
:whereNull("deleted_at")
-- SQL: WHERE deleted_at IS NULL
```

---

### `:whereNotNull(column)`

Filters rows where the column is not NULL.

```lua
:whereNotNull("email")
-- SQL: WHERE email IS NOT NULL
```

---

### `:whereIn(column, subSQL, params?)`

Filters with an IN subquery.

```lua
:whereIn("id", "SELECT user_id FROM active_users WHERE last_login > ?", { "2024-01-01" })
-- SQL: WHERE id IN (SELECT user_id FROM active_users WHERE last_login > ?)
```

---

### `:whereNotIn(column, subSQL, params?)`

Filters with a NOT IN subquery.

```lua
:whereNotIn("id", "SELECT user_id FROM banned_users")
-- SQL: WHERE id NOT IN (SELECT user_id FROM banned_users)
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

Adds a raw SQL clause, wrapped in parentheses and combined with AND.

```lua
:whereRaw("LOWER(job) = ?", { "police" })
-- SQL: WHERE (LOWER(job) = ?)

:whereRaw("money > ? OR job = ?", { 1000, "police" })
-- SQL: WHERE (money > ? OR job = ?)
```

:::caution
Always pass values through `params` (`?` placeholders), **never** by string concatenation. Concatenating values into the clause opens the door to SQL injection.
:::

---

### `:after(column, value, direction?)`

Cursor-based pagination: retrieves rows after a given value.

```lua
-- Retrieve the 10 players after ID 50
User.query():after("id", 50):limit(10):get()
-- SQL: WHERE id > 50 ORDER BY id ASC LIMIT 10
```

---

### `:before(column, value, direction?)`

Cursor-based pagination: retrieves rows before a given value.

```lua
User.query():before("id", 50):limit(10):get()
-- SQL: WHERE id < 50 ORDER BY id ASC LIMIT 10
```

---

## Terminal methods

These methods **execute** the query and return a result.

### `:get()` → `OrvexInstance[]`

Executes the query and returns all rows.

```lua
local results = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :get()
```

---

### `:first()` → `OrvexInstance | nil`

Executes the query and returns the first row (automatically adds `LIMIT 1`).

```lua
local richest = User.query()
    :orderBy("money", "DESC")
    :first()
```

---

### `:count()` → `integer`

Counts the rows.

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

Calculates the average.

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

### `:toSQL()` → `string, table`

Returns the generated SQL and parameters **without executing** the query.

```lua
local sql, params = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :toSQL()

print(sql)     -- SELECT * FROM users WHERE job = ? AND money > ?
print(params)  -- { "police", 500 }
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

### Statistics by job

```lua
local stats = User.query()
    :select("job, COUNT(*) as nb, AVG(money) as avg_money")
    :groupBy("job")
    :having("COUNT(*) >= ?", 2)
    :orderBy("avg_money", "DESC")
    :get()
```

### Players with profile (join)

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
