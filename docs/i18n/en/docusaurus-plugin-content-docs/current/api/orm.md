---
sidebar_position: 1
---

# ORM

The main module. This is the entry point of the library.

```lua
-- OrvexORM is a global table, in orvexorm and in every resource
-- that includes server_script '@orvexorm/lib/import.lua'
print(OrvexORM.version)  -- version read from orvexorm's fxmanifest.lua
```

:::info Async
Every function that touches the database (`transaction`, `migrate`, `rollback`, `raw`, `rawExec`, `seed` depending on its content, `introspect`, `fromTable`) waits for MySQL's answer: call them from a thread, an event or a command. See [Async and threads](/docs/getting-started#async-and-threads). `model`, `enableCache`, `debug`, `setAdapter`, `migrations` and `schema` run no query.
:::

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
| `timestamps` | `boolean` | `false` | Fills `created_at` / `updated_at`; these columns are accepted even if they are not in `fields` |
| `softDelete` | `boolean` | `false` | `delete()` fills `deleted_at` instead of deleting; reads and class-level writes exclude those rows |
| `allowManagedColumns` | `boolean` | `false` | Allows `created_at` / `updated_at` in the data of `create`, `createMany`, `upsert`, `update` (otherwise an error). `deleted_at` is always refused |
| `hooks` | `table` | `nil` | One hook per event: `{ beforeCreate = fn, afterBulkUpdate = fn, ... }` (see [Hooks](/docs/api/model#hooks-lifecycle)) |
| `scopes` | `table` | `nil` | Reusable filters: `{ rich = function(b) b:where(...) end }`, callable as `User.rich()` |
| `relations` | `function` | `nil` | `function(M) M.hasMany(...) end`, run by `Model.applyRelations()` |
| `adapter` | `OrvexAdapter` | default adapter | Adapter of this model (another database, a test driver...) |
| `cache` | `OrvexCache` | global cache | Cache of this model only (see [Cache](/docs/guides/cache#one-cache-per-model)) |

### Available field types

| Type | Description |
|---|---|
| `"string"` | Text |
| `"number"` | Number |
| `"boolean"` | True/false |
| `"json"` | Lua table automatically converted to JSON |
| `"date"` | Date (`"2024-03-15"`) |
| `"datetime"` | Date and time (`"2024-03-15 14:30:00"`) |
| `"timestamp"` | Timestamp (`"2024-03-15 14:30:00"`) |
| `"auto"` | Automatic detection (table → JSON, JSON string → table) |

Any other type (a typo such as `"int"` or `"text"`) raises an error as soon as the model is defined: `Field 'x': unknown type 'int' (supported: string, number, boolean, json, auto, date, datetime, timestamp)`.

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

## `ORM.transaction(fn, adapter?)` / `ORM.transaction(adapter?)`

Creates a new transaction builder, or runs a transactional callback with auto-commit. Only `tx:*` methods are part of the transaction; read the [Transactions guide](/docs/guides/transactions) before writing a conditional operation (transfer, purchase).

### Callback mode (recommended)

```lua
local success = OrvexORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:abc", money = 500 })
    tx:update("vehicles", { owner = "license:abc" }, { plate = "ABC123" })
end) -- auto-commit!
```

### Builder mode

```lua
local tx = OrvexORM.transaction()
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("vehicles", { owner = "license:abc" }, { plate = "ABC123" })
local success = tx:commit()
```

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `fn` | `function` | No | Callback receiving the transaction builder. If given, auto-commit at the end. If it raises an error, nothing is sent and the error propagates. |
| `adapter` | `OrvexAdapter` | No | Custom adapter (the default one otherwise). In callback mode it is the **2nd** argument: `ORM.transaction(fn, adapter)`. |

### Return

- Callback mode: `boolean` — `true` if the transaction succeeded. Depending on the driver, a failure can also raise an error (see [commit](/docs/guides/transactions#txcommit--boolean)).
- Builder mode: `OrvexTransaction` — A transaction object with the `insert`, `update`, `delete`, `upsert`, `addRaw`, `getQueries`, `commit` methods

After a successful commit, the global cache is invalidated for every table written.

---

## `ORM.enableCache(opts?)`

Enables the global cache with an optional TTL. The global cache holds at most **1000 entries**; beyond that, the least recently read ones are evicted (LRU). A result of more than **5000 rows** is not cached. For other limits (`maxEntries`, `maxRows`), give a model its own cache (`opts.cache`, see [Cache](/docs/guides/cache#one-cache-per-model)).

### Parameters

| Option | Type | Default | Description |
|---|---|---|---|
| `ttl` | `number` | `60` | Time to live in seconds |

The cache lives in the resource that enables it: with `lib/import.lua`, each resource has its own.

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

| Field | Type | Description |
|---|---|---|
| `hits` | `number` | Number of reads served from the cache |
| `misses` | `number` | Number of reads that queried the database |
| `hitRate` | `number` | Ratio hits / (hits + misses) |
| `entries` | `number` | Number of entries currently in the cache |
| `maxEntries` | `number` | Maximum cache size (1000 for the global cache) |

### Example

```lua
local stats = OrvexORM.cacheStats()
print(("Cache: %d hits, %d misses (%.0f%% hit rate), %d entries")
    :format(stats.hits, stats.misses, stats.hitRate * 100, stats.entries))
```

---

## `ORM.setAdapter(adapter)`

Replaces the default database adapter (used by models created **after** the call, transactions, `raw`, `rawExec` and migrations). An adapter is built with the global `OrvexAdapter` class, available in orvexorm and in every resource that uses `lib/import.lua`: `OrvexAdapter.new(driver, opts?)`.

```lua
local MyDriver = {}
MyDriver.__index = MyDriver

function MyDriver:execute(sql, params)   -- SELECT: returns a list of rows
    return exports.oxmysql:executeSync(sql, params) or {}
end

function MyDriver:scalar(sql, params)    -- INSERT: inserted id; UPDATE / DELETE: affected rows
    if sql:match("^%s*[Ii][Nn][Ss][Ee][Rr][Tt]") then
        return exports.oxmysql:insertSync(sql, params)
    end
    return exports.oxmysql:updateSync(sql, params)
end

function MyDriver:transaction(queries)   -- optional: { { query = "...", values = {...} }, ... }
    return exports.oxmysql:transactionSync(queries) == true
end

OrvexORM.setAdapter(OrvexAdapter.new(setmetatable({}, MyDriver)))
```

### Driver contract

| Method | Required | Receives | Returns |
|---|---|---|---|
| `driver:execute(sql, params)` | Yes | query and parameter array | `table[]`: the rows (`{}` if none) |
| `driver:scalar(sql, params)` | Yes | write query | `INSERT`: the inserted id; `UPDATE`/`DELETE`: the affected row count (`number` or `{ affectedRows = n }`) |
| `driver:transaction(queries)` | No | `{ { query, values }, ... }` | `boolean`: `true` if everything was applied |

Without `transaction`, the adapter **refuses** transactions: `OrvexORM.transaction`, `createMany` with several key sets and `createWith` raise an error (`this driver has no :transaction(), so a transaction cannot be atomic`). To accept a query-by-query, **non-atomic** run anyway, opt in explicitly:

```lua
OrvexORM.setAdapter(OrvexAdapter.new(setmetatable({}, MyDriver), {
    allowNonAtomicTransactions = true,  -- a failing query does not roll back the previous ones
}))
```

In this mode, a failure returns `false`. If queries already ran before the failure (partial commit), the transaction still invalidates the cache of every table it touches (the whole cache for a raw statement whose tables cannot be told): no read can serve a stale row. The database keeps those partial changes. Driver methods may *yield* (`Citizen.Await`).

The shipped driver is `OrvexMySQLDriver` (`OrvexAdapter.new(OrvexMySQLDriver.new())`), see [MySQL driver](/docs/installation#mysql-driver).

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

Runs all pending migrations, in order, in a new batch recorded under the name of the calling resource (`GetCurrentResourceName()`). A migration name is **unique across the whole database**: a name already recorded by another resource raises an error before anything runs. So prefix your names with your resource name (`"garage_001_create_vehicles"`). **On the first failing migration**, it is not recorded, the following ones are not run, and an error is raised: `[OrvexORM] Migration of migration '<name>' failed (N migration(s) applied before it): <driver error>`. A statement for which the driver returns `nil` counts as a failure. An applied migration whose tracking row cannot be written raises an error too.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | No | Custom adapter (uses the default otherwise) |

### Return

`number` — The number of migrations applied.

### Example

```lua
CreateThread(function()
    local ok, result = pcall(OrvexORM.migrate)
    if ok then
        print(result .. " migration(s) applied")
    else
        print("^1Migration failed: " .. tostring(result) .. "^0")
    end
end)
```

:::caution DDL is not transactional
MySQL commits each `CREATE` / `ALTER` immediately: if a migration has several statements and the 3rd one fails, the first 2 stay applied. Fix the database by hand or write single-statement migrations.
:::

---

## `ORM.rollback(adapter?)`

Rolls back the last batch of migrations **of the calling resource** (newest first). Only migrations this resource registered (`OrvexORM.migrations`) and applied are rolled back: `rollback()` never touches another resource's migrations. If a `down` fails, its migration stays recorded and an error is raised, as with `migrate()`.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | No | Custom adapter (uses the default otherwise) |

### Return

`number` — The number of migrations rolled back.

### Example

```lua
CreateThread(function()
    local count = OrvexORM.rollback()
    print(count .. " migration(s) rolled back")
end)
```

---

## `ORM.raw(sql, params?)`

Runs a raw SQL query (SELECT) and returns the rows (`{}` if none). The rows are plain tables, not instances.

```lua
local rows = OrvexORM.raw("SELECT * FROM users WHERE money > ?", { 1000 })
```

If the query writes (`INSERT`, `UPDATE`, `DELETE`...), the global cache is invalidated for the written table, or flushed entirely when the table cannot be told (joins, complex subqueries).

---

## `ORM.rawExec(sql, params?)`

Runs a raw SQL query (INSERT/UPDATE/DELETE) and returns what the driver returns: the inserted id for an `INSERT`, the affected row count for an `UPDATE` / `DELETE`. Invalidates the global cache like `ORM.raw`.

```lua
local affected = OrvexORM.rawExec("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
print(affected .. " officer(s) paid")
```

---

## `ORM.debug(enabled)`

Enables or disables debug mode. When enabled, all SQL queries are printed in the console.

```lua
OrvexORM.debug(true)   -- Enable SQL logs
OrvexORM.debug(false)  -- Disable logs
```

---

## `ORM.seed(fn)`

Runs a seed function to populate the database with initial data.

```lua
CreateThread(function()
    OrvexORM.seed(function(orm)
        local User = orm.model("users", { identifier = "string", money = "number" })
        User.create({ identifier = "license:admin", money = 99999 })
        User.create({ identifier = "license:test", money = 500 })
    end)
end)
```

---

## `ORM.introspect(tableName, adapter?)`

Analyzes an existing MySQL table and returns its field definitions and primary key. Uses `DESCRIBE` internally.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `tableName` | `string` | Yes | Name of the MySQL table to analyze |
| `adapter` | `OrvexAdapter` | No | Custom adapter |

### Return

`table<string, OrvexFieldType>, string` — The detected fields and the primary key name.

### MySQL type mapping

| MySQL type | OrvexORM type |
|---|---|
| `int`, `bigint`, `float`, `double`, `decimal` | `"number"` |
| `varchar`, `char`, `text`, `enum` | `"string"` |
| `tinyint(1)` | `"boolean"` |
| `json` | `"json"` |
| `date` | `"date"` |
| `datetime` | `"datetime"` |
| `timestamp` | `"timestamp"` |

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

---

## `ORM.unpack()`

Returns the most common functions to avoid repeating `OrvexORM.` everywhere.

### Return

`function, function, function, function` — `model`, `raw`, `migrate`, `transaction` (typed for LuaLS: each function keeps the signature of `OrvexORM.*`)

### Example

```lua
local model, raw, migrate, transaction = OrvexORM.unpack()

local User = model("users", { identifier = "string", money = "number" })

CreateThread(function()
    migrate()
    local rows = raw("SELECT * FROM logs")
end)
```
