---
sidebar_position: 1
---

# ORM

The main module. This is the entry point of the library.

```lua
```

---

## `ORM.model(tableName, fields, opts?)`

Creates a new model linked to a MySQL table.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `tableName` | `string` | Yes | Name of the MySQL table |
| `fields` | `table` | Yes | Schema: `{ column = "type", ... }` |
| `opts` | `table` | No | Options (see below) |

### Options (`opts`)

| Option | Type | Default | Description |
|---|---|---|---|
| `primaryKey` | `string` | `"id"` | Name of the primary key column |

### Available field types

| Type | Description |
|---|---|
| `"string"` | Text |
| `"number"` | Number |
| `"boolean"` | True/false |
| `"json"` | Lua table automatically converted to JSON |
| `"auto"` | Automatic detection (table → JSON, JSON string → table) |

### Return

`OrvexModel` — A model object with all CRUD methods, the query builder, and relations.

### Example

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
    position   = "json",
    metadata   = "auto",
}, { primaryKey = "identifier" })
```

---

## `ORM.transaction(adapter?)`

Creates a new transaction builder to execute multiple queries atomically.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | No | Custom adapter (uses the default otherwise) |

### Return

`OrvexTransaction` — A transaction object with the methods `insert`, `update`, `delete`, `upsert`, `addRaw`, `commit`.

### Example

```lua
local tx = OrvexORM.transaction()
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("vehicles", { owner = "license:abc" }, { plate = "ABC123" })
local success = tx:commit()
```

---

## `ORM.enableCache(opts?)`

Enables the global cache with an optional TTL.

### Parameters

| Option | Type | Default | Description |
|---|---|---|---|
| `ttl` | `number` | `60` | Time to live in seconds |

### Example

```lua
OrvexORM.enableCache({ ttl = 30 })
```

---

## `ORM.disableCache()`

Disables and clears the global cache.

```lua
OrvexORM.disableCache()
```

---

## `ORM.flushCache()`

Clears all cache entries without disabling it.

```lua
OrvexORM.flushCache()
```

---

## `ORM.cacheStats()`

Returns global cache statistics.

### Return

`table` — `{ hits, misses, hitRate, entries }`

| Field | Type | Description |
|---|---|---|
| `hits` | `number` | Number of cache hits |
| `misses` | `number` | Number of cache misses |
| `hitRate` | `number` | Hit ratio (`hits / (hits + misses)`) |
| `entries` | `number` | Number of entries currently in the cache |

### Example

```lua
local stats = OrvexORM.cacheStats()
print(("Cache: %d hits, %d misses (%.0f%% hit rate), %d entries")
    :format(stats.hits, stats.misses, stats.hitRate * 100, stats.entries))
```

---

## `ORM.setAdapter(adapter)`

Replaces the default database adapter.

```lua
OrvexORM.setAdapter(Adapter.new(MyDriver.new()))
```

---

## `ORM.migrations(migrations)`

Registers a list of migrations to apply.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `migrations` | `table[]` | Yes | List of migrations with `name`, `up`, `down` |

### Example

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
})
```

---

## `ORM.migrate(adapter?)`

Runs all pending migrations.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | No | Custom adapter (uses the default otherwise) |

### Return

`number` — The number of applied migrations.

### Example

```lua
local count = OrvexORM.migrate()
print(count .. " migration(s) applied")
```

---

## `ORM.rollback(adapter?)`

Rolls back the last batch of migrations.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | No | Custom adapter (uses the default otherwise) |

### Return

`number` — The number of rolled back migrations.

### Example

```lua
local count = OrvexORM.rollback()
print(count .. " migration(s) rolled back")
```

---

## `ORM.raw(sql, params?)`

Executes a raw SQL query (SELECT) and returns the rows.

```lua
local rows = OrvexORM.raw("SELECT * FROM users WHERE money > ?", { 1000 })
```

---

## `ORM.rawExec(sql, params?)`

Executes a raw SQL query (INSERT/UPDATE/DELETE).

```lua
OrvexORM.rawExec("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
```

---

## `ORM.debug(enabled)`

Enables or disables debug mode. When enabled, all SQL queries are printed to the console.

```lua
OrvexORM.debug(true)   -- Enable SQL logs
OrvexORM.debug(false)  -- Disable logs
```

---

## `ORM.seed(fn)`

Runs a seed function to populate the database with initial data.

```lua
OrvexORM.seed(function(orm)
    local User = orm.model("users", { identifier = "string", money = "number" })
    User.create({ identifier = "license:admin", money = 99999 })
    User.create({ identifier = "license:test", money = 500 })
end)
```

---

## `ORM.introspect(tableName, adapter?)`

Analyzes an existing MySQL table and returns its field definition and primary key. Uses `DESCRIBE` internally.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `tableName` | `string` | Yes | Name of the MySQL table to analyze |
| `adapter` | `OrvexAdapter` | No | Custom adapter |

### Return

`table<string, OrvexFieldType>, string` — The detected fields and the primary key name.

### MySQL type mapping

| MySQL Type | OrvexORM Type |
|---|---|
| `int`, `bigint`, `float`, `double`, `decimal` | `"number"` |
| `varchar`, `char`, `text`, `enum` | `"string"` |
| `tinyint(1)` | `"boolean"` |
| `json` | `"json"` |
| `datetime`, `timestamp`, `date` | `"string"` |

### Example

```lua
local fields, pk = OrvexORM.introspect("users")
-- fields = { id = "number", name = "string", money = "number", ... }
-- pk = "id"

-- Create a model automatically
local User = OrvexORM.model("users", fields, { primaryKey = pk })
```

---

## `ORM.fromTable(tableName, opts?)`

Shortcut that combines `introspect()` and `model()`: analyzes the table and creates the model automatically.

```lua
local User = OrvexORM.fromTable("users")
-- Equivalent to:
-- local fields, pk = OrvexORM.introspect("users")
-- local User = OrvexORM.model("users", fields, { primaryKey = pk })
```
