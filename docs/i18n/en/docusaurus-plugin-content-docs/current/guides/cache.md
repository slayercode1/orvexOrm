---
sidebar_position: 8
---

# Cache

The **cache** stores query results in memory to avoid unnecessary database calls. If you look up the same player 10 times in 1 second, the database is only queried once.

## Enabling the cache

By default, the cache is **disabled**. To enable it:

```lua
-- Enable with a 60-second TTL (time-to-live for cached data)
OrvexORM.enableCache({ ttl = 60 })
```

The **TTL** (Time To Live) is the duration in seconds that data remains in the cache before being considered stale.

The global cache holds at most **1000 entries**. When it is full, the **least recently read** entry is evicted (LRU). Expired entries are purged as writes happen, at most once per TTL: memory does not grow forever.

:::info One cache per resource
The cache lives in the resource's memory. With `@orvexorm/lib/import.lua`, each resource has **its own** cache: `enableCache()` in resource A enables nothing in resource B, and a write made by B does not invalidate A's cache. If several resources (or another script, or a tool such as HeidiSQL) write to the same tables, keep a short TTL or leave the cache off for those models.
:::

## How it works

### Without cache

```lua
-- Each call queries the database
local p1 = User.find({ identifier = "license:abc" })  -- → SQL query
local p2 = User.find({ identifier = "license:abc" })  -- → SQL query (again)
local p3 = User.find({ identifier = "license:abc" })  -- → SQL query (again)
-- = 3 SQL queries
```

### With cache

```lua
OrvexORM.enableCache({ ttl = 30 })

local p1 = User.find({ identifier = "license:abc" })  -- → SQL query (cache miss)
local p2 = User.find({ identifier = "license:abc" })  -- → cache (no SQL!)
local p3 = User.find({ identifier = "license:abc" })  -- → cache (no SQL!)
-- = 1 single SQL query
```

## Automatic invalidation

The cache is **automatically invalidated** when you modify data. You don't have to worry about it.

```lua
local player = User.find({ identifier = "license:abc" })  -- cache miss → SQL
local player = User.find({ identifier = "license:abc" })  -- cache hit

-- Modification → the "users" table cache is cleared
User.update({ money = 1000 }, { identifier = "license:abc" })

local player = User.find({ identifier = "license:abc" })  -- cache miss → SQL (fresh data)
```

Operations that invalidate the cache:

| Operation | Invalidates cache? |
|---|---|
| `create()`, `createMany()`, `createWith()` | Yes |
| `upsert()` | Yes |
| `update()` / `updateWhere()` (class and instance) | Yes |
| `delete()`, `forceDelete()`, `restore()` (class and instance) | Yes |
| `increment()` / `decrement()` | Yes |
| `attach()` / `detach()` | Yes (pivot table) |
| `OrvexORM.transaction` / `tx:commit()` | Yes, for every table written, **after** a successful commit |
| `OrvexORM.raw()` / `rawExec()` that writes | Yes: the written table, or the **whole** cache when it cannot be told |
| `find()` / `findAll()` | No (read-only) |
| `query():get()` | No (read-only) |

Invalidation is **exact**: writing to `users` only drops the entries that read `users` (including through a join or a subquery), not those of `users_logs`. It only costs the number of entries of that table.

:::caution What the cache cannot see
A write made **outside this resource** (another resource, another SQL script, the Studio, an external tool) invalidates nothing: reads can stay stale until the TTL. Transactions and `raw` only invalidate the **global** cache: a model with its own `opts.cache` must be flushed by hand (`Model.flushCache()`).
:::

## Managing the cache manually

### Flush the cache for a model

```lua
User.flushCache()
```

### Flush all caches

```lua
OrvexORM.flushCache()
```

### Disable the cache

```lua
OrvexORM.disableCache()  -- disables and empties the global cache
```

### Checking the statistics

`OrvexORM.cacheStats()` tells you whether your cache is effective:

```lua
local stats = OrvexORM.cacheStats()

print(stats.hits)     -- reads served from the cache
print(stats.misses)   -- reads that queried the database
print(stats.hitRate)  -- ratio hits / (hits + misses)
print(stats.entries)  -- number of entries currently cached
print(stats.maxEntries) -- maximum size (1000 for the global cache)
```

:::tip Reading the hitRate
A `hitRate` close to 1 means most reads come from the cache. If it is very low, your TTL may be too short, or your queries are too varied to benefit from the cache.
:::

## Which TTL to choose?

| Situation | Recommended TTL |
|---|---|
| Data that rarely changes (configs, roles) | `300` (5 minutes) |
| Data that changes often (money, inventory) | `10` - `30` seconds |
| Real-time data (position, health) | Don't use the cache |

:::caution Beware of caching critical data
The cache may return slightly stale data (up to the TTL). For critical operations like money transfers, it's safer to **not** cache this data or to use a very short TTL.
:::

## The cache with the Query Builder

The cache also works with the Query Builder:

```lua
-- This query is cached
local cops = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :limit(10)
    :get()

-- If the same query is run again within the TTL, the cache is used
local cops2 = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :limit(10)
    :get()
-- → no SQL query, identical result from the cache
```

Aggregations (`count`, `sum`, `avg`, `min`, `max`) are also cached. `chunk` / `chunkById` scans are not (they would evict useful entries).

A query with a parameter that is a table, a function or a userdata is **not** cached (its key would not be reliable). Parameters are told apart by type: `1` and `"1"`, or `true` and `"true"`, give different entries.

## One cache per model

A model can have its own cache, with its own settings, through the `cache` option. The global `OrvexCache` class is available in orvexorm and in every resource that uses `lib/import.lua`:

```lua
local Config = OrvexORM.model("server_config", { key = "string", value = "json" }, {
    primaryKey = "key",
    cache = OrvexCache.new({
        ttl = 300,          -- 5 minutes
        maxEntries = 200,   -- default: 1000
    }),
})
```

| `OrvexCache.new` option | Default | Description |
|---|---|---|
| `ttl` | `60` | Time to live in seconds |
| `maxEntries` | `1000` | Maximum number of entries (LRU eviction) |
| `sweepInterval` | `ttl` (min. 1 s) | Minimum interval between two purges of expired entries |
| `enabled` | `true` | A cache created this way is **active** right away, even if the global cache is off |

This cache is not affected by `OrvexORM.enableCache`, `disableCache`, `flushCache` or `cacheStats`. Use its methods: `cache:setEnabled(bool)`, `cache:flush()`, `cache:stats()`, `cache:purgeExpired()` (returns the number of entries removed), or `Model.flushCache()`.
