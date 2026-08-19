---
sidebar_position: 2
---

# Model

All methods available on a model created with `ORM.model()`.

```lua
local User = ORM.model("users", { ... })
-- User is an OrvexModel
```

---

## CRUD

### `Model.create(data)` → `OrvexInstance`

Inserts a new row.

```lua
local player = User.create({ identifier = "license:abc", money = 500 })
```

---

### `Model.find(where, opts?)` → `OrvexInstance | nil`

Returns the first matching row, or `nil`.

```lua
local player = User.find({ identifier = "license:abc" })

-- With eager loading
local player = User.find({ identifier = "license:abc" }, {
    include = { "profile", "vehicles" }
})
```

---

### `Model.findAll(where, opts?)` → `OrvexInstance[]`

Returns all matching rows.

```lua
local cops = User.findAll({ job = "police" })
```

With `opts.include`, relations are eager-loaded in **batch**: a single `WHERE fk IN (...)` query per relation instead of one query per instance (no N+1). Works for `hasOne`, `hasMany`, and `belongsTo` (`belongsToMany` falls back to per-instance loading).

```lua
local cops = User.findAll({ job = "police" }, {
    include = { "vehicles" }
})
-- 2 queries total: 1 for users, 1 for all their vehicles
```

---

### `Model.all(opts?)` → `OrvexInstance[]`

Returns all rows in the table. Shortcut for `Model.findAll({}, opts)`.

```lua
local players = User.all()

-- With eager loading
local players = User.all({ include = { "vehicles" } })
```

---

### `Model.upsert(data)` → `boolean`

Inserts or updates if the primary key already exists.

```lua
User.upsert({ identifier = "license:abc", money = 2000 })
```

:::info
With `timestamps = true`, `created_at` is **not** overwritten when the row already exists — only the other fields are updated via `ON DUPLICATE KEY UPDATE`.
:::

---

### `Model.update(data, where)` → `boolean`

Updates the rows matching `where`.

```lua
User.update({ money = 0 }, { job = "unemployed" })
```

:::caution
The `where` parameter is **required** and must be non-empty to prevent updating the entire table.
:::

---

### `Model.delete(where)` → `boolean`

Deletes the rows matching `where`. If soft delete is enabled, marks the rows as deleted (sets `deleted_at`).

```lua
User.delete({ job = "unemployed" })
```

---

### `Model.createMany(rows)` → `boolean`

Inserts multiple rows in a single query.

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
```

---

### `Model.findOrCreate(where, defaults?)` → `OrvexInstance, boolean`

Finds a record, or creates it if it doesn't exist. Returns the instance and a `created` boolean.

```lua
local player, created = User.findOrCreate(
    { identifier = "license:abc" },        -- search condition
    { money = 500, job = "unemployed" }     -- default values if created
)

if created then
    print("New player created!")
end
```

---

### `Model.updateOrCreate(where, data)` → `OrvexInstance, boolean`

Updates an existing record, or creates a new one.

```lua
local player, created = User.updateOrCreate(
    { identifier = "license:abc" },   -- search condition
    { money = 1000, job = "police" }  -- data to update or create
)
```

---

### `Model.increment(column, amount, where)` → `boolean`

Increments a numeric column.

```lua
User.increment("money", 100, { identifier = "license:abc" })
-- SQL: UPDATE users SET money = money + 100 WHERE identifier = ?
```

---

### `Model.decrement(column, amount, where)` → `boolean`

Decrements a numeric column.

```lua
User.decrement("money", 50, { identifier = "license:abc" })
```

---

### `Model.forceDelete(where)` → `boolean`

Permanently deletes (ignores soft delete).

```lua
User.forceDelete({ identifier = "license:old" })
```

---

### `Model.restore(where)` → `boolean`

Restores soft-deleted rows.

```lua
User.restore({ identifier = "license:abc" })
```

---

### `Model.createWith(data)` → `OrvexInstance`

Creates a record with nested relations (nested writes). Relation keys are automatically detected.

```lua
-- Define relations
User.hasOne("profile", Profile, { foreignKey = "user_id" })
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })

-- Create with nested relations
local player = User.createWith({
    identifier = "license:abc",
    money      = 500,
    -- Nested hasOne
    profile = { bio = "Hello!", avatar = "avatar.png" },
    -- Nested hasMany
    vehicles = {
        { plate = "ABC123", model = "sultan" },
        { plate = "XYZ789", model = "adder" },
    },
})
```

This executes 4 queries:
1. `INSERT INTO users ...`
2. `INSERT INTO profiles (user_id, bio, avatar) ...`
3. `INSERT INTO vehicles (owner_id, plate, model) ...`
4. `INSERT INTO vehicles (owner_id, plate, model) ...`

---

### `Model.whereHas(relationName, callback?)` → `OrvexBuilder`

Filters records that have at least one related record. Uses `WHERE EXISTS` in SQL.

```lua
-- Players who have at least one vehicle
local players = User.whereHas("vehicles"):get()

