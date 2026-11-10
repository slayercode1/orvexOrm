---
sidebar_position: 2
---

# Model

All the methods available on a model created with `ORM.model()`.

```lua
local User = ORM.model("users", { ... })
-- User is an OrvexModel
```

---

## Conventions

These rules apply to every method on this page.

### Return values

| Family | Return |
|---|---|
| `update`, `updateWhere`, `delete`, `deleteWhere`, `forceDelete`, `restore`, `increment`, `decrement` | `integer`: the number of rows the driver reports as affected. `0` = nothing changed (no row matched). A number is always "truthy" in Lua: test `n > 0`, not `if n then`. |
| `create`, `createWith` | The created instance |
| `createMany`, `upsert` | `true` (an `INSERT` returns an id, not a row count) |
| `find`, `first`, `findOrFail` | An instance, or `nil` (`findOrFail` raises an error) |
| `findAll`, `all` | A list, possibly empty `{}` |

### Errors

Misuse **raises a Lua error** whose position points at **your** line of code (not inside the library):

- `update` / `delete` / `forceDelete` / `restore` / `increment` / `decrement` without a `where` (or with `{}`): `update() requires a where clause`. This is on purpose, so the whole table is never hit by accident.
- Invalid data (wrong type, unknown column): see [Validation](/docs/guides/validation). When several fields are invalid, the one reported is the first in alphabetical order, always the same.
- `restore` on a model without `softDelete`; unknown relation; invalid SQL identifier.

A SQL error reported by the driver is a Lua error too. Use `pcall` to catch them.

### Conditions (`where`)

- In a `{ column = value }` table, every value is an **equality**. An operator is written `OrvexORM.op(operator, value)`: `{ money = OrvexORM.op(">", 100) }`. A plain table (the old `{ money = { ">", 100 } }` syntax) raises an error.
- `OrvexORM.op` is accepted by `find`, `findAll`, `findOrFail`, `first`, `exists`, `count`, `pluck`, `sum` / `avg` / `min` / `max`, `countByRelation` and the query builder (so scopes too).
- `update` / `updateWhere`, `delete` / `deleteWhere`, `forceDelete`, `restore`, `increment` / `decrement`, `findOrCreate` and `updateOrCreate` accept equalities only: an `OrvexORM.op` raises an error there.
- A value must be a string, a boolean or a finite number (no table, `NaN` or infinity). Never pass a client's net-event argument without converting it: see [Values coming from the client](/docs/guides/query-builder#values-coming-from-the-client).

### Argument order

The API has a few historical irregularities, kept for backward compatibility:

| Methods | Order |
|---|---|
| `update(data, where)` | **data** then where (like `instance:update(data)`) |
| `updateWhere(where, data)` | **where** then data (alias of `update`, reversed order) |
| `count(where?)` | **where** only |
| `sum / avg / min / max(column, where?)` | **column** then where |
| `increment / decrement(column, amount, where)` | `amount` **required** (on the instance, `instance:increment(column, amount?)` defaults to 1) |
| `find(where?, opts?)` / `findAll(where?, opts?)` | `where` optional: `findAll()` = the whole table, `find()` = the first row |
| Column selection | `opts.select` of `find`/`findAll` takes an **array** (`{ "identifier", "money" }`) or a comma-separated string (`"identifier, money"`); the builder's `:select()` takes a **string** |

### Async

