---
sidebar_position: 7
---

# Transactions

A **transaction** lets you execute multiple queries **atomically**: either everything succeeds, or nothing is applied. This is essential when you need to guarantee data consistency.

## Why use transactions?

Imagine this scenario: a player transfers $1000 to another player. You need to:

1. Remove $1000 from player A
2. Add $1000 to player B

If step 1 succeeds but step 2 fails (crash, error...), player A loses their money but player B receives nothing. The money vanishes!

With a **transaction**, if step 2 fails, step 1 is automatically rolled back. The money is protected.

## How it works

```lua
local tx = ORM.transaction()

-- Add operations (nothing is executed yet)
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("users", { money = 1000 }, { identifier = "license:def" })
tx:delete("logs", { identifier = "license:old" })

-- Everything is executed at once, atomically
local success = tx:commit()

if success then
    print("Transaction succeeded!")
else
    print("Transaction failed, everything was rolled back")
end
```

## Available methods

You can add any operation to a transaction:

### `tx:insert(table, data)`

```lua
tx:insert("users", { identifier = "license:abc", money = 500, job = "police" })
```

### `tx:update(table, data, where)`

```lua
tx:update("users", { money = 0 }, { identifier = "license:abc" })
```

### `tx:delete(table, where)`

```lua
tx:delete("users", { identifier = "license:abc" })
```

### `tx:upsert(table, data)`

```lua
tx:upsert("users", { identifier = "license:abc", money = 2000 })
```

### `tx:addRaw(sql, params)`

For custom SQL queries:

```lua
tx:addRaw("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
```

### `tx:commit()` -> `boolean`

Executes all queries at once. Returns `true` if everything succeeded.

### `tx:getQueries()` -> `table`

Returns the list of queries (useful for debugging).

## Practical examples

### Money transfer

```lua
local function transferMoney(fromId, toId, amount)
    local tx = ORM.transaction()

    -- Remove money from player A
    tx:addRaw(
        "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
        { amount, fromId, amount }
    )

    -- Add money to player B
    tx:addRaw(
        "UPDATE users SET money = money + ? WHERE identifier = ?",
        { amount, toId }
    )

    local success = tx:commit()

    if success then
        print(("Transfer of %d$ from %s to %s succeeded"):format(amount, fromId, toId))
    else
        print("Transfer failed — no changes applied")
    end

    return success
end
```

### Vehicle purchase

```lua
local function buyVehicle(playerId, vehicleModel, price)
    local tx = ORM.transaction()

    -- Charge the player
    tx:addRaw(
        "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
        { price, playerId, price }
    )

    -- Create the vehicle
    tx:insert("vehicles", {
        owner = playerId,
        model = vehicleModel,
        plate = GeneratePlate(),
        fuel  = 100,
    })

    return tx:commit()
end
```

### Deleting a player and their data

```lua
local function deletePlayer(identifier)
    local tx = ORM.transaction()

    tx:delete("vehicles", { owner = identifier })
    tx:delete("inventories", { owner = identifier })
    tx:delete("user_roles", { user_id = identifier })
    tx:delete("users", { identifier = identifier })

    return tx:commit()
end
```

:::tip When to use a transaction?
Use a transaction when you modify **multiple tables** or **multiple rows** that must remain consistent with each other. If a single operation fails, all others are rolled back.
:::
