---
sidebar_position: 3
---

# Query Builder

The **Query Builder** lets you build advanced queries by chaining methods. It's like building a sentence piece by piece.

## The principle

Instead of writing SQL by hand, you chain methods:

```lua
-- Instead of:
-- SELECT * FROM users WHERE job = 'police' AND money > 1000 ORDER BY money DESC LIMIT 10

-- You write:
local results = User.query()
    :where({ job = "police" })
    :where("money", ">", 1000)
    :orderBy("money", "DESC")
    :limit(10)
    :get()
```

Each method adds a piece to the query. At the end, `:get()` executes the query and returns the results.

---

## Filtering with `:where()`

### Simple equality

```lua
-- All police officers (table)
User.query()
    :where({ job = "police" })
    :get()
-- SQL: WHERE job = ?

-- Or as a shortcut (2 arguments, implicit =)
User.query()
    :where("job", "police")
    :get()
-- SQL: WHERE job = ?
```

### With an operator

```lua
-- Players with more than $1000
User.query()
    :where("money", ">", 1000)
    :get()
-- SQL: WHERE money > ?
```

### Combining multiple conditions

```lua
-- Police officers with more than $1000
User.query()
    :where({ job = "police" })
    :where("money", ">", 1000)
    :get()
-- SQL: WHERE job = ? AND money > ?
```

When you chain multiple `:where()` calls, they are joined by **AND** (both conditions must be true).

---

## All operators

An operator can be written two ways: with 3 arguments (`:where("money", ">", 1000)`), or inside a table of conditions with `OrvexORM.op(operator, value)`:

```lua
User.query():where({ job = "police", money = OrvexORM.op(">", 1000) }):get()
-- SQL: WHERE `job` = ? AND `money` > ?
```

In a table, a plain value is an equality; only a value built by `OrvexORM.op` is read as an operator. An ordinary table (`{ money = { ">", 1000 } }`, the old syntax) **raises an error**. The same rule applies to `orWhere`, and to the table-form `where` of `find`, `findAll`, `findOrFail`, `first`, `exists`, `count`, `pluck`, the aggregates, `countByRelation` and scopes.

### Greater than / Less than

```lua
:where("money", ">", 1000)    -- greater than 1000
:where("money", ">=", 1000)   -- greater than or equal to 1000
:where("money", "<", 500)     -- less than 500
:where("money", "<=", 500)    -- less than or equal to 500
```

### Not equal to

```lua
:where("status", "!=", "banned")
:where({ status = OrvexORM.op("!=", "banned") })  -- same condition, table form
-- SQL: WHERE status != ?
```

### LIKE (text search)

```lua
-- All jobs containing "poli"
:where({ job = OrvexORM.op("LIKE", "%poli%") })
-- SQL: WHERE job LIKE ?
```

The `%` is a wildcard that matches any text:
- `"%poli%"` → contains "poli" anywhere
- `"poli%"` → starts with "poli"
- `"%poli"` → ends with "poli"

### IN (among a list)

```lua
-- Police officers, medics, or firefighters
:where({ job = OrvexORM.op("IN", { "police", "medic", "firefighter" }) })
-- SQL: WHERE job IN (?, ?, ?)
```

### BETWEEN (between two values)

```lua
-- Players with between $500 and $5000
:where({ money = OrvexORM.op("BETWEEN", { 500, 5000 }) })
-- SQL: WHERE money BETWEEN ? AND ?
```

### IS NULL / IS NOT NULL

```lua
-- Players without a job
:where({ job = OrvexORM.op("IS", "NULL") })   -- or :whereNull("job")
-- SQL: WHERE job IS NULL

-- Players with a job
:where({ job = OrvexORM.op("IS NOT", "NULL") })   -- or :whereNotNull("job")
-- SQL: WHERE job IS NOT NULL
```

---

### Shortcuts for common filters

Instead of `{ col = OrvexORM.op("OP", val) }`, you can use dedicated methods:

