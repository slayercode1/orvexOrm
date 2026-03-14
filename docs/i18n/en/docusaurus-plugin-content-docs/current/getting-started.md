---
sidebar_position: 3
slug: /getting-started
---

# Getting Started

This guide will show you how to use OrvexORM from start to finish with a concrete example: **managing the players on your server**.

## The "Model" concept

A **model** is like a blueprint that describes a table in your database.

Imagine your `users` table in MySQL. It has columns: `identifier`, `money`, `job`. The model is the same thing but in Lua:

```lua
local User = OrvexORM.model("users", {
    identifier = "string",   -- the column type
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

Let's break down this code:

| Part | Meaning |
|---|---|
| `"users"` | The name of your table in MySQL |
| `identifier = "string"` | The `identifier` column contains text |
| `money = "number"` | The `money` column contains a number |
| `primaryKey = "identifier"` | The column that uniquely identifies each player |

:::info What is a primaryKey?
The **primaryKey** (primary key) is the column that uniquely identifies each row. For FiveM players, it's often `identifier` (the player's license). For other tables, it can be `id` (an auto-incrementing number).

If you don't set a `primaryKey`, OrvexORM will use `id` by default.
:::

---

## Create a player

To add a new player to the database:

```lua
local player = User.create({
    identifier = "license:abc123",
    money      = 500,
    job        = "unemployed",
})

print(player.identifier)  -- "license:abc123"
print(player.money)        -- 500
print(player.job)          -- "unemployed"
```

This code automatically generates this SQL query:

```sql
INSERT INTO users (identifier, job, money) VALUES (?, ?, ?)
```

You don't need to write it yourself!

---

## Find a player

To retrieve a player that already exists:

```lua
local player = User.find({ identifier = "license:abc123" })

if player then
    print("Player found! They have " .. player.money .. "$")
else
    print("Player not found")
end
```

:::tip Always check if the player exists
`User.find()` returns `nil` if no player matches. Always check with `if player then` before using the result.
:::

---

## Update a player

Once you've found a player, you can update them:

```lua
local player = User.find({ identifier = "license:abc123" })

if player then
    player:update({ money = 1000, job = "police" })
    print(player.money)  -- 1000 (the value is also updated locally)
end
```

:::caution Watch the syntax
Notice the `:` (colon) in `player:update()`. This is because `update` is an **instance** method — it applies to a specific player that has already been found.

- `player:update()` = update THIS player (with `:`)
- `User.update()` = update players by condition (with `.`)

We'll cover the difference in more detail on the [CRUD](/docs/guides/crud) page.
:::

---

## Delete a player

```lua
local player = User.find({ identifier = "license:abc123" })

if player then
    player:delete()
    print("Player deleted!")
end
```

---

## Full example

Here's a realistic example for a FiveM server — a system that saves a player's money when they disconnect:

```lua
-- server.lua

-- Define the model
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- When a player connects
AddEventHandler("playerConnecting", function()
    local src = source
    local identifier = GetPlayerIdentifierByType(src, "license")

    -- Find or create the player
    local player = User.find({ identifier = identifier })

    if not player then
        player = User.create({
            identifier = identifier,
            money      = 500,
            job        = "unemployed",
        })
        print("New player created: " .. identifier)
    else
        print("Existing player: " .. identifier .. " with " .. player.money .. "$")
    end
end)

-- When a player disconnects, save their money
AddEventHandler("playerDropped", function()
    local src = source
    local identifier = GetPlayerIdentifierByType(src, "license")
    local currentMoney = GetPlayerMoney(src) -- your function to get the money

    User.update({ money = currentMoney }, { identifier = identifier })
    print("Money saved for " .. identifier)
end)
```

---

## What's next?

Now that you know the basics, you can explore the guides:

| Guide | Description |
|---|---|
| **[Models](/docs/guides/models)** | Everything about creating and configuring models |
| **[CRUD](/docs/guides/crud)** | Create, read, update, delete in detail |
| **[Query Builder](/docs/guides/query-builder)** | Advanced queries: filters, sorting, pagination, joins |
| **[Relations](/docs/guides/relations)** | Link tables together (a player's vehicles, etc.) |
| **[Migrations](/docs/guides/migrations)** | Create your tables automatically or manage database evolution |
| **[Transactions](/docs/guides/transactions)** | Execute multiple queries atomically |
| **[Cache](/docs/guides/cache)** | Reduce SQL queries with a TTL cache |
| **[JSON](/docs/guides/json-columns)** | Store Lua tables as JSON automatically |
