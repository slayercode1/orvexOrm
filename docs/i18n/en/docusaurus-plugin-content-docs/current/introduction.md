---
sidebar_position: 1
slug: /introduction
---

# Introduction

## What is OrvexORM?

When you build a FiveM server, you often need to save things in a database: a player's money, their vehicles, their job, etc.

Normally, to do that, you have to write **SQL** by hand. It looks like this:

```lua
-- Without ORM: you write SQL yourself 😩
MySQL.prepare("SELECT * FROM users WHERE identifier = ?", { identifier }, function(result)
    -- ...
end)

MySQL.prepare("UPDATE users SET money = ? WHERE identifier = ?", { 1000, identifier }, function()
    -- ...
end)
```

It's tedious, repetitive, and error-prone.

**OrvexORM** lets you do the same thing, but in a much simpler way:

```lua
-- With OrvexORM: clean and readable 😎
local player = User.find({ identifier = "license:abc" })
player:update({ money = 1000 })
```

**That's it.** No need to write SQL. OrvexORM generates it automatically for you.

---

## Why use OrvexORM?

| Without ORM | With OrvexORM |
|---|---|
| You write SQL by hand | SQL is generated automatically |
| Risk of mistakes in queries | Impossible to get it wrong |
| Long and hard-to-read code | Short and clear code |
| No data validation | Types are checked automatically |
| Hard to maintain | Easy to evolve |

---

## How does it work in 30 seconds?

**Step 1**: You define a "model" (a representation of your SQL table):

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
})
```

**Step 2**: You use this model to interact with the database:

```lua
-- Create a player
User.create({ identifier = "license:abc", money = 500, job = "unemployed" })

-- Find a player
local player = User.find({ identifier = "license:abc" })

-- Update their money
player:update({ money = 1000 })

-- Delete the player
player:delete()
```

It's as simple as that. No SQL, no complicated callbacks.

---

## Prerequisites

To use OrvexORM, you need:

- A working **FiveM** server
- The **[oxmysql](https://github.com/overextended/oxmysql)** resource installed and configured
- A **MySQL** or **MariaDB** database connected to your server

If you already have a FiveM server with oxmysql, you're ready to go. Head over to the [Installation](/docs/installation) page.