```lua
-- whereIn: among a list of values
User.query():whereIn("job", { "police", "medic", "fire" }):get()

-- whereNotIn: not in the list
User.query():whereNotIn("id", { 1, 2, 3 }):get()

-- whereBetween: between two values
User.query():whereBetween("money", 500, 5000):get()

-- whereNotBetween: outside the range
User.query():whereNotBetween("money", 0, 100):get()

-- whereLike: text search
User.query():whereLike("name", "%john%"):get()
```

---

## Values coming from the client

A condition value (`where`, `orWhere`, `IN` / `BETWEEN` elements, `after` / `before` cursors) must be a **string, a boolean or a finite number**. A table, `nil`, `NaN` or infinity raise an error before the query is sent.

Never forward a net-event argument as is into a `where`: a client can send a table instead of the expected string. Convert and check it first:

```lua
RegisterNetEvent("garage:spawn", function(plate)
    local src = source
    if type(plate) ~= "string" or #plate > 8 then return end  -- reject everything else
    local vehicle = Vehicle.find({ plate = plate, owner = GetPlayerIdentifier(src, 0) })
    -- ...
end)
```

A client cannot forge an operator either: an argument decoded from the network can be shaped like `{ "LIKE", "%" }`, but only a value created by `OrvexORM.op` on the server is read as an operator. `User.find({ identifier = payload })` with a table therefore raises an error instead of becoming `identifier LIKE '%'`.

---

## Raw SQL with `:whereRaw()`

When no method covers your need, `:whereRaw(clause, params?)` lets you write a raw SQL clause. It is wrapped in parentheses and joined with the other conditions by **AND**.

```lua
-- SQL function in the condition
User.query()
    :whereRaw("LOWER(job) = ?", { "police" })
    :get()
-- SQL: WHERE (LOWER(job) = ?)

-- OR nested inside a group
User.query()
    :where({ status = "active" })
    :whereRaw("money > ? OR job = ?", { 10000, "police" })
    :get()
-- SQL: WHERE status = ? AND (money > ? OR job = ?)
```

:::caution SQL injection
**Always** pass values through `params`, never by string concatenation. `:whereRaw("name = '" .. input .. "'")` is an open door to SQL injection.
:::

---

## OR WHERE

By default, conditions are joined by **AND**. To use **OR**:

```lua
-- Police officers OR medics
User.query()
    :where({ job = "police" })
    :orWhere({ job = "medic" })
    :get()
-- SQL: WHERE job = ? OR job = ?
```

```lua
-- Police officers OR medics OR firefighters
User.query()
    :where({ job = "police" })
    :orWhere({ job = "medic" })
    :orWhere({ job = "firefighter" })
    :get()
-- SQL: WHERE job = ? OR job = ? OR job = ?
```

On a model with `softDelete`, your conditions are **grouped in parentheses** after the soft delete filter: an `orWhere` cannot bring deleted rows back.

```sql
WHERE deleted_at IS NULL AND (job = ? OR job = ? OR job = ?)
```

:::caution AND binds before OR
Conditions are joined in call order and MySQL evaluates `AND` before `OR`:

```lua
User.query():where("money", ">", 1000):where("job", "police"):orWhere("job", "medic")
-- WHERE money > ? AND job = ? OR job = ?
-- = (more than 1000 AND officer) OR medic (whatever their money)
```

For "more than $1000 AND (officer OR medic)", group it yourself:

```lua
User.query()
    :where("money", ">", 1000)
    :whereRaw("(job = ? OR job = ?)", { "police", "medic" })
-- or simpler here: :whereIn("job", { "police", "medic" })
```
:::

---

## Sorting with `:orderBy()`

```lua
-- From richest to poorest
User.query()
    :orderBy("money", "DESC")
    :get()
-- SQL: ORDER BY money DESC

-- Alphabetical order by job
User.query()
    :orderBy("job")  -- ASC by default
    :get()
-- SQL: ORDER BY job ASC
```

| Direction | Meaning |
|---|---|
| `"ASC"` | Ascending (A → Z, 0 → 9). This is the default. |
| `"DESC"` | Descending (Z → A, 9 → 0) |

### Sorting shortcuts

