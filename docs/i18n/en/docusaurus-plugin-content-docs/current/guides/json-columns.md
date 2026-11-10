---
sidebar_position: 9
---

# Automatic JSON Columns

OrvexORM can automatically convert **Lua tables** to **JSON** for database storage, and convert them back when you read them. This is perfect for saving positions, inventories, configurations, etc.

## The `"json"` type (explicit)

When you declare a field as `"json"`, OrvexORM knows it needs to convert tables to JSON:

```lua
local Player = ORM.model("players", {
    identifier = "string",
    position   = "json",     -- Lua table ↔ JSON automatically
    inventory  = "json",
})
```

### Saving

```lua
Player.create({
    identifier = "license:abc",
    position   = { x = 100.5, y = 200.3, z = 50.0 },
    inventory  = {
        { item = "bread", count = 5 },
        { item = "water", count = 3 },
    },
})
```

In the database, `position` is stored as:
```json
{"x":100.5,"y":200.3,"z":50.0}
```

### Reading

```lua
local player = Player.find({ identifier = "license:abc" })

-- It's automatically converted back to a Lua table
print(player.position.x)            -- 100.5
print(player.inventory[1].item)     -- "bread"
```

You don't have to do **anything** — the conversion is transparent.

:::caution Invalid JSON in the database
If a `"json"` column holds text that is not valid JSON (written by raw SQL or an external tool), reading it does not raise an error: the field keeps the **raw string** (as with `"auto"`) and a warning naming the field (never its content) is logged. Check `type(player.position) == "table"` before using it if the column can be written outside the ORM.
:::

## The `"auto"` type (automatic detection)

The `"auto"` type automatically detects whether a value needs to be converted:

- **On write**: if the value is a table -> encode as JSON
- **On read**: if the value looks like JSON (starts with `{` or `[`) -> decode to a table

```lua
local Config = ORM.model("configs", {
    key   = "string",
    value = "auto",     -- detects automatically
})

-- Save a table → stored as JSON
Config.create({ key = "spawn_point", value = { x = 100, y = 200, z = 50 } })

-- Save a string → stays a string
Config.create({ key = "server_name", value = "My RP Server" })

-- Save a number → stays a number
Config.create({ key = "max_players", value = 64 })

-- On read, everything is converted back correctly
local spawn = Config.find({ key = "spawn_point" })
print(spawn.value.x)  -- 100 (Lua table)

local name = Config.find({ key = "server_name" })
print(name.value)  -- "My RP Server" (string)
```

## Difference between `"json"` and `"auto"`

| | `"json"` | `"auto"` |
|---|---|---|
| Writing a table | Encodes to JSON | Encodes to JSON |
| Writing a string | No conversion | No conversion |
| Reading a JSON string | Decodes to table | Decodes to table |
| Reading a regular string | Decodes to table (may break) | Stays a string |
| Validation | Checks that it's a table | No strict validation |

:::tip Which one to choose?
- **`"json"`**: when the column **always** contains JSON (position, inventory, vehicle mods)
- **`"auto"`**: when the column can contain **different types** of values (configurations, metadata)
:::

## JSON column examples

### Player position

```lua
local Player = ORM.model("players", {
    identifier = "string",
    position   = "json",
})

-- Save
Player.upsert({
    identifier = "license:abc",
    position   = { x = 123.4, y = 567.8, z = 90.1, heading = 180.0 },
})
```

### Vehicle modifications

```lua
local Vehicle = ORM.model("vehicles", {
    id    = "number",
    plate = "string",
    mods  = "json",
})

Vehicle.create({
    plate = "ABC123",
    mods  = {
        engine   = 3,
        brakes   = 2,
        color    = { r = 255, g = 0, b = 0 },
        neon     = true,
    },
})
```

### Inventory

```lua
local Inventory = ORM.model("inventories", {
    id    = "number",
    owner = "string",
    items = "json",
})

Inventory.create({
    owner = "license:abc",
    items = {
        { name = "bread", count = 5, metadata = {} },
        { name = "water", count = 3, metadata = {} },
        { name = "phone", count = 1, metadata = { number = "555-0123" } },
    },
})

local inv = Inventory.find({ owner = "license:abc" })
for _, item in ipairs(inv.items) do
    print(item.name .. " x" .. item.count)
end
```

:::caution Transactions and raw SQL
JSON encoding is done by the model. The `tx:insert` / `tx:update` methods of [transactions](/docs/guides/transactions) and `OrvexORM.raw` / `rawExec` do not go through the model: encode yourself with `json.encode(value)`, and decode the rows of `OrvexORM.raw` with `json.decode`.
:::

### Recommended SQL table

For JSON columns, use the `JSON` or `LONGTEXT` type in MySQL:

```sql
CREATE TABLE `players` (
    `identifier` VARCHAR(60) NOT NULL,
    `position` JSON DEFAULT NULL,
    `inventory` JSON DEFAULT NULL,
    PRIMARY KEY (`identifier`)
);
```
