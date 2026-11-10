---
sidebar_position: 1
---

# Models

A **model** is the link between your Lua code and a table in your database. It's through the model that you can create, read, update, and delete data without writing SQL.

## Creating a model

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

### The 3 arguments of `ORM.model()`

| Argument | Description | Example |
|---|---|---|
| `tableName` | The exact name of your MySQL table | `"users"` |
| `fields` | The columns and their types | `{ money = "number" }` |
| `opts` | Options (optional) | `{ primaryKey = "identifier" }` |

## Available types

When defining your schema, you need to specify what **type** of data each column contains:

| Type | Description | Example value |
|---|---|---|
| `"string"` | Text | `"license:abc"`, `"police"` |
| `"number"` | A number | `500`, `3.14` |
| `"boolean"` | True or false | `true`, `false` |
| `"json"` | A Lua table (saved as JSON) | `{ x = 1, y = 2 }` |
| `"date"` | A date | `"2024-03-15"` |
| `"datetime"` | Date and time | `"2024-03-15 14:30:00"` |
| `"timestamp"` | Timestamp | `"2024-03-15 14:30:00"` |

### The `json` type in detail

The `json` type is special: it lets you save **Lua tables** directly in the database. OrvexORM automatically converts them to JSON for storage, and converts them back to tables when you read them.

```lua
local Player = OrvexORM.model("players", {
    identifier = "string",
    position   = "json",    -- will be stored as '{"x":100,"y":200,"z":50}'
    inventory  = "json",    -- will be stored as '[{"item":"bread","count":5}]'
})

-- Save a position
Player.create({
    identifier = "license:abc",
    position   = { x = 100.0, y = 200.0, z = 50.0 },   -- Lua table
    inventory  = { { item = "bread", count = 5 } },
})

-- When you read it, it's automatically converted back to a Lua table
local p = Player.find({ identifier = "license:abc" })
print(p.position.x)  -- 100.0 (it's a table, not text)
```

## The primary key

The **primary key** (`primaryKey`) tells OrvexORM which column uniquely identifies each row.

```lua
-- Custom primary key
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

-- Default primary key (= "id")
local Vehicle = OrvexORM.model("vehicles", {
    id    = "number",
    plate = "string",
    model = "string",
})
-- No need to specify primaryKey, it defaults to "id"
```

:::info Why does this matter?
The primary key is automatically used by `:update()` and `:delete()` to know **which row** to modify or delete. If you set the primary key incorrectly, OrvexORM could modify the wrong row!
:::

## Common model examples

### Players

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    bank       = "number",
    job        = "string",
    group      = "string",
}, { primaryKey = "identifier" })
```

### Vehicles

```lua
local Vehicle = OrvexORM.model("vehicles", {
    id       = "number",
    owner    = "string",
    plate    = "string",
    model    = "string",
    garage   = "string",
    fuel     = "number",
    mods     = "json",
}, { primaryKey = "id" })
```

### Houses

```lua
local House = OrvexORM.model("houses", {
    id       = "number",
    owner    = "string",
    label    = "string",
    price    = "number",
    locked   = "boolean",
    coords   = "json",
}, { primaryKey = "id" })
```

### Inventory

```lua
local Inventory = OrvexORM.model("inventories", {
    id         = "number",
    owner      = "string",
    item_name  = "string",
    quantity   = "number",
    metadata   = "json",
}, { primaryKey = "id" })
```

## Reserved column names

Column and table names are always wrapped in backticks in the generated SQL: a `group`, `key`, `order` or `rank` column (like in the *Players* example above) works without any precaution. Names may only contain letters, digits, `_` and `.`.

## What the schema controls

The schema (`fields`) is not just a hint: a write with a key missing from the schema is **rejected** (`Unknown field 'x'`). Declare every column you write. The only exceptions: `created_at` / `updated_at` with `timestamps = true` and `deleted_at` with `softDelete = true`, which the ORM manages. See [Validation](/docs/guides/validation#unknown-columns).

## All options

| Option | Default | Role |
|---|---|---|
| `primaryKey` | `"id"` | Column that identifies a row |
| `timestamps` | `false` | Fills `created_at` / `updated_at` |
| `softDelete` | `false` | `delete()` fills `deleted_at` instead of deleting |
| `hooks` | `nil` | One hook per event (see [Hooks](/docs/api/model#hooks-lifecycle)) |
| `scopes` | `nil` | Reusable filters, callable as methods |
| `relations` | `nil` | Callback declaring the relations, run by `applyRelations()` |
| `adapter` | default | Adapter of this model only |
| `cache` | global cache | Cache of this model only (see [Cache](/docs/guides/cache#one-cache-per-model)) |

## Inline hooks and scopes

You can declare hooks and scopes directly in the model definition (one hook per event in `hooks`; use `User.hook(event, fn)` to add more):

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, {
    primaryKey = "identifier",
    hooks = {
        beforeCreate = function(data)
            data.money = data.money or 500  -- default value
        end,
        afterDelete = function(instance)
            print("Player deleted: " .. instance.identifier)
        end,
        -- Class-level write (User.update(data, where)): no instance
        afterBulkUpdate = function(data, where, affected)
            print(affected .. " player(s) updated")
        end,
    },
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where({ job = "police" }) end,
    },
})

-- Scopes are callable as direct methods!
local riches = User.rich():get()
local richCops = User.rich():where({ job = "police" }):get()
```

## Inline relations

You can also declare relations in the model definition through a callback:

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
}, {
    primaryKey = "identifier",
    relations = function(M)
        M.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
        M.hasOne("profile", Profile, { foreignKey = "user_id" })
    end,
})

-- Call once every model has been created
User.applyRelations()
```

:::tip Why `applyRelations()`?
Relations reference other models. When you declare them inline, those models must already exist. Call `applyRelations()` once all your models are created.
:::
