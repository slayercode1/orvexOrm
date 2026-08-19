---
sidebar_position: 2
---

# CRUD (Create, Read, Update, Delete)

CRUD is an acronym for the 4 basic operations you perform with a database:

- **C**reate
- **R**ead
- **U**pdate
- **D**elete

Throughout this page, we'll use this model:

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

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

-- "player" is an instance, you can use it directly
print(player.money)  -- 500
```

**Generated SQL:**
```sql
INSERT INTO users (identifier, job, money) VALUES (?, ?, ?)
```

### `Model.upsert(data)`

Inserts a row, **or updates it** if it already exists (based on the primary or unique key).

This is very useful for saving data without worrying about whether the player already exists:

```lua
-- If "license:abc" doesn't exist → INSERT
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

:::tip When to use upsert?
Use `upsert` when you want to save data without knowing whether the row already exists. It's perfect for automatic save systems.
:::

---

## Read

### `Model.find(where)`

Finds **a single** row matching the conditions and returns an instance (or `nil`).

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
SELECT * FROM users WHERE identifier = ?
```

### `Model.findAll(where)`

Finds **all rows** matching the conditions and returns a list.

```lua
local cops = User.findAll({ job = "police" })

print(#cops .. " police officers found")  -- "3 police officers found"

for _, cop in ipairs(cops) do
    print(cop.identifier .. " has " .. cop.money .. "$")
end
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE job = ?
```

:::info Difference between find and findAll
- `find()` returns **a single** result (the first one) or `nil`
- `findAll()` returns **a list** (which can be empty `{}`)
:::

### `Model.all()`

Returns **all rows** in the table. It's a shortcut for `findAll({})`.

```lua
local players = User.all()

print(#players .. " players in total")
```

**Generated SQL:**
```sql
SELECT * FROM users
```

### Sending data to a client

Instances contain internal fields and a metatable, so don't send them raw over the network. Use `instance:toTable()` to get a plain table:

```lua
local player = User.find({ identifier = "license:abc" })
TriggerClientEvent("myresource:playerData", src, player:toTable())
```

---

## Update

There are two ways to update data.

### Instance: `player:update(data)`

Updates **a specific player** that you've already retrieved with `find()`.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    player:update({ money = 1000, job = "police" })

    -- The local object is also updated
    print(player.money)  -- 1000
    print(player.job)    -- "police"
end
```

**Generated SQL:**
```sql
UPDATE users SET job = ?, money = ? WHERE identifier = ?
```

### Class: `User.update(data, where)`

Updates rows **without fetching them first**. Faster if you don't need to read the data.

```lua
-- Set all unemployed players to $0
User.update({ money = 0 }, { job = "unemployed" })

-- Change a specific player's job
User.update({ job = "medic" }, { identifier = "license:abc" })
```

**Generated SQL:**
```sql
UPDATE users SET money = ? WHERE job = ?
```

### Which method to choose?

| Situation | Method |
|---|---|
| You already have the player object | `player:update()` |
| You want to update without reading first | `User.update()` |
| You want to update multiple rows at once | `User.update()` |

---

## Delete

### Instance: `player:delete()`

Deletes **a specific player**.

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

Deletes rows **by condition**, without fetching them first.

```lua
-- Delete all unemployed players
User.delete({ job = "unemployed" })
```

**Generated SQL:**
```sql
DELETE FROM users WHERE job = ?
```

:::caution Beware of mass deletions
`User.delete({ job = "unemployed" })` deletes **all** matching rows. Double-check your condition before running a mass deletion.
:::

---

---

## Advanced methods

### `findOrCreate` — Find or create

```lua
local player, created = User.findOrCreate(
    { identifier = "license:abc" },        -- search with these conditions
    { money = 500, job = "unemployed" }     -- default values if creating
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

### `createMany` — Bulk insert

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
-- SQL: INSERT INTO users (...) VALUES (...), (...), (...)
```

### `increment` / `decrement`

```lua
-- On the class: update without fetching first
User.increment("money", 100, { identifier = "license:abc" })
User.decrement("money", 50, { identifier = "license:abc" })

-- On the instance: update a player you already have
player:increment("money", 100)
player:decrement("money", 50)
-- SQL: UPDATE users SET money = money + 100 WHERE identifier = ?
```

---

## Soft Delete

If your model has `softDelete = true`, deletions set `deleted_at` instead of actually deleting the row.

```lua
local User = ORM.model("users", { ... }, { softDelete = true })

player:delete()          -- Sets deleted_at
player:forceDelete()     -- Actually deletes
player:restore()         -- Restores (sets deleted_at back to NULL)
```

Queries using `find`, `findAll`, and `query()` automatically exclude soft-deleted rows.

```lua
User.withTrashed():get()    -- Include soft-deleted rows
User.onlyTrashed():get()    -- Only soft-deleted rows
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

---

## Summary

| Operation | Class method (`.`) | Instance method (`:`) |
|---|---|---|
| Create | `User.create(data)` | — |
| Create with relations | `User.createWith(data)` | — |
| Bulk insert | `User.createMany(rows)` | — |
| Upsert | `User.upsert(data)` | — |
| Find or create | `User.findOrCreate(where, defaults)` | — |
| Update or create | `User.updateOrCreate(where, data)` | — |
| Read one | `User.find(where)` | — |
| Read many | `User.findAll(where)` | — |
| Read all | `User.all()` | — |
| Update | `User.update(data, where)` | `player:update(data)` |
| Delete | `User.delete(where)` | `player:delete()` |
| Delete (force) | `User.forceDelete(where)` | `player:forceDelete()` |
| Restore | `User.restore(where)` | `player:restore()` |
| Increment | `User.increment(col, n, where)` | `player:increment(col, n)` |
| Decrement | `User.decrement(col, n, where)` | `player:decrement(col, n)` |