-- Players who have a vehicle with plate "ABC123"
local players = User.whereHas("vehicles", function(b)
    b:where({ plate = "ABC123" })
end):get()
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE EXISTS (
    SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.identifier
)
```

---

### `Model.countByRelation(relationName, where?)` → `table`

Counts related records for each parent record. Uses a **single `GROUP BY` query** instead of one `COUNT` query per record.

```lua
local results = User.countByRelation("vehicles", { job = "police" })

for _, entry in ipairs(results) do
    print(entry.instance.identifier .. " has " .. entry.count .. " vehicle(s)")
end
-- Each instance also has a _count_vehicles field
```

---

## Query Builder

### `Model.query()` → `OrvexBuilder`

Returns a chainable query builder.

```lua
local results = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :limit(10)
    :get()
```

See the [full Builder reference](/docs/api/builder).

---

## Aggregations

### `Model.count(where?)` → `integer`

```lua
User.count()                    -- all
User.count({ job = "police" }) -- with filter
```

### `Model.sum(column, where?)` → `number`

```lua
User.sum("money")
User.sum("money", { job = "police" })
```

### `Model.avg(column, where?)` → `number`

```lua
User.avg("money", { job = "police" })
```

### `Model.min(column, where?)` → `any`

```lua
User.min("money")
```

### `Model.max(column, where?)` → `any`

```lua
User.max("money")
```

---

## Table

### `Model.sync()`

Creates the model's table if it doesn't exist. Automatically generates the `CREATE TABLE IF NOT EXISTS` SQL from the schema.

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

User.sync() -- Creates the "users" table if it doesn't exist
```

---

### `Model.flushCache()`

Flushes the cache for this model.

```lua
User.flushCache()
```

---

## Relations

### `Model.hasOne(name, relatedModel, opts)`

Defines a 1 → 1 relation.

| Option | Type | Description |
|---|---|---|
| `foreignKey` | `string` | Column on the **related** table |
| `localKey` | `string?` | Column on this table (default: primaryKey) |

```lua
User.hasOne("profile", Profile, { foreignKey = "user_id" })
```

---

### `Model.hasMany(name, relatedModel, opts)`

Defines a 1 → N relation.

| Option | Type | Description |
|---|---|---|
| `foreignKey` | `string` | Column on the **related** table |
| `localKey` | `string?` | Column on this table (default: primaryKey) |

```lua
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
```

---

### `Model.belongsTo(name, relatedModel, opts)`

Defines an N → 1 relation.

| Option | Type | Description |
|---|---|---|
| `foreignKey` | `string` | Column on **this** table |
| `ownerKey` | `string?` | Column on the related table (default: its primaryKey) |

```lua
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
```

---

### `Model.belongsToMany(name, relatedModel, opts)`

Defines an N → N relation via a pivot table.

| Option | Type | Description |
|---|---|---|
| `pivot` | `string` | Name of the pivot table **(required)** |
| `foreignKey` | `string` | Pivot column → this table |
| `otherKey` | `string` | Pivot column → related table |
| `localKey` | `string?` | Column on this table (default: primaryKey) |

```lua
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",
    foreignKey = "user_id",
    otherKey   = "role_id",
})
```

---

## Model Options

| Option | Type | Default | Description |
|---|---|---|---|
| `primaryKey` | `string` | `"id"` | Name of the primary key |
| `softDelete` | `boolean` | `false` | Enables soft delete (`deleted_at` column) |
| `timestamps` | `boolean` | `false` | Auto-manages `created_at` and `updated_at` |

```lua
local User = ORM.model("users", { ... }, {
    primaryKey = "identifier",
    softDelete = true,
    timestamps = true,
})
```

---

## Soft Delete

When `softDelete = true`, deletions mark the row with `deleted_at` instead of actually deleting it.

```lua
local User = ORM.model("users", { ... }, { softDelete = true })

-- Soft delete (sets deleted_at)
User.delete({ identifier = "license:abc" })

-- Permanently delete
User.forceDelete({ identifier = "license:abc" })

-- Restore a deleted record
User.restore({ identifier = "license:abc" })

-- Query builder: include deleted records
User.withTrashed():get()

-- Query builder: only deleted records
User.onlyTrashed():get()
```

---

## Hooks (Lifecycle)

Hooks allow you to execute code before/after CRUD operations.

```lua
User.beforeCreate(function(data)
    data.money = data.money or 500  -- default value
end)

User.afterCreate(function(instance)
    print("Player created: " .. instance.identifier)
end)

User.beforeUpdate(function(instance, data)
    print("Updating " .. instance.identifier)
end)

User.afterUpdate(function(instance)
    print("After update")
end)

User.beforeDelete(function(instance)
    print("Deleting " .. instance.identifier)
end)

User.afterDelete(function(instance)
    print("Deleted!")
end)
```

---

## Scopes

Scopes are reusable filters for the query builder.

```lua
-- Define a scope
User.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

User.scope("police", function(b)
    b:where({ job = "police" })
end)

-- Use a scope
local richPlayers = User.scoped("rich"):get()
local richCops = User.scoped("rich"):where({ job = "police" }):get()
```