```lua
-- Shortcuts without giving the direction
User.query():orderByDesc("money"):get()   -- ORDER BY money DESC
User.query():orderByAsc("name"):get()     -- ORDER BY name ASC

-- Newest / oldest first (uses created_at by default)
User.query():latest():get()               -- ORDER BY created_at DESC
User.query():oldest():get()               -- ORDER BY created_at ASC

-- With a custom column
User.query():latest("updated_at"):get()   -- ORDER BY updated_at DESC
```

---

## Paginating with `:limit()` and `:offset()`

Pagination lets you display results by "pages".

```lua
-- Page 1: the first 10 results
User.query()
    :limit(10)
    :offset(0)
    :get()

-- Page 2: the next 10
User.query()
    :limit(10)
    :offset(10)
    :get()

-- Page 3
User.query()
    :limit(10)
    :offset(20)
    :get()
```

:::tip Pagination formula
For a given page:
- `limit` = number of results per page
- `offset` = (page number - 1) * limit

Example: page 3, 10 results per page → `offset = (3-1) * 10 = 20`

`limit` and `offset` only accept non-negative integers (or numeric strings such as `"20"`). Any other value raises an error: you can pass them a page number coming from the client without injection risk, but still convert and clamp it (`math.min(tonumber(x) or 1, 100)`).
:::

### Shortcut: `:paginate(page, perPage)`

Instead of computing limit/offset yourself, use `:paginate()`:

```lua
local page = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :paginate(2, 10)

print(page.total)     -- total number of results (e.g. 25)
print(page.page)      -- 2
print(page.perPage)   -- 10
print(page.lastPage)  -- 3 (ceil(25/10))
print(#page.data)     -- 10 (the results of page 2)

for _, player in ipairs(page.data) do
    print(player.identifier .. " — " .. player.money .. "$")
end
```

| Field | Type | Description |
|---|---|---|
| `data` | `OrvexInstance[]` | The results of the page |
| `total` | `integer` | Total number of records |
| `page` | `integer` | Current page number |
| `perPage` | `integer` | Number of items per page (default: 15) |
| `lastPage` | `integer` | Number of the last page |

`page` and `perPage` must be positive integers; a page so large that the `OFFSET` would overflow raises an error.

### Shortcut: `:first()`

If you just want the **first** result:

```lua
local richest = User.query()
    :orderBy("money", "DESC")
    :first()
-- Automatically adds LIMIT 1

if richest then
    print(richest.identifier .. " is the richest with " .. richest.money .. "$")
end
```

---

## Joins

Joins let you **combine data from multiple tables** in a single query.

### LEFT JOIN

Returns all rows from the main table, even if they have no match in the joined table.

```lua
-- All players, with their profile (if they have one)
User.query()
    :select("users.*, profiles.bio")
    :leftJoin("profiles", "profiles.user_id", "users.identifier")
    :get()
-- SQL: SELECT users.*, profiles.bio FROM users
--      LEFT JOIN profiles ON profiles.user_id = users.identifier
```

### INNER JOIN

Returns **only** the rows that have a match in both tables.

```lua
-- Only players who have at least one vehicle
User.query()
    :select("users.identifier, vehicles.plate")
    :innerJoin("vehicles", "vehicles.owner_id", "users.identifier")
    :get()
```

### RIGHT JOIN

The opposite of LEFT JOIN — returns all rows from the joined table.

```lua
Vehicle.query()
    :select("vehicles.*, users.identifier as owner_name")
    :rightJoin("users", "users.identifier", "vehicles.owner_id")
    :get()
```

:::info Which join to choose?
- **LEFT JOIN**: "I want all players, with or without a vehicle"
- **INNER JOIN**: "I want only players who have a vehicle"
- **RIGHT JOIN**: rarely used, prefer LEFT JOIN by swapping the tables
:::

