# [FREE][STANDALONE][OPEN SOURCE] OrvexORM — Lightweight Lua ORM for FiveM

OrvexORM is a lightweight ORM made specifically for FiveM resources. It provides models, a fluent query builder, relations, migrations, transactions, caching, and a built-in database browser while remaining compatible with both oxmysql and mysql-async.

The goal is simple: keep database code readable and reusable without forcing every resource to repeat the same SQL and callback logic.

## Preview

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, {
    primaryKey = "identifier",
    timestamps = true,
})

local player = User.find({ identifier = "license:abc" })

if player then
    player:increment("money", 500)
    player:update({ job = "mechanic" })
end
```

## Features

- Model-based CRUD
- Fluent query builder
- hasOne, hasMany, belongsTo, and belongsToMany relations
- Eager loading and relation counts
- Transactions
- Migrations and schema builder
- Soft deletes
- Automatic timestamps
- JSON column serialization
- Data type validation
- Aggregations and pagination
- Reusable query scopes
- Bulk inserts, upserts, and nested writes
- Optional in-memory query cache
- Built-in OrvexORM Studio database browser
- Automatic oxmysql/mysql-async detection
- Lua 5.4 support
- No JavaScript runtime dependency

## Requirements

- A FiveM server using Lua 5.4
- oxmysql or mysql-async
- MySQL 5.7+ or a compatible MariaDB version

## Installation

1. Download the [latest release](https://github.com/slayercode1/orvexOrm/releases/latest).
2. Extract the `orvexorm` folder into your server's `resources` directory.
3. Start your MySQL resource before OrvexORM.

```cfg
ensure oxmysql
ensure orvexorm
```

For mysql-async:

```cfg
ensure mysql-async
ensure orvexorm
```

Add the dependency and import file to each resource that uses OrvexORM:

```lua
-- fxmanifest.lua
dependency 'orvexorm'

server_script '@orvexorm/lib/import.lua'
server_script 'server.lua'
```

The global `OrvexORM` object is then available from your server scripts.

## Defining a model

```lua
local Player = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
    position   = "json",
    created_at = "datetime",
    updated_at = "datetime",
}, {
    primaryKey = "identifier",
    timestamps = true,
    softDelete = true,
})
```

Supported field types include:

| OrvexORM | Lua value | MySQL type |
|---|---|---|
| `string` | string | `VARCHAR(255)` |
| `number` | number | `INT` |
| `boolean` | boolean | `TINYINT(1)` |
| `json` | table | `JSON` |
| `date` | string | `DATE` |
| `datetime` | string | `DATETIME` |
| `timestamp` | string | `TIMESTAMP` |

## CRUD

```lua
local player = Player.create({
    identifier = "license:abc",
    money = 500,
    job = "unemployed",
    position = { x = 120.0, y = -300.0, z = 40.0 },
})

local found = Player.find({ identifier = "license:abc" })
local police = Player.findAll({ job = "police" })

found:update({ money = 1000 })
found:increment("money", 250)
found:decrement("money", 50)
found:delete()
```

Additional helpers include `first`, `all`, `exists`, `pluck`, `findOrFail`, `findOrCreate`, `updateOrCreate`, `createMany`, and `upsert`.

## Query builder

```lua
local players = Player.query()
    :where("job", "police")
    :where("money", ">", 1000)
    :whereNotIn("identifier", { "license:blocked1", "license:blocked2" })
    :orderByDesc("money")
    :limit(10)
    :get()
```

Pagination returns the rows and page metadata:

```lua
local result = Player.query()
    :where("job", "police")
    :paginate(2, 20)

print(result.page)
print(result.lastPage)
print(result.total)
```

## Relations

```lua
Player.hasMany("vehicles", Vehicle, {
    foreignKey = "owner_id",
})

Player.hasOne("profile", Profile, {
    foreignKey = "user_id",
})

Vehicle.belongsTo("owner", Player, {
    foreignKey = "owner_id",
})

local player = Player.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")
```

Relations can also be eager-loaded:

```lua
local players = Player.findAll({ job = "police" }, {
    include = { "vehicles", "profile" },
})
```

## Transactions

```lua
local success = OrvexORM.transaction(function(tx)
    tx:update("users", { money = 900 }, { identifier = fromId })
    tx:update("users", { money = 1100 }, { identifier = toId })
end)

if not success then
    print("Transaction failed")
end
```

## Migrations

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
                t:json("position")
                t:timestamps()
                t:softDeletes()
                t:index("job")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
})

OrvexORM.migrate()
```

## Cache

```lua
OrvexORM.enableCache({ ttl = 60 })

local stats = OrvexORM.cacheStats()
print(stats.hits, stats.misses, stats.hitRate)

OrvexORM.disableCache()
```

Cached reads are invalidated automatically when the related model writes data.

## OrvexORM Studio

Studio is an optional web interface for inspecting tables, schemas, and rows while developing your server.

Start it from the server console:

```text
orvexstudio
```

The console displays the temporary Studio URL. Stop the interface when finished:

```text
orvexstudio stop
```

Studio includes table browsing, schema inspection, filters, sorting, pagination, and row editing.

## Debug logging

Query logging is disabled by default. It can be enabled during development:

```lua
OrvexORM.debug(true)
```

Disable it again when it is no longer needed:

```lua
OrvexORM.debug(false)
```

## Links

- Documentation: https://slayercode1.github.io/orvexOrm/
- GitHub: https://github.com/slayercode1/orvexOrm
- Releases: https://github.com/slayercode1/orvexOrm/releases
- Issues: https://github.com/slayercode1/orvexOrm/issues

## License and price

- Price: Free
- Subscription: No
- Source available: Yes
- License: MIT
- Support: GitHub Issues
