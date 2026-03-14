---
sidebar_position: 10
---

# Migrations & Table Creation

OrvexORM can **create your tables automatically** from your models, or let you write **migrations** to manage the evolution of your database over time.

## Quick creation with `sync()`

The simplest method: you define your model and call `.sync()`. The table is automatically created if it doesn't exist.

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- Creates the "users" table if it doesn't exist
User.sync()
```

:::tip When to use sync()?
`sync()` is perfect for **development** and **initial testing**. It creates the table if it doesn't exist, but doesn't modify it if it already exists. For structural changes, use **migrations**.
:::

### Type mapping

When you use `sync()`, OrvexORM converts your schema types to MySQL types:

| OrvexORM type | MySQL type |
|---|---|
| `"string"` | `VARCHAR(255)` |
| `"number"` | `INT` |
| `"boolean"` | `TINYINT(1)` |
| `"json"` | `JSON` |
| `"auto"` | `TEXT` |

The **primary key** is automatically configured as `NOT NULL`. If it's a `"number"` field, it's also `AUTO_INCREMENT`.

## Migrations

Migrations let you version your database changes. Each migration has a unique name, an `up` function (apply) and a `down` function (revert).

### Defining migrations

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
                t:timestamp("created_at")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
    {
        name = "002_create_vehicles",
        up = function(schema)
            schema:create("vehicles", function(t)
                t:id()
                t:string("owner", 60)
                t:string("plate", 10)
                t:string("model")
                t:integer("fuel")
                t:json("mods")
            end)
        end,
        down = function(schema)
            schema:drop("vehicles")
        end,
    },
})
```

### Applying migrations

```lua
local count = OrvexORM.migrate()
print(count .. " migration(s) applied")
```

OrvexORM keeps track of already applied migrations in an `orvex_migrations` table. Previously executed migrations are never replayed.

### Rolling back migrations

```lua
local count = OrvexORM.rollback()
print(count .. " migration(s) rolled back")
```

`rollback()` reverts the **last batch** of migrations (the last `migrate()` call).

## The Schema Builder

In migrations, you have access to a **Schema Builder** to define your tables in a readable way.

### Creating a table

```lua
schema:create("players", function(t)
    t:id()                        -- INT UNSIGNED NOT NULL AUTO_INCREMENT (PK)
    t:string("name", 100)         -- VARCHAR(100)
    t:integer("money")            -- INT
    t:bigInteger("experience")    -- BIGINT
    t:float("rating")             -- FLOAT
    t:double("coordinates")       -- DOUBLE
    t:boolean("vip")              -- TINYINT(1)
    t:text("bio")                 -- TEXT
    t:json("inventory")           -- JSON
    t:datetime("last_login")      -- DATETIME
    t:timestamp("created_at")     -- TIMESTAMP
end)
```

### Available column types

| Method | MySQL type | Description |
|---|---|---|
| `t:id(name?)` | `INT UNSIGNED AUTO_INCREMENT` | Auto-increment primary key (default: `"id"`) |
| `t:primaryString(name, length?)` | `VARCHAR(n) NOT NULL` | Text primary key (default: 60 characters) |
| `t:string(name, length?)` | `VARCHAR(n)` | Text (default: 255 characters) |
| `t:integer(name)` | `INT` | Integer |
| `t:bigInteger(name)` | `BIGINT` | Large integer |
| `t:float(name)` | `FLOAT` | Decimal number (single precision) |
| `t:double(name)` | `DOUBLE` | Decimal number (double precision) |
| `t:boolean(name)` | `TINYINT(1)` | True/false |
| `t:text(name)` | `TEXT` | Long text |
| `t:json(name)` | `JSON` | JSON data |
| `t:datetime(name)` | `DATETIME` | Date and time |
| `t:timestamp(name)` | `TIMESTAMP` | Timestamp (auto `CURRENT_TIMESTAMP`) |

### Dropping a table

```lua
schema:drop("old_table")

-- Or in "safe" mode (does nothing if the table doesn't exist)
schema:dropIfExists("maybe_table")
```

### Modifying an existing table

```lua
schema:table("users", function(t)
    -- Add columns
    t:string("email", 255)
    t:boolean("verified")

    -- Drop a column
    t:dropColumn("old_column")

    -- Rename a column
    t:renameColumn("name", "full_name")
end)
```

### Raw SQL

If you need a special operation, you can add raw SQL:

```lua
schema:raw("ALTER TABLE users ADD INDEX idx_job (job)")
```

## Full examples

### Typical FiveM server

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
                t:json("inventory")
                t:timestamp("created_at")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
    {
        name = "002_create_vehicles",
        up = function(schema)
            schema:create("vehicles", function(t)
                t:id()
                t:string("owner", 60)
                t:string("plate", 10)
                t:string("model")
                t:integer("fuel")
                t:json("mods")
            end)
        end,
        down = function(schema)
            schema:drop("vehicles")
        end,
    },
    {
        name = "003_create_roles",
        up = function(schema)
            schema:create("roles", function(t)
                t:id()
                t:string("name", 50)
            end)
            schema:create("user_roles", function(t)
                t:id()
                t:string("user_id", 60)
                t:integer("role_id")
            end)
        end,
        down = function(schema)
            schema:drop("user_roles")
            schema:drop("roles")
        end,
    },
})

-- On server startup
OrvexORM.migrate()
```

### Adding a column later

```lua
OrvexORM.migrations({
    -- ... previous migrations ...
    {
        name = "004_add_email_to_users",
        up = function(schema)
            schema:table("users", function(t)
                t:string("email", 255)
            end)
        end,
        down = function(schema)
            schema:table("users", function(t)
                t:dropColumn("email")
            end)
        end,
    },
})

OrvexORM.migrate() -- Only migration 004 is executed
```

## How it works internally

1. OrvexORM creates an `orvex_migrations` table to track applied migrations
2. When you call `ORM.migrate()`, it compares your migrations with those already applied
3. New migrations are executed in order
4. Each batch of migrations receives a "batch" number (useful for rollback)
5. `ORM.rollback()` only reverts the last batch

:::caution In production
Migrations modify your database structure. Always make a **backup** before applying migrations in production. And test your migrations on a development server first!
:::
