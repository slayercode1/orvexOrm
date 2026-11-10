---
sidebar_position: 2
---

# CRUD (Create, Read, Update, Delete)

CRUD is an acronym for the 4 basic operations you perform on a database:

- **C**reate
- **R**ead
- **U**pdate
- **D**elete

Throughout this page, we will use this model:

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

:::info Before you start
- All these calls wait for the database: they must run in a thread, an event or a command ([Async and threads](/docs/getting-started#async-and-threads)).
- Writes (`update`, `delete`, `increment`...) return the **number of affected rows** (`0` = nothing changed).
- The SQL shown here is simplified: in reality every column and table name is wrapped in backticks (`` `users`.`money` ``), which lets you use reserved words such as `group` or `key` as column names.
:::

---

## Create

### `Model.create(data)`

Inserts a new row into the database and returns an **instance**.

```lua
local player = User.create({
    identifier = "license:abc",
    money      = 500,
    job        = "unemployed",
})

-- "player" is an instance, you can use it right away
print(player.money)  -- 500
```

Your `data` table is not modified: the ORM works on a copy (you can reuse the same data template for several `create` calls). With an auto-increment primary key, the instance receives the generated id.

**Generated SQL:**
```sql
INSERT INTO users (identifier, job, money) VALUES (?, ?, ?)
```

### `Model.upsert(data)`

Inserts a row, **or updates it** if it already exists (based on the primary or a unique key).

Very handy to save data without worrying whether the player already exists:

```lua
-- If "license:abc" does not exist → INSERT
-- If "license:abc" already exists → UPDATE money
User.upsert({
    identifier = "license:abc",
    money      = 2000,
})
```

**Generated SQL:**
```sql
INSERT INTO users (identifier, money) VALUES (?, ?)
ON DUPLICATE KEY UPDATE identifier = VALUES(identifier), money = VALUES(money)
```

:::tip When should I use upsert?
Use `upsert` when you want to save data without knowing whether the row already exists. It is perfect for auto-save systems.
:::

:::info upsert and timestamps
With `timestamps = true`, `created_at` is not overwritten when the row already exists: only the other fields are updated.
:::

---

## Read

### `Model.find(where)`

Looks for **a single** row matching the conditions and returns an instance (or `nil`). The query carries a `LIMIT 1`.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    print(player.money)  -- 500
    print(player.job)    -- "unemployed"
else
    print("Player not found")
end
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE identifier = ? LIMIT 1
```

### `Model.findAll(where?)`

Looks for **every row** matching the conditions and returns a list. Without an argument, `User.findAll()` returns the whole table (like `User.all()`).

```lua
local cops = User.findAll({ job = "police" })

print(#cops .. " officers found")  -- "3 officers found"

for _, cop in ipairs(cops) do
    print(cop.identifier .. " has " .. cop.money .. "$")
end
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE job = ?
```

### `Model.findAll` with operators

You can use operators directly in `find()` and `findAll()`, as in the query builder, with `OrvexORM.op(operator, value)`:

```lua
-- Officers with more than 1000$
local richCops = User.findAll({
    job   = "police",
    money = OrvexORM.op(">", 1000),
})

-- Active players with a specific job
local players = User.findAll({
    job    = OrvexORM.op("IN", { "police", "medic", "firefighter" }),
    money  = OrvexORM.op("BETWEEN", { 500, 50000 }),
    status = OrvexORM.op("!=", "banned"),
})
```

A plain table as a value (the old `{ money = { ">", 1000 } }` syntax) raises an error: only a value created by `OrvexORM.op` is read as an operator, so a client's net-event argument cannot change the condition. See [Values coming from the client](/docs/guides/query-builder#values-coming-from-the-client).

:::info Difference between find and findAll
- `find()` returns **a single** result (the first) or `nil`
- `findAll()` returns **a list** (which can be empty `{}`)
:::

### `Model.all(opts?)`

Returns **every row** of the table. Shortcut for `findAll({}, opts)`.

```lua
local everyone = User.all()
print(#everyone .. " players in the database")
```

**Generated SQL:**
```sql
SELECT * FROM users
```

---

## Update

There are two ways to update data.

### Instance: `player:update(data)`

Updates **one specific player** you already fetched with `find()`.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    player:update({ money = 1000, job = "police" })

    -- The local object is updated too
    print(player.money)  -- 1000
    print(player.job)    -- "police"
end
```

**Generated SQL:**
```sql
UPDATE users SET job = ?, money = ? WHERE identifier = ?
```

### Class: `User.update(data, where)`

Updates rows **without fetching them first**. Faster when you do not need to read the data. Mind the order: **data first, `where` second** (`updateWhere` takes the reversed order).

```lua
-- Set every unemployed player to 0$
local n = User.update({ money = 0 }, { job = "unemployed" })
print(n .. " player(s) updated")

-- Change one player's job
if User.update({ job = "medic" }, { identifier = "license:abc" }) == 0 then
    print("Player not found")
end
```

The `where` is required and must not be empty: `User.update({ money = 0 }, {})` raises an error, so the whole table is never modified by accident. It accepts **equalities** only (string, boolean or finite number): an `OrvexORM.op` or a table raises an error there. The same goes for class-level `delete`, `forceDelete`, `restore`, `increment` / `decrement` and for the transactions' `tx:update` / `tx:delete`. For a condition with an operator, use `User.query():where(...)` and write each instance, or a parameterized `OrvexORM.rawExec` query. The `beforeBulkUpdate` / `afterBulkUpdate` hooks fire (not `beforeUpdate`, which receives an instance). On a `softDelete` model, class-level `update`, `increment` / `decrement` and `delete` leave rows already deleted alone (`deleted_at IS NULL` is added).

**Generated SQL:**
```sql
UPDATE users SET money = ? WHERE job = ?
```

### Which method to choose?

| Situation | Method |
|---|---|
| You already have the player object | `player:update()` |
| You want to update without reading first | `User.update()` |
| You want to update several rows at once | `User.update()` |

---

## Delete

### Instance: `player:delete()`

Deletes **one specific player**.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    player:delete()
    print("Player deleted!")
end
```

**Generated SQL:**
```sql
DELETE FROM users WHERE identifier = ?
```

### Class: `User.delete(where)`

Deletes rows **by condition**, without fetching them first. Returns the number of deleted rows and fires `beforeBulkDelete` / `afterBulkDelete`.

```lua
-- Delete every unemployed player
local n = User.delete({ job = "unemployed" })
```

**Generated SQL:**
```sql
DELETE FROM users WHERE job = ?
```

:::caution Watch out for bulk deletes
`User.delete({ job = "unemployed" })` deletes **every** matching row. Double-check your condition before running a bulk delete.
:::

---

## Advanced methods

### `findOrFail` — Find or error

Like `find()`, but raises an error if the player is not found. Useful when you are **sure** the row must exist.

```lua
local player = User.findOrFail({ identifier = "license:abc" })
-- If the player does not exist → error: "Record not found in 'users' where identifier=license:abc"

-- No need to check for nil!
print(player.money)
```

### `first` — First result

Shortcut to find the first matching record.

```lua
-- With a filter
local cop = User.first({ job = "police" })

-- Without a filter (first of the table)
local anyone = User.first()
```

### `exists` — Check existence

Returns `true` or `false` without loading the data. Faster than `find()`.

```lua
if User.exists({ identifier = "license:abc" }) then
    print("The player exists!")
end
```

### `pluck` — Extract a column

Returns an array with only the values of one column.

```lua
local jobs = User.pluck("job")
-- { "police", "medic", "firefighter", "unemployed" }

local moneys = User.pluck("money", { job = "police" })
-- { 1500, 3000, 800 }
```

### `toTable` — Send to the client

An instance carries internal fields and a metatable: it does not go through `TriggerClientEvent` or `json.encode` as is. Use `:toTable()` to get a flat copy, ready to send.

```lua
local player = User.find({ identifier = "license:abc" })
TriggerClientEvent("myresource:playerData", src, player:toTable())
```

### `refresh` — Reload from the database

Reloads an instance's columns from the database. Returns `false` if the row no longer exists. Like the instance's `update`, `delete`, `forceDelete`, `restore`, `increment` and `decrement`, it needs the primary key value: an instance loaded by a query builder `:select()` that does not include it raises an error instead of targeting another row.

```lua
if player:refresh() then
    print(player.money)  -- fresh data
end
```

### `updateWhere` / `deleteWhere` — Readable aliases

```lua
-- Same as User.update(data, where), but the where comes first
User.updateWhere({ identifier = "license:abc" }, { money = 9999 })

-- More readable than User.delete(where)
User.deleteWhere({ job = "unemployed" })
```

---

### `findOrCreate` — Find or create

```lua
local player, created = User.findOrCreate(
    { identifier = "license:abc" },        -- look up with these conditions
    { money = 500, job = "unemployed" }     -- default values on creation
)

if created then
    print("New player!")
else
    print("Existing player: " .. player.money .. "$")
end
```

### `updateOrCreate` — Update or create

```lua
local player, created = User.updateOrCreate(
    { identifier = "license:abc" },
    { money = 1000, job = "police" }
)
```

The `where` of `findOrCreate` and `updateOrCreate` is also the data of the created row: it accepts equalities only (an `OrvexORM.op` raises an error). With `softDelete`, the lookup does not see soft-deleted rows: a matching deleted row leads to a new row. Put a **unique index** on the `where` columns (for example `identifier`) to prevent duplicates.

### `createMany` — Bulk insert

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
-- SQL: INSERT INTO users (...) VALUES (...), (...), (...)
```

When the rows do not all have the same keys, `createMany` runs one `INSERT` per key set, all in a single transaction: no column is lost.

### `increment` / `decrement` — Increment / Decrement

```lua
-- On the class: update without fetching first
User.increment("money", 100, { identifier = "license:abc" })
User.decrement("money", 50, { identifier = "license:abc" })

-- On the instance: update a player you already have (amount = 1 by default)
player:increment("money", 100)
player:decrement("money", 50)
player:increment("kills")
-- SQL: UPDATE users SET money = money + ? WHERE identifier = ?
```

:::tip Prefer increment over update for counters
`player:update({ money = player.money + 100 })` writes a value computed from a read: if another write happened in between, it is overwritten. `increment` does the math inside MySQL (`money = money + ?`) and loses nothing. On the class, `amount` is **required**: `User.increment("money", 100, where)`. It must be a finite number: a string, `NaN` or infinity raise an error (convert an amount coming from the client with `tonumber` and bound it).
:::

---

## Soft Delete

If your model has `softDelete = true`, deletions set `deleted_at` instead of deleting the row.

```lua
local User = ORM.model("users", { ... }, { softDelete = true })

player:delete()          -- Sets deleted_at
player:forceDelete()     -- Really deletes
player:restore()         -- Restores (sets deleted_at back to NULL)
```

Queries using `find`, `findAll`, `first`, `count` and `query()` automatically exclude soft-deleted rows, including when you combine `orWhere` calls (the filter always stays applied). To read a deleted row with `find`, put an explicit condition on `deleted_at`, or use `withTrashed()`.

```lua
User.withTrashed():get()    -- Include deleted rows
User.onlyTrashed():get()    -- Only deleted rows
```

---

## Automatic timestamps

If your model has `timestamps = true`, `created_at` and `updated_at` are managed automatically.

```lua
local User = ORM.model("users", { ... }, { timestamps = true })

local p = User.create({ identifier = "license:abc", money = 500 })
-- created_at and updated_at are filled automatically

p:update({ money = 1000 })
-- updated_at is updated automatically
```

You do not need to declare `created_at` / `updated_at` (nor `deleted_at` with `softDelete`) in the model's fields: validation accepts them when the option is on. Dates are written in UTC, as `YYYY-MM-DD HH:MM:SS`.

---

## Summary

| Operation | Class method (`.`) | Instance method (`:`) |
|---|---|---|
| Create | `User.create(data)` | — |
| Create with relations | `User.createWith(data)` | — |
| Bulk create | `User.createMany(rows)` | — |
| Upsert | `User.upsert(data)` | — |
| Find or create | `User.findOrCreate(where, defaults)` | — |
| Update or create | `User.updateOrCreate(where, data)` | — |
| Read one | `User.find(where)` | — |
| Read one (or error) | `User.findOrFail(where)` | — |
| First result | `User.first(where?)` | — |
| Read many | `User.findAll(where, opts?)` | — |
| Read all | `User.all(opts?)` | — |
| Exists? | `User.exists(where)` | — |
| Extract column | `User.pluck(col, where?)` | — |
| Update | `User.update(data, where)` → affected rows | `player:update(data)` |
| Update (alias, where first) | `User.updateWhere(where, data)` | — |
| Delete | `User.delete(where)` | `player:delete()` |
| Delete (alias) | `User.deleteWhere(where)` | — |
| Delete (force) | `User.forceDelete(where)` | `player:forceDelete()` |
| Restore | `User.restore(where)` | `player:restore()` |
| Increment | `User.increment(col, n, where)` | `player:increment(col, n)` |
| Decrement | `User.decrement(col, n, where)` | `player:decrement(col, n)` |
| Reload | — | `player:refresh()` |
| Convert to table | — | `player:toTable()` |
| Read a column named like a method | — | `player:getAttribute(col)` |
