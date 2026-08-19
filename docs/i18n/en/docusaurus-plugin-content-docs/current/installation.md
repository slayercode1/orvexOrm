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
OrvexORM automatically detects which MySQL library is installed on your server. No configuration needed — it works with both. Under the hood, the driver uses `MySQL.query`/`MySQL.insert`/`MySQL.update` with the oxmysql global API (instead of `MySQL.prepare`, which flattens single-row results), and `MySQL.Async.insert` under mysql-async to get the real `insertId`.
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
Your MySQL library (`oxmysql` or `mysql-async`) must **always** be started before `orvexorm`.
:::

## Use in your resource

Configure your resource to use OrvexORM:

**Option A: Direct import (recommended)**

```lua title="your-resource/fxmanifest.lua"
fx_version 'cerulean'
game 'common'

dependency 'orvexorm'

server_scripts {
    '@orvexorm/lib/import.lua',   -- Load OrvexORM
    'server.lua',
}
```

:::tip Migrations and schema
To use migrations or schema features, use the full `@orvexorm/` include pattern in your `fxmanifest.lua`. All features (migrations, schema builder, introspection) are available through the direct import.
:::

```lua title="your-resource/server.lua"
-- OrvexORM is available globally
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

**Option B: Via exports**

```lua title="your-resource/server.lua"
local ORM = exports.orvexorm:lib()

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })
```

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

You have **3 options**:

### Option A: `sync()` — Automatic creation

The simplest approach. Define your model and call `.sync()`:

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

User.sync() -- Creates the table if it doesn't exist
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

OrvexORM.migrate()
```

See the full guide: [Migrations](/docs/guides/migrations)

### Option C: Introspection — Existing table

If your table already exists, OrvexORM can detect it automatically:

```lua
-- Generate the model from the existing MySQL table
local User = OrvexORM.fromTable("users")

-- Or just retrieve the fields
local fields, pk = OrvexORM.introspect("users")
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
    local ORM = OrvexORM or exports.orvexorm:lib()
    ORM.debug(true)  -- Enable SQL logs

    local User = ORM.model("users", {
        identifier = "string",
        money      = "number",
    }, { primaryKey = "identifier" })

    User.sync()
    print("^2[OrvexORM] Installation OK !^0")
end)
```

You should see in the console:
```
[OrvexORM] v1.2.0 loaded — ready to use
[OrvexORM] Installation OK !
```

Move on to the [Getting started](/docs/getting-started) page.