Every method that reads or writes waits for the database: call it from a thread, an event or a command ([Async and threads](/docs/getting-started#async-and-threads)). Defining a model, a relation, a scope or a hook runs no query.

### The caller's data is not modified

`create`, `createMany`, `upsert`, `update` and the `before*` hooks work on a **copy** of your table: you can reuse a data template without it receiving `created_at` or a hook's changes.

---

## CRUD

### `Model.create(data)` → `OrvexInstance`

Inserts a new row.

```lua
local player = User.create({ identifier = "license:abc", money = 500 })
```

---

### `Model.find(where?, opts?)` → `OrvexInstance | nil`

Returns the first matching row, or `nil`. The query carries a `LIMIT 1`. `where` accepts operators (`{ money = OrvexORM.op(">", 100) }`); without `where`, returns the first row of the table.

| Option | Type | Description |
|---|---|---|
| `include` | `string[]` | Relations to load at the same time (eager loading) |
| `select` | `string[]` or `string` | Columns to read (plain names, validated and quoted; a string is split on commas); the primary key is always added |

```lua
local player = User.find({ identifier = "license:abc" })

-- With eager loading
local player = User.find({ identifier = "license:abc" }, {
    include = { "profile", "vehicles" }
})
```

---

### `Model.findAll(where?, opts?)` → `OrvexInstance[]`

Returns all matching rows (`{}` if none). Without `where`, returns the whole table. Same options as `find`.

```lua
local cops = User.findAll({ job = "police" })
```

With `opts.include`, relations are loaded with **batched eager loading**: a single query per relation, whatever the number of results (no N+1 problem). `hasOne`, `hasMany` and `belongsTo` use `WHERE fk IN (...)`, `belongsToMany` a single join on the pivot table for all parents.

```lua
local cops = User.findAll({ job = "police" }, {
    include = { "profile", "vehicles" }
})

for _, cop in ipairs(cops) do
    print(cop.profile.bio)   -- already loaded
    print(#cop.vehicles)     -- already loaded
end
```

---

### `Model.all(opts?)` → `OrvexInstance[]`

Returns every row of the table. Shortcut for `Model.findAll({}, opts)`.

```lua
local everyone = User.all()

-- With eager loading
local everyone = User.all({ include = { "vehicles" } })
```

---

### `Model.upsert(data)` → `boolean`

Inserts, or updates if the primary key (or a unique key) already exists. With `timestamps = true`, `created_at` is **not** overwritten on existing rows: only the other fields are updated through `ON DUPLICATE KEY UPDATE`. Fires `beforeUpsert(data)` then `afterUpsert(data)`.

```lua
User.upsert({ identifier = "license:abc", money = 2000 })
```

---

### `Model.update(data, where)` → `integer`

Updates the rows matching `where` and returns the affected row count. Fires `beforeBulkUpdate(data, where)` then `afterBulkUpdate(data, where, affected)`. With `softDelete`, soft-deleted rows are left alone (`AND deleted_at IS NULL`), unless `where` itself holds `deleted_at`. `data` cannot hold `deleted_at`, nor `created_at` / `updated_at` without `allowManagedColumns` (see [Validation](/docs/guides/validation#columns-managed-by-the-orm)).

```lua
local n = User.update({ money = 0 }, { job = "unemployed" })
print(n .. " player(s) reset")
```

:::caution
The `where` parameter is **required** and must be non-empty, so the whole table is never modified by accident.
:::

---

### `Model.delete(where)` → `integer`

Deletes the rows matching `where` and returns the affected row count. If soft delete is enabled, marks the rows as deleted (sets `deleted_at`); a row already deleted keeps its deletion date (`AND deleted_at IS NULL`). Fires `beforeBulkDelete(where)` then `afterBulkDelete(where, affected)`.

```lua
User.delete({ job = "unemployed" })
```

---

### `Model.createMany(rows)` → `boolean`

Inserts several rows in a single query. When the rows do not all have the same keys, one `INSERT` runs per key set, all in a single transaction (no column is lost). Every row is validated; `beforeCreate` fires for each row (on a copy), then `afterBulkCreate(rows)` once. No instance is built.

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
```

---

### `Model.findOrCreate(where, defaults?)` → `OrvexInstance, boolean`

Looks up a record, or creates it (with `where` + `defaults`) if it does not exist. Returns the instance and a `created` boolean. `where` accepts equalities only, since it is also the data of the created row. It is not atomic: two simultaneous calls can both create the row unless a unique key prevents it. With `softDelete`, the lookup does not see soft-deleted rows: a matching "deleted" row leads to a **new** row. Put a unique index on the `where` columns so a duplicate raises an error instead of being inserted (the same goes for `updateOrCreate`).

```lua
local player, created = User.findOrCreate(
    { identifier = "license:abc" },        -- lookup condition
    { money = 500, job = "unemployed" }     -- default values on creation
)

if created then
    print("New player created!")
end
```

---

### `Model.updateOrCreate(where, data)` → `OrvexInstance, boolean`

Updates an existing record (through `instance:update`, so `beforeUpdate`/`afterUpdate`), or creates a new one (`beforeCreate`/`afterCreate`). As with `findOrCreate`, the lookup ignores soft-deleted rows: a unique index prevents duplicates.

```lua
local player, created = User.updateOrCreate(
    { identifier = "license:abc" },   -- lookup condition
    { money = 1000, job = "police" }  -- data to update or create
)
```

---

### `Model.increment(column, amount, where)` → `integer`

Increments a numeric column, atomically on the MySQL side (`money = money + ?`). `amount` is required and must be a finite number (a string, `NaN` or infinity raise an error). With `softDelete`, soft-deleted rows are left alone (as with `decrement`). No hook fires.

```lua
User.increment("money", 100, { identifier = "license:abc" })
-- SQL: UPDATE `users` SET `money` = `money` + ? WHERE `identifier` = ?
```

---

### `Model.decrement(column, amount, where)` → `integer`

Decrements a numeric column (`amount` required, no hook).

```lua
User.decrement("money", 50, { identifier = "license:abc" })
```

---

### `Model.findOrFail(where, opts?)` → `OrvexInstance`

Like `find()`, but raises an error if no record is found.

```lua
local player = User.findOrFail({ identifier = "license:abc" })
-- Error if not found: "Record not found in 'users' where identifier=license:abc"
```

---

### `Model.first(where?)` → `OrvexInstance | nil`

Returns the first matching record. Shortcut for `query():where(...):first()`.

```lua
local cop = User.first({ job = "police" })
local anyone = User.first()  -- first of the table
```

---

### `Model.exists(where)` → `boolean`

Checks whether a record exists without loading the data.

```lua
if User.exists({ identifier = "license:abc" }) then
    print("The player exists")
end
```

---

### `Model.pluck(column, where?)` → `any[]`

Returns an array with only the values of one column.

```lua
local jobs = User.pluck("job")                         -- every job
local moneys = User.pluck("money", { job = "police" }) -- officers' money
```

---

### `Model.updateWhere(where, data)` → `integer`

Alias of `update(data, where)` with the arguments **in reversed order** (where first). Same hooks and same return value.

```lua
User.updateWhere({ identifier = "license:abc" }, { money = 9999 })
```

---

### `Model.deleteWhere(where)` → `integer`

Alias of `delete(where)`.

```lua
User.deleteWhere({ job = "unemployed" })
```

---

### `Model.forceDelete(where)` → `integer`

Deletes permanently (ignores soft delete). Fires the `beforeBulkDelete` / `afterBulkDelete` hooks.

```lua
User.forceDelete({ identifier = "license:old" })
```

---

### `Model.restore(where)` → `integer`

Restores soft-deleted rows (sets `deleted_at` back to `NULL`). Requires `softDelete = true` and a non-empty `where`. No hook fires.

```lua
User.restore({ identifier = "license:abc" })
```

---

### `Model.createWith(data)` → `OrvexInstance`

Creates a record with nested relations (nested writes). Relation keys are detected automatically.

:::danger Never raw client data
**Any** key of `data` named like a relation is treated as a nested write: a client that adds `roles = { { name = "admin" } }` to its table creates related rows. Never pass a table received from a client to `createWith` unfiltered: copy only the fields you expect.
:::

```lua
-- Define the relations
User.hasOne("profile", Profile, { foreignKey = "user_id" })
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })

-- Create with nested relations
local player = User.createWith({
    identifier = "license:abc",
    money      = 500,
    -- Nested hasOne
    profile = { bio = "Hi!", avatar = "avatar.png" },
    -- Nested hasMany
    vehicles = {
        { plate = "ABC123", model = "sultan" },
        { plate = "XYZ789", model = "adder" },
    },
})
```

How it runs:
1. Every nested row is **validated first**: invalid data writes nothing.
2. `INSERT INTO users ...` (through `create`, so with its hooks).
3. The `hasOne` / `hasMany` rows receive the foreign key, go through their model's `beforeCreate` hooks (on a copy, once per row), then are sent in **a single transaction**, as multi-row `INSERT`s (one query per table): here `INSERT INTO profiles ...` and `INSERT INTO vehicles ... VALUES (...), (...)`.
4. For `belongsToMany`, each related row is created with `create` (its id is needed, so its hooks fire), then the pivot rows are inserted in the same transaction.
5. Once the transaction is committed, `afterBulkCreate(rows)` fires once per `hasOne` / `hasMany` relation on the child model. `afterCreate` does **not** fire for those rows: no instance is built (their id is not known).

If the transaction fails, the rows already created (the parent and the `belongsToMany` rows) are **deleted**, then the error is raised: `createWith('users'): nested rows were not written, created rows removed: ...`. If one of those deletes fails in turn, the message says so and lists the rows left in the database (`these created rows could not be removed: users#12: ...`). `belongsTo` entries are ignored.

:::warning Not fully atomic
Only the `hasOne` / `hasMany` rows and the pivot rows are in the transaction. The parent and the `belongsToMany` rows are created **before** it, each by its own query: during that short window other queries can read them, and on failure they are removed by compensating `DELETE`s, not by a rollback. If everything must be atomic, write the rows yourself inside `OrvexORM.transaction(function(tx) ... end)`.
:::

---

### `Model.whereHas(relationName, callback?)` → `OrvexBuilder`

Filters the records that have at least one related record. Uses `WHERE EXISTS` in SQL. Soft-deleted related rows (when the related model has `softDelete`) do not count. For `belongsToMany`, the callback filters the **related** table (joined to the pivot table). An `orWhere` inside the callback stays tied to the parent row.

```lua
-- Players who own at least one vehicle
local players = User.whereHas("vehicles"):get()

-- Players who own a vehicle with plate "ABC123"
local players = User.whereHas("vehicles", function(b)
    b:where({ plate = "ABC123" })
end):get()
```

**Generated SQL (simplified):**
```sql
SELECT * FROM `users` WHERE EXISTS (
    SELECT 1 FROM `vehicles` WHERE `vehicles`.`owner_id` = `users`.`identifier`
)
```

---

### `Model.countByRelation(relationName, where?)` → `table`

Counts the related records of each parent record. Uses a **single** `GROUP BY` query for all parents at once (instead of one `COUNT` per parent). Soft-deleted related rows are not counted. Not supported for `belongsTo`.

```lua
local results = User.countByRelation("vehicles", { job = "police" })

for _, entry in ipairs(results) do
    print(entry.instance.identifier .. " has " .. entry.count .. " vehicle(s)")
end
-- Each instance also gets a _count_vehicles field
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

Excludes soft-deleted rows. Mind the order: `count` takes the `where` first, the other aggregations take the column first.

```lua
User.count()                   -- all
User.count({ job = "police" }) -- filtered
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

Creates the model's table if it does not exist. Generates the `CREATE TABLE IF NOT EXISTS` SQL from the schema automatically. With `timestamps = true`, adds `created_at` / `updated_at`; with `softDelete = true`, adds `deleted_at`. If the primary key is **not declared** in `fields`, a `` `<primaryKey>` INT UNSIGNED NOT NULL AUTO_INCREMENT `` column is added first (like `t:id()`). An existing table is never modified.

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

CreateThread(function()
    User.sync() -- Creates the "users" table if it does not exist
end)
```

---

### `Model.flushCache()`

Clears this model's cache entries (its table only).

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

Defines an N → N relation through a pivot table.

| Option | Type | Description |
|---|---|---|
| `pivot` | `string` | Name of the pivot table **(required)** |
| `foreignKey` | `string` | Pivot column → this table **(required)** |
| `otherKey` | `string` | Pivot column → related table **(required)** |
| `localKey` | `string?` | Column on this table (default: primaryKey) |

```lua
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",
    foreignKey = "user_id",
    otherKey   = "role_id",
})
```

---

## Model options

| Option | Type | Default | Description |
|---|---|---|---|
| `primaryKey` | `string` | `"id"` | Name of the primary key |
| `softDelete` | `boolean` | `false` | Enables soft delete (`deleted_at` column) |
| `timestamps` | `boolean` | `false` | Manages `created_at` and `updated_at` automatically |
| `hooks` | `table` | `nil` | Inline hooks `{ beforeCreate = fn, ... }`, one per event (see [Hooks](#hooks-lifecycle)) |
| `scopes` | `table` | `nil` | Inline scopes `{ rich = fn, ... }` |
| `relations` | `function` | `nil` | Callback that declares the relations `function(M) ... end` |
| `adapter` | `OrvexAdapter` | default | Adapter of this model only |
| `cache` | `OrvexCache` | global cache | Cache of this model only (see [Cache](/docs/guides/cache#one-cache-per-model)) |

| `allowManagedColumns` | `boolean` | `false` | Allows `created_at` / `updated_at` in the data of writes (imports) |

With `timestamps` or `softDelete`, the `created_at`, `updated_at` and `deleted_at` columns are accepted by validation even if you do not declare them in `fields`. Your data cannot write them: never `deleted_at`, `created_at` / `updated_at` only with `allowManagedColumns = true`; `before*` hooks always can.

```lua
local User = ORM.model("users", { ... }, {
    primaryKey = "identifier",
    softDelete = true,
    timestamps = true,
    hooks = {
        beforeCreate = function(data)
            data.money = data.money or 500
        end,
    },
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where({ job = "police" }) end,
    },
    relations = function(M)
        M.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
    end,
})

