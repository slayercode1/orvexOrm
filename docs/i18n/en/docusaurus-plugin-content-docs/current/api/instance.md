---
sidebar_position: 3
---

# Instance

An **instance** is an object that represents one row of your database. You get one when you use `create()`, `find()`, or `query():get()`.

```lua
local player = User.find({ identifier = "license:abc" })
-- "player" is an OrvexInstance
```

You can access the columns like regular properties:

```lua
print(player.identifier)  -- "license:abc"
print(player.money)        -- 500
print(player.job)          -- "police"
```

An instance only holds the row's columns (plus the loaded relations and `_count_*` values): `pairs(player)` only walks your data. The methods and the model context are shared by every instance through a single metatable.

:::caution Columns named like a method
A column named like an instance method (`update`, `delete`, `get`, `refresh`, `restore`, `increment`, `toTable`...) no longer hides the method: `player:update()` always calls the method. Read the column's value with `player:getAttribute("update")`; `toTable()` includes it.
:::

Write methods return the **number of affected rows** (`0` if the row no longer exists), like the class methods. See the [conventions](/docs/api/model#conventions).

---

## Methods

### `instance:update(data)` → `integer`

Updates this row in the database and returns the affected row count. The local object is updated too. The data is validated, and `updated_at` is refreshed when `timestamps = true`. Fires `beforeUpdate(instance, data)` then `afterUpdate(instance)`. If `data` changes the primary key, the instance follows: later writes target the new value.

```lua
player:update({ money = 1000, job = "medic" })
print(player.money)  -- 1000 (updated locally too)
```

**Generated SQL:**
```sql
UPDATE `users` SET `job` = ?, `money` = ? WHERE `identifier` = ?
```

---

### `instance:delete()` → `integer`

Deletes this row from the database (or fills `deleted_at` when the model has `softDelete`). Fires `beforeDelete` / `afterDelete`.

```lua
player:delete()
```

**Generated SQL:**
```sql
DELETE FROM `users` WHERE `identifier` = ?
```

---

### `instance:get(relationName)` → `OrvexInstance | OrvexInstance[] | nil`

Fetches the data linked through a relation.

A query runs on every call (use `include` to load ahead). If the instance's linking key is `nil`, no query runs: `nil` for `hasOne`/`belongsTo`, `{}` for the multiple relations. Soft-deleted related rows are excluded.

The return type depends on the relation:

| Relation type | Return |
|---|---|
| `hasOne` | `OrvexInstance` or `nil` |
| `hasMany` | `OrvexInstance[]` (list) |
| `belongsTo` | `OrvexInstance` or `nil` |
| `belongsToMany` | `OrvexInstance[]` (list) |

```lua
-- hasOne → one instance
local profile = player:get("profile")

-- hasMany → a list
local vehicles = player:get("vehicles")

-- belongsTo → one instance
local owner = car:get("owner")

-- belongsToMany → a list
local roles = player:get("roles")
```

:::caution
The name passed to `:get()` must match exactly the name used when the relation was defined (`hasOne("profile", ...)` → `:get("profile")`).
:::

---

### `instance:attach(relationName, relatedInstance)` → `boolean`

Adds a link to the pivot table of a `belongsToMany` relation and invalidates the pivot table's cache. Returns `true`.

```lua
local adminRole = Role.find({ name = "admin" })
player:attach("roles", adminRole)
```

**Generated SQL:**
```sql
INSERT INTO user_roles (role_id, user_id) VALUES (?, ?)
```

:::caution
`attach` **only** works on `belongsToMany` relations. Using it on another relation raises an error.
:::

---

### `instance:detach(relationName, relatedInstance)` → `boolean`

Removes a link from the pivot table of a `belongsToMany` relation.

```lua
player:detach("roles", adminRole)
```

**Generated SQL:**
```sql
DELETE FROM user_roles WHERE role_id = ? AND user_id = ?
```

---

### `instance:increment(column, amount?)` → `integer`

Increments a numeric column on the MySQL side (`money = money + ?`). `amount` is optional (default: 1), whereas it is required on `Model.increment`. No hook fires; validation and `updated_at` do not apply.

```lua
player:increment("money", 100)
print(player.money)  -- updated locally too

player:increment("kills")  -- +1 by default
```

**Generated SQL:**
```sql
UPDATE `users` SET `money` = `money` + ? WHERE `identifier` = ?
```

---

### `instance:decrement(column, amount?)` → `integer`

Decrements a numeric column.

```lua
player:decrement("money", 50)
```

---

### `instance:forceDelete()` → `integer`

Deletes permanently, even when soft delete is enabled. Fires `beforeDelete` / `afterDelete`.

```lua
player:forceDelete()
```

---

### `instance:restore()` → `integer`

Restores a soft-deleted row. Requires `softDelete = true`. No hook fires.

```lua
player:restore()
print(player.deleted_at)  -- nil
```

---

### `instance:toTable()` → `table`

Returns a "flat" copy of the instance: a plain Lua table with every column (including those named like a method), without a metatable. Eager-loaded relations are converted recursively.

Main use case: sending the data to the client with `TriggerClientEvent` or serializing it with `json.encode`.

```lua
local player = User.find({ identifier = "license:abc" }, {
    include = { "vehicles" }
})

-- Send to the client (an instance does not go through as is)
TriggerClientEvent("myresource:playerData", src, player:toTable())

-- Or serialize to JSON
local jsonStr = json.encode(player:toTable())
```

:::tip Why toTable?
An instance has a metatable, which does not survive the network (msgpack): the methods would be lost, and a column named like a method would be missing. `toTable()` gives you a clean table, ready to send.
:::

---

### `instance:refresh()` → `boolean`

Reloads the instance's columns from the database. Returns `false` if the row no longer exists, `true` otherwise. JSON fields are decoded again.

```lua
local player = User.find({ identifier = "license:abc" })

-- Someone else changes the row...
User.update({ money = 9999 }, { identifier = "license:abc" })

-- Reload the fresh data
if player:refresh() then
    print(player.money)  -- 9999
else
    print("The row no longer exists")
end
```

---

### `instance:getAttribute(name)` → `any`

Reads a column, including a column named like an instance method (which `player[name]` would resolve to the method).

```lua
local Setting = ORM.model("settings", { id = "number", update = "string" })
local s = Setting.find({ id = 1 })
print(s:getAttribute("update"))  -- value of the `update` column
s:update({ update = "daily" })   -- still calls the method
```
