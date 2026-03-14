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