:::caution Columns of joined tables
On a model query with a join, the default select is `users.*` (the model's table), not `*`: a same-named column (`id`...) of the joined table cannot overwrite the instance's primary key. To read columns of the joined table, list them with `:select()`, as in the examples above.
:::

---

## GROUP BY and HAVING

### GROUP BY

Groups results by a column, useful with aggregation functions.

```lua
-- Count the number of players per job
User.query()
    :select("job, COUNT(*) as nb_players")
    :groupBy("job")
    :get()
-- Result: { { job = "police", nb_players = 5 }, { job = "medic", nb_players = 3 } }
```

### HAVING

Filters groups (like WHERE, but for groups).

```lua
-- Only jobs with more than 5 players
User.query()
    :select("job, COUNT(*) as nb_players")
    :groupBy("job")
    :having("COUNT(*) > ?", 5)
    :get()
```

---

## Selecting specific columns

By default, OrvexORM selects all columns (`*`). You can choose which ones:

```lua
-- Only identifier and money
User.query()
    :select("identifier, money")
    :where({ job = "police" })
    :get()
-- SQL: SELECT `identifier`, `money` FROM `users` WHERE `job` = ?
```

Plain names are quoted, expressions (`COUNT(*) AS nb`) are kept as is. Never build this string from player input. Note: `:select()` takes a **string**, whereas the `select` option of `find` / `findAll` takes an **array** (`{ "identifier", "money" }`).

---

## Debugging with `:toSQL()`

You can see the generated SQL without executing the query:

```lua
local sql, params = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :orderBy("money", "DESC")
    :limit(5)
    :toSQL()

print(sql)
-- SELECT * FROM `users` WHERE `job` = ? AND `money` > ? ORDER BY `money` DESC LIMIT 5

print(params[1], params[2])
-- police    500
```

:::tip Useful for debugging
Use `:toSQL()` when something isn't working as expected. It shows you exactly what SQL query would be generated.
:::

---

## Utility methods

### `:pluck(column)` — Extract a column

Returns an array with only the values of one column, without building instances.

```lua
local jobs = User.query():pluck("job")
-- { "police", "medic", "firefighter" }

local richJobs = User.query():where("money", ">", 10000):pluck("job")
```

### `:exists()` — Check existence

Returns `true` or `false` without loading the data. Faster than `:get()`.

```lua
local hasCops = User.query():where("job", "police"):exists()
if hasCops then
    print("There are officers!")
end
```

### `:chunkById(size, callback, column?)` — Batch processing (recommended)

Processes the results in batches to avoid loading everything into memory. Each batch resumes after the last key seen (`WHERE id > ? ORDER BY id LIMIT 100`): the cost is the same for the first and the thousandth batch, and changing or deleting rows in the callback skips no row.

```lua
-- Process every player in batches of 100, on their primary key
User.query():chunkById(100, function(players, chunkIndex)
    print("Batch " .. chunkIndex .. ": " .. #players .. " players")
    for _, player in ipairs(players) do
        player:update({ money = 0 })
    end
    -- Return false to stop
end, "identifier")  -- unique column; "id" by default
```

A `:limit(n)` set on the builder caps the total number of rows scanned. `chunkById` refuses `:offset()` (a keyset page skips no rows): filter with `:where(column, ">", key)` instead.

### `:chunk(size, callback)` — Batch processing (OFFSET)

Same idea with `LIMIT` / `OFFSET`. Simpler, but MySQL rereads every previous row for each batch (slow on a large table), and if the callback changes rows so that they no longer match the filter, rows are **skipped**. Keep it for small read-only tables.

```lua
User.query():chunk(100, function(players, chunkIndex)
    for _, player in ipairs(players) do
        print(player.identifier)
    end
end)
```

Here too, a `:limit(n)` caps the total number of rows scanned, and the scan starts at the builder's `:offset()`.

---

## Full example

Here's a realistic example — a leaderboard of the richest players:

```lua
-- Top 10 richest players who aren't banned
local top10 = User.query()
    :where({ status = OrvexORM.op("!=", "banned") })
    :where("money", ">", 0)
    :orderBy("money", "DESC")
    :limit(10)
    :get()

for i, player in ipairs(top10) do
    print(("#%d — %s : %d$"):format(i, player.identifier, player.money))
end
-- #1 — license:xyz : 50000$
-- #2 — license:abc : 35000$
-- ...
```
