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

-- Creates the "users" table if it doesn't exist (in a thread: sync() waits for the database)
CreateThread(function()
    User.sync()
end)
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
| `"date"` | `DATE` |
| `"datetime"` | `DATETIME` |
| `"timestamp"` | `TIMESTAMP` |
| `"auto"` | `TEXT` |

The **primary key** is automatically configured as `NOT NULL`. If it's a `"number"` field, it's also `AUTO_INCREMENT`.

If the primary key is **not declared** in `fields` (for example the default `id`, which you did not list), `sync()` adds it as the first column: `` `id` INT UNSIGNED NOT NULL AUTO_INCREMENT ``, the same column as `t:id()`. A declared primary key is kept as is.

```lua
local Log = OrvexORM.model("logs", { message = "string" })  -- primaryKey = "id", not declared
-- sync() creates: `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `message` VARCHAR(255), PRIMARY KEY (`id`)
```

With `timestamps = true`, `sync()` also adds `created_at` and `updated_at`; with `softDelete = true`, `deleted_at`.

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
CreateThread(function()
    local count = OrvexORM.migrate()
    print(count .. " migration(s) applied")
end)
```

OrvexORM keeps track of already applied migrations in an `orvex_migrations` table. Previously executed migrations are never replayed.

### Several resources on the same database

`orvex_migrations` is shared by every resource using the database. Each row records the **resource** that applied it (`resource` column, added automatically to a table created by an earlier version; older rows have no resource and belong to the resource that lists them).

:::caution Prefix your migration names
A migration name is **unique across the whole database**. If two resources each have a `001_create_users` migration, the second one to call `migrate()` gets an error before anything runs:

```
[OrvexORM] Migration '001_create_users' is already recorded by resource 'garage': migration names are shared by every resource on the database, prefix them with your resource name
```

So prefix every name with your resource's: `"garage_001_create_vehicles"`, `"bank_001_create_accounts"`.
:::

Two resources calling `migrate()` at the same instant may get the same batch number. This is harmless: `rollback()` only touches the rows of the resource that calls it.

### When a migration fails

`migrate()` stops at the **first** failing migration and **raises an error**:

```
[OrvexORM] Migration of migration '003_create_roles' failed (2 migration(s) applied before it): <MySQL error>
```

- the failing migration is **not** recorded in `orvex_migrations`: it will be retried on the next `migrate()`;
- the following migrations are **not** run;
- the earlier migrations of the same call stay applied and recorded.

A statement for which the driver returns `nil` (oxmysql does on a SQL error, without raising) counts as a failure. So does an error raised in your `up` function.

To decide what to do at startup, catch the error:

```lua
CreateThread(function()
    local ok, result = pcall(OrvexORM.migrate)
    if not ok then
        print("^1[Migrations] " .. tostring(result) .. "^0")
        return  -- do not start the rest of the script
    end
    print(result .. " migration(s) applied")
end)
```

:::caution MySQL cannot roll back DDL
`CREATE TABLE`, `ALTER TABLE` and `DROP TABLE` are committed immediately by MySQL, even inside a transaction. If a migration has several statements and the third one fails, the first two **stay applied**. Fix the database by hand (or write an idempotent `up`, for example with `dropIfExists`) before running it again. One change per migration limits the problem.
:::

### Rolling back migrations

```lua
CreateThread(function()
    local count = OrvexORM.rollback()
    print(count .. " migration(s) rolled back")
end)
```

`rollback()` reverts the **last batch of the resource that calls it** (its last `migrate()` call), newest first. Only the migrations this resource registers with `OrvexORM.migrations` are rolled back: another resource's migrations are never touched. If a `down` fails, its migration **stays recorded**, the next ones are not rolled back, and an error is raised, as with `migrate()`.

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
    t:date("birth_date")          -- DATE
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
| `t:date(name)` | `DATE` | Date only |
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

    -- Indexes and foreign keys (ADD INDEX / ADD CONSTRAINT)
    t:index("email")                         -- idx_email
    t:unique({ "email", "verified" })        -- uq_email_verified
    t:foreignKey("job_id", "jobs", "id", { onDelete = "SET NULL" })  -- fk_users_job_id
end)
```

Within one `table()` call, the `ALTER TABLE` statements are generated in this order: added columns, dropped columns, renames, **then** indexes, **then** foreign keys. An index or a foreign key can therefore target a column added or renamed in the same call. `t:id()` inside `table()` adds the column with `AUTO_INCREMENT PRIMARY KEY`.

### Indexes and foreign keys

| Method | Effect | Default name |
|---|---|---|
| `t:index(columns, name?)` | Plain index (`columns`: one name or an array) | `idx_<columns>` |
| `t:unique(columns, name?)` | Unique index | `uq_<columns>` |
| `t:foreignKey(column, refTable, refColumn, opts?)` | Foreign key; `opts.onDelete` / `opts.onUpdate` among `CASCADE` (default), `RESTRICT`, `SET NULL`, `NO ACTION`, `SET DEFAULT` | `fk_<table>_<column>` |
| `t:enum(name, values)` | `ENUM(...)` column | — |
| `t:timestamps()` | `created_at` and `updated_at` (`DATETIME`, filled by MySQL) | — |
| `t:softDeletes()` | `deleted_at` (`DATETIME NULL`) | — |

They work in `schema:create()` as well as in `schema:table()`.

### Execution order

Each schema builder call (`create`, `table`, `drop`, `dropIfExists`, `raw`) adds its statements **in the order you call it**, and several `table()` calls in the same migration add up:

```lua
up = function(schema)
    schema:create("jobs", function(t) t:id() t:string("label") end)
    schema:table("users", function(t) t:integer("job_id") end)
    schema:table("users", function(t)
        t:foreignKey("job_id", "jobs", "id")  -- jobs already exists: created just before
    end)
    schema:raw("INSERT INTO jobs (label) VALUES ('unemployed')")
end
```

`t:renameColumn` generates `RENAME COLUMN`, which requires MySQL 8.0+ or MariaDB 10.5+.

`schema:toSQL()` returns a copy of the statement list, handy to check a migration without running it.

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
CreateThread(function()
    OrvexORM.migrate()
end)
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

CreateThread(function()
    OrvexORM.migrate() -- Only migration 004 is executed
end)
```

## How it works internally

1. OrvexORM creates an `orvex_migrations` table to track applied migrations
2. When you call `OrvexORM.migrate()`, it compares your migrations with those already applied
3. New migrations are executed in order; the statements of each `up` are sent in call order
4. A migration is only recorded once all its statements succeeded; on the first failure, `migrate()` raises an error. Writing the tracking row is checked too: if it fails, `migrate()` raises an error
5. Each batch of migrations receives a "batch" number and the resource name (useful for rollback)
6. `OrvexORM.rollback()` only reverts the last batch of the resource that calls it

`OrvexORM.migrate()` and `rollback()` use the current resource's name (`GetCurrentResourceName()`). The low-level module accepts an explicit name: `OrvexMigration.migrate(migrations, adapter, resource?)` and `OrvexMigration.rollback(migrations, adapter, resource?)`.

:::caution In production
Migrations modify your database structure. Always make a **backup** before applying migrations in production. And test your migrations on a development server first!
:::
