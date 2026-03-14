---
sidebar_position: 3
---

# Instance

An **instance** is an object that represents a row in your database. You get one when you use `create()`, `find()`, or `query():get()`.

```lua
local player = User.find({ identifier = "license:abc" })
-- "player" is an OrvexInstance
```

You can access columns as normal properties:

```lua
print(player.identifier)  -- "license:abc"
print(player.money)        -- 500
print(player.job)          -- "police"
```

---

## Methods

### `instance:update(data)` → `boolean`

Updates this row in the database. The local object is also updated.

```lua
player:update({ money = 1000, job = "medic" })
print(player.money)  -- 1000 (updated locally as well)
```

**Generated SQL:**
```sql
UPDATE users SET job = ?, money = ? WHERE identifier = ?
```

---

### `instance:delete()` → `boolean`

Deletes this row from the database.

```lua
player:delete()
```

**Generated SQL:**
```sql
DELETE FROM users WHERE identifier = ?
```

---

### `instance:get(relationName)` → `OrvexInstance | OrvexInstance[] | nil`

Retrieves related data through a relation.

The return type depends on the relation:

| Relation type | Return |
|---|---|
| `hasOne` | `OrvexInstance` or `nil` |
| `hasMany` | `OrvexInstance[]` (list) |
| `belongsTo` | `OrvexInstance` or `nil` |
| `belongsToMany` | `OrvexInstance[]` (list) |

```lua
-- hasOne → a single instance
local profile = player:get("profile")

-- hasMany → a list
local vehicles = player:get("vehicles")

-- belongsTo → a single instance
local owner = car:get("owner")

-- belongsToMany → a list
local roles = player:get("roles")
```

:::caution
The name passed to `:get()` must match exactly the name used when defining the relation (`hasOne("profile", ...)` → `:get("profile")`).
:::

---

### `instance:attach(relationName, relatedInstance)` → `boolean`

Adds a link in the pivot table of a `belongsToMany` relation.

```lua
local adminRole = Role.find({ name = "admin" })
player:attach("roles", adminRole)
```

**Generated SQL:**
```sql
INSERT INTO user_roles (role_id, user_id) VALUES (?, ?)
```

:::caution
`attach` **only** works on `belongsToMany` relations. If you use it on another relation, an error will be thrown.
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

### `instance:increment(column, amount?)` → `boolean`

Increments a numeric column. `amount` is optional (default: 1).

```lua
player:increment("money", 100)
print(player.money)  -- updated locally as well

player:increment("kills")  -- +1 by default
```

**Generated SQL:**
```sql
UPDATE users SET money = money + 100 WHERE identifier = ?
```

---

### `instance:decrement(column, amount?)` → `boolean`

Decrements a numeric column.

```lua
player:decrement("money", 50)
```

---

### `instance:forceDelete()` → `boolean`

Permanently deletes the row, even if soft delete is enabled.

```lua
player:forceDelete()
```

---

### `instance:restore()` → `boolean`

Restores a soft-deleted row. Requires `softDelete = true`.

```lua
player:restore()
print(player.deleted_at)  -- nil
```