-- Call once every model has been created
User.applyRelations()
```

---

## Soft Delete

With `softDelete = true`, deletions mark the row with `deleted_at` instead of removing it. The class-level writes `update` / `updateWhere`, `increment` / `decrement` and `delete` add `deleted_at IS NULL`: they leave rows already deleted alone (unless the `where` holds `deleted_at`). `restore` still targets the deleted rows, `forceDelete` every row of the `where`.

```lua
local User = ORM.model("users", { ... }, { softDelete = true })

-- Soft delete (sets deleted_at)
User.delete({ identifier = "license:abc" })

-- Permanent delete
User.forceDelete({ identifier = "license:abc" })

-- Restore a deleted record
User.restore({ identifier = "license:abc" })

-- Query builder: include the deleted rows
User.withTrashed():get()

-- Query builder: only the deleted rows
User.onlyTrashed():get()
```

---

## Hooks (Lifecycle)

Hooks run code before/after writes. Writes **on an instance** fire the instance hooks; **class-level** writes (`User.update(data, where)`...) act on a `where` clause without loading the rows, so they fire the **bulk** hooks, which receive the data and the clause instead of an instance.

| Hook | Arguments | Fired by |
|---|---|---|
| `beforeCreate` | `data` | `create`, `createMany` and `createWith` (once per row), `findOrCreate`, `updateOrCreate` |
| `afterCreate` | `instance` | `create`, `findOrCreate`, `updateOrCreate` |
| `afterBulkCreate` | `rows` | `createMany`, `createWith` (`hasOne` / `hasMany` rows, once per relation) |
| `beforeUpdate` | `instance, data` | `instance:update`, `updateOrCreate` |
| `afterUpdate` | `instance` | `instance:update`, `updateOrCreate` |
| `beforeDelete` | `instance` | `instance:delete`, `instance:forceDelete` |
| `afterDelete` | `instance` | `instance:delete`, `instance:forceDelete` |
| `beforeBulkUpdate` | `data, where` | `update`, `updateWhere` |
| `afterBulkUpdate` | `data, where, affected` | `update`, `updateWhere` |
| `beforeBulkDelete` | `where` | `delete`, `deleteWhere`, `forceDelete` |
| `afterBulkDelete` | `where, affected` | `delete`, `deleteWhere`, `forceDelete` |
| `beforeUpsert` | `data` | `upsert` |
| `afterUpsert` | `data` | `upsert` |

`before*` hooks receive a **copy** of the data and may modify it (add a field, change a value): that copy is what gets validated and written. A column added by a hook must exist in the schema (or be a managed column, see [Validation](/docs/guides/validation#unknown-columns)). **No hook** fires for `increment` / `decrement`, `restore`, the `tx:*` transaction methods, `OrvexORM.raw` / `rawExec`. The nested rows `createWith` inserts in batch fire `beforeCreate` and `afterBulkCreate`, not `afterCreate`. The list of events is exposed as `OrvexModelFactory.HOOK_EVENTS`.

Every event has a shortcut (`User.beforeCreate(fn)`), and `User.hook(event, fn)` works for all of them. Several hooks per event run in registration order.

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

-- Class-level writes
User.beforeBulkUpdate(function(data, where)
    data.updated_by = "admin"  -- column declared in the schema
end)

User.afterBulkDelete(function(where, affected)
    print(("%d row(s) deleted"):format(affected))
end)
```

---

## Scopes

Scopes are reusable filters for the query builder. Once defined, a scope becomes **directly callable as a model method**.

```lua
-- Define a scope
User.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

User.scope("cops", function(b)
    b:where({ job = "police" })
end)

-- Use a scope as a direct method
local richPlayers = User.rich():get()
local copPlayers  = User.cops():get()

-- Chainable with other conditions
local richCops = User.rich():where({ job = "police" }):get()

-- Or through scoped() (older syntax, still supported)
local richPlayers = User.scoped("rich"):get()
```

You can also declare scopes inline in the model definition:

```lua
local User = ORM.model("users", { ... }, {
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where({ job = "police" }) end,
    },
})

-- Ready to use!
User.rich():limit(10):get()
```
