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
-- All police officers
User.query()
    :where({ job = "police" })
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

### Greater than / Less than

```lua
:where("money", ">", 1000)    -- greater than 1000
:where("money", ">=", 1000)   -- greater than or equal to 1000
:where("money", "<", 500)     -- less than 500
:where("money", "<=", 500)    -- less than or equal to 500
```

### Not equal to

```lua
:where({ status = { "!=", "banned" } })
-- SQL: WHERE status != ?
```

### LIKE (text search)

```lua
-- All jobs containing "poli"
:where({ job = { "LIKE", "%poli%" } })
-- SQL: WHERE job LIKE ?
```

The `%` is a wildcard that matches any text:
- `"%poli%"` — contains "poli" anywhere
- `"poli%"` — starts with "poli"
- `"%poli"` — ends with "poli"

### IN (among a list)

```lua
-- Police officers, medics, or firefighters
:where({ job = { "IN", { "police", "medic", "firefighter" } } })
-- SQL: WHERE job IN (?, ?, ?)
```

### BETWEEN (between two values)

```lua
-- Players with between $500 and $5000
:where({ money = { "BETWEEN", { 500, 5000 } } })
-- SQL: WHERE money BETWEEN ? AND ?
```

### IS NULL / IS NOT NULL

```lua
-- Players without a job
:where({ job = { "IS", "NULL" } })
-- SQL: WHERE job IS NULL

-- Players with a job
:where({ job = { "IS NOT", "NULL" } })
-- SQL: WHERE job IS NOT NULL
```

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

---

## Raw clauses with `:whereRaw()`

Sometimes you need a condition that `:where()` can't express (SQL functions, custom expressions). `:whereRaw()` lets you write the clause yourself. It's wrapped in parentheses and joined by **AND**:

```lua
-- Police officers, case-insensitive
User.query()
    :whereRaw("LOWER(job) = ?", { "police" })
    :get()
-- SQL: WHERE (LOWER(job) = ?)

-- Combined with other conditions
User.query()
    :where({ job = "police" })
    :whereRaw("money > ? OR kills > ?", { 1000, 50 })
    :get()
-- SQL: WHERE job = ? AND (money > ? OR kills > ?)
```

:::caution Never concatenate values
Always pass values through the `params` table (`?` placeholders). **Never** build the clause by string concatenation — that opens the door to SQL injection.

```lua
-- ❌ DANGEROUS: SQL injection possible
:whereRaw("job = '" .. input .. "'")

-- ✅ SAFE: value passed as a parameter
:whereRaw("job = ?", { input })
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
| `"ASC"` | Ascending (A to Z, 0 to 9). This is the default. |
| `"DESC"` | Descending (Z to A, 9 to 0) |

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

Example: page 3, 10 results per page -> `offset = (3-1) * 10 = 20`
:::

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
-- SQL: SELECT identifier, money FROM users WHERE job = ?
```

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
-- SELECT * FROM users WHERE job = ? AND money > ? ORDER BY money DESC LIMIT 5

print(params[1], params[2])
-- police    500
```

:::tip Useful for debugging
Use `:toSQL()` when something isn't working as expected. It shows you exactly what SQL query would be generated.
:::

---

## Full example

Here's a realistic example — a leaderboard system for the richest players:

```lua
-- Top 10 richest players who aren't banned
local top10 = User.query()
    :where({ status = { "!=", "banned" } })
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
