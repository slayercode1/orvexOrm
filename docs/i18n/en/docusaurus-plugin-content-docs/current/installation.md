---
sidebar_position: 2
slug: /installation
---

# Installation

## Prerequisites

- A working **FiveM** server
- **oxmysql** or **mysql-async** installed and configured (either one works)
- A **MySQL** or **MariaDB** database

:::info Compatibility
OrvexORM picks the MySQL driver by itself, on the first call. The details are in [MySQL driver](#mysql-driver).
:::

---

## Method 1: GitHub Release (recommended)

1. Download the latest release from [GitHub Releases](https://github.com/slayercode1/orvexOrm/releases)
2. Extract the `orvexorm` folder into your `resources/` directory
3. That's it!

```
your-server/
└── resources/
    └── orvexorm/
        ├── core/*.lua
        ├── database/*.lua
        ├── utils/*.lua
        ├── lib/*.lua
        └── fxmanifest.lua
```

---

## Start the resource

```cfg title="server.cfg"
# With oxmysql:
ensure oxmysql
ensure orvexorm

# OR with mysql-async:
ensure mysql-async
ensure orvexorm
```

:::caution Important
Your MySQL library (`oxmysql` or `mysql-async`) must **always** be started before `orvexorm`: detection happens on the first call, and if neither is running the call fails with `No MySQL library found. Ensure oxmysql or mysql-async is started before orvexorm.`
:::

## MySQL driver

On the first call, OrvexORM tries, in this order (the first match wins):

| Order | Condition | Mode | Functions used |
|---|---|---|---|
| 1 | oxmysql `MySQL` global (`@oxmysql/lib/MySQL.lua` loaded **inside orvexorm**) | `oxmysql_global` | `MySQL.query.await`, `MySQL.insert.await`, `MySQL.update.await`, `MySQL.transaction.await` |
| 2 | `MySQL.Async` global (`@mysql-async/lib/MySQL.lua` loaded **inside orvexorm**) | `mysql-async` | `MySQL.Async.fetchAll`, `execute`, `insert`, `transaction` |
| 3 | `oxmysql` resource started | `oxmysql_export` | `exports.oxmysql:executeSync`, `insertSync`, `updateSync`, `transactionSync` |
| 4 | `mysql-async` resource started | `mysql-async` | `exports['mysql-async']:mysql_fetch_all`, `mysql_execute`, `mysql_insert`, `mysql_transaction` |

The shipped `fxmanifest.lua` loads neither `MySQL.lua` file, so the **exports** (rows 3 and 4) are what is used. When both oxmysql and mysql-async are started, **oxmysql is chosen**. Modes 1 and 2 only apply if you add `@oxmysql/lib/MySQL.lua` or `@mysql-async/lib/MySQL.lua` to orvexorm's `server_scripts` yourself.

Good to know:

- Reads go through `MySQL.query` / `executeSync` (text protocol), not `MySQL.prepare`, which flattens single-row results and reads a table parameter as a batch.
- In `oxmysql_global` mode, a SQL error raises a Lua error (the `.await` form is used). Before, the thread could hang.
- **mysql-async 3.3 or later** is required for transactions: OrvexORM uses its native transaction (`MySQL.Async.transaction`), the only atomic way under mysql-async. On an older version, `commit()` raises `atomic transactions need mysql-async >= 3.3` and sends nothing.
- Under mysql-async, queries starting with `SELECT`, `SHOW`, `DESCRIBE` / `DESC`, `EXPLAIN` or `WITH` (including a parenthesised `(SELECT ...) UNION (SELECT ...)`) go through `fetchAll` and return rows. A read for which mysql-async returns nothing (`nil`, the query failed) raises an error instead of being taken for an empty result (and cached as such).
- Under mysql-async, a SQL error outside a transaction may never call the callback back (a mysql-async limitation): the thread then waits forever. Prefer oxmysql.
- Every call **waits** for the database: see [Async and threads](/docs/getting-started#async-and-threads).

## Use in your resource

Configure your resource to use OrvexORM:

```lua title="your-resource/fxmanifest.lua"
fx_version 'cerulean'
game 'common'

dependency 'orvexorm'
server_script '@orvexorm/lib/import.lua'   -- Loads OrvexORM, before your scripts

server_script 'server.lua'
```

```lua title="your-resource/server.lua"
-- OrvexORM is a global table of your resource
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

### How the import works

Every FiveM resource has its own Lua state. `lib/import.lua` reads the `server_script` list of orvexorm's `fxmanifest.lua` and runs those files **inside your resource**. As a result:

- `OrvexORM` is a real Lua table in your resource: instances (`player:update()`), query builders (`User.query():where()`) and transactions (`tx:insert()`) keep their methods. Every feature (migrations, schema builder, introspection, `OrvexAdapter`, `OrvexCache`) is available.
- **Each resource has its own ORM instance**: its own cache, `OrvexORM.debug()`, `enableCache()` and adapter. Enabling the cache in resource A does not enable it in resource B, and a write made by B does not invalidate A's cache. If several resources write to the same tables, keep the cache off or use a short TTL.
- Importing twice reloads nothing. Included on the client (`shared_script`), the file does nothing: the ORM is server only.
- If the `orvexorm` resource is missing, the import fails with a message asking you to add `dependency 'orvexorm'`.

:::danger Stop using `exports.orvexorm:lib()`
The export is kept for backward compatibility, but FiveM exports go through msgpack, which **drops metatables**: rows returned by `find`/`findAll`, `User.query()` builders and the transaction `tx` arrive **without their methods** (`player:update` is `nil`). The first call prints a warning in the console. Replace it with `server_script '@orvexorm/lib/import.lua'`.
:::

---

## Database configuration

If not already done, configure the connection in your `server.cfg`:

```cfg title="server.cfg"
set mysql_connection_string "mysql://user:password@localhost/your_database_name?charset=utf8mb4"
```

Replace:
- `user` with your MySQL username
- `password` with your password
- `your_database_name` with the name of your database

---

## Create your tables

You have **4 options**:

### Option A: `sync()` — Automatic creation

The simplest approach. Define your model and call `.sync()`:

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

CreateThread(function()
    User.sync() -- Creates the table if it doesn't exist
end)
```

### Option B: Migrations

For a serious project, use **migrations**:

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

CreateThread(function()
    OrvexORM.migrate()
end)
```

See the full guide: [Migrations](/docs/guides/migrations)

### Option C: Introspection — Existing table

If your table already exists, OrvexORM can detect it automatically:

```lua
CreateThread(function()
    -- Generate the model from the existing MySQL table (runs a DESCRIBE)
    local User = OrvexORM.fromTable("users")

    -- Or just retrieve the fields
    local fields, pk = OrvexORM.introspect("users")
end)
```

### Option D: Manual SQL

```sql
CREATE TABLE IF NOT EXISTS `users` (
    `identifier` VARCHAR(60) NOT NULL,
    `money` INT NOT NULL DEFAULT 0,
    `job` VARCHAR(50) NOT NULL DEFAULT 'unemployed',
    PRIMARY KEY (`identifier`)
);
```

:::tip Tip
You can use **HeidiSQL**, **phpMyAdmin**, or **DBeaver** to create your tables visually.
:::

---

## Verify the installation

Add this code to your resource to verify that everything works:

```lua
Citizen.CreateThread(function()
    local ORM = OrvexORM  -- loaded by @orvexorm/lib/import.lua
    ORM.debug(true)  -- Enable SQL logs

    local User = ORM.model("users", {
        identifier = "string",
        money      = "number",
    }, { primaryKey = "identifier" })

    User.sync()
    print("^2[OrvexORM] Installation OK !^0")
end)
```

You should see in the console (the first line comes from the `orvexorm` resource itself, at startup):
```
[OrvexORM] v1.3.0 loaded — ready to use
[OrvexORM] Installation OK !
```

Move on to the [Getting started](/docs/getting-started) page.
