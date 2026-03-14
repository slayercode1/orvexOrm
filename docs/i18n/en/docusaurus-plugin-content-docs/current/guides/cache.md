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
| `create()` | Yes |
| `upsert()` | Yes |
| `update()` (class and instance) | Yes |
| `delete()` (class and instance) | Yes |
| `attach()` / `detach()` | Yes (pivot table) |
| `find()` / `findAll()` | No (read-only) |
| `query():get()` | No (read-only) |

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
OrvexORM.disableCache()
```

## Choosing the right TTL

| Situation | Recommended TTL |
|---|---|
| Data that rarely changes (configs, roles) | `300` (5 minutes) |
| Data that changes often (money, inventory) | `10` - `30` seconds |
| Real-time data (position, health) | Don't use the cache |

:::caution Beware of caching critical data
The cache may return slightly stale data (up to the TTL). For critical operations like money transfers, it's safer to **not** cache this data or to use a very short TTL.
:::

## Cache with the Query Builder

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

Aggregations (`count`, `sum`, `avg`, `min`, `max`) are also cached.
