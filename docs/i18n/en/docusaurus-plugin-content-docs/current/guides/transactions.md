---
sidebar_position: 7
---

# Transactions

A **transaction** runs several queries **atomically**: either they all succeed, or none of them is applied. It is essential when several writes must stay consistent with each other.

## How it works

An OrvexORM transaction is a **list of queries**: you add them with the `tx:*` methods, then they are sent together to the driver (oxmysql's `transactionSync`, mysql-async's `MySQL.Async.transaction`) on `commit()`. If one of them **fails** (SQL error), MySQL rolls back all the others.

Two important consequences:

1. **Nothing runs before the commit.** So you cannot read a value or check the result of a query in the middle of a transaction.
2. **A query that matches no row is not a failure.** An `UPDATE ... WHERE money >= ?` that finds nothing succeeds (0 rows changed): the next queries still run and `commit()` returns `true`. See [Money transfer](#money-transfer) for the right way to do it.

### Callback syntax (recommended)

Pass a function: the commit happens automatically at the end.

```lua
local success = OrvexORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:abc", money = 500 })
    tx:update("users", { money = 1000 }, { identifier = "license:def" })
    tx:delete("logs", { identifier = "license:old" })
end)
-- Auto-commit at the end of the function!

if success then
    print("Transaction succeeded!")
else
    print("Transaction failed, nothing was applied")
end
```

If the function **raises an error**, nothing is sent: the transaction is not committed and the error propagates to the caller.

### Builder syntax (manual)

```lua
local tx = OrvexORM.transaction()

-- Add operations (nothing is executed yet)
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("users", { money = 1000 }, { identifier = "license:def" })
tx:delete("logs", { identifier = "license:old" })

-- Everything is executed at once, atomically
local success = tx:commit()
```

:::tip Which syntax should I choose?
The **callback syntax** is recommended: you never forget the `commit()`. The builder syntax is useful to build the transaction dynamically (loops, conditions...).
:::

## What is part of the transaction (and what is not)

:::danger Only `tx:*` methods are transactional
Inside the callback, a model call (`User.create`, `User.update`, `player:update`, `player:delete`...) is **executed immediately, outside the transaction**. It is not rolled back if the transaction fails.

```lua
OrvexORM.transaction(function(tx)
    tx:delete("vehicles", { owner = id })              -- in the transaction
    User.update({ money = 0 }, { identifier = id })    -- NOT in the transaction: already executed
end)
```
:::

The `tx:insert`, `tx:update`, `tx:upsert` and `tx:delete` methods build the SQL straight from the table name and the data. They **do not go through** the model, so:

| Model feature | With `tx:*` |
|---|---|
| Type validation and unknown-column rejection | No |
| JSON encoding of `json` / `auto` columns | No: encode yourself with `json.encode` |
| `created_at` / `updated_at` (timestamps) | No: set them yourself |
| Soft delete (`tx:delete` is a real `DELETE`) | No |
| Hooks (`beforeCreate`, `afterUpdate`...) | No |
| Cache invalidation | Yes, after a successful commit (global cache) |

The cache shared by models (`OrvexORM.enableCache`) is invalidated for every table written, **once the commit succeeds** (and flushed entirely for an `addRaw` whose table cannot be told). A model created with its own `opts.cache` is not covered: call `Model.flushCache()` after the transaction.

## Available methods

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

For custom SQL queries (always with `?`, never string concatenation):

```lua
tx:addRaw("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
```

### `tx:commit()` → `boolean`

Executes all the queries at once. Returns `true` if the driver applied everything, `false` otherwise. An empty transaction returns `true` without sending anything.

:::caution A failure can also raise an error
Depending on the driver, a failure can surface as a **Lua error** instead of `false` (oxmysql's `transactionSync` export raises the SQL error; mysql-async < 3.3 raises `atomic transactions need mysql-async >= 3.3`). If you always need a boolean, wrap the call in `pcall`:

```lua
local ok, result = pcall(OrvexORM.transaction, function(tx) ... end)
local success = ok and result == true
```
:::

### `tx:getQueries()` → `table`

Returns the list of pending queries (`{ query = "...", values = {...} }`), useful for debugging.

### Custom adapter

`OrvexORM.transaction(fn, adapter)` and `OrvexORM.transaction(adapter)` use the given adapter instead of the default one. If its driver does not implement `transaction`, `commit()` **raises an error**, unless the adapter was created with `OrvexAdapter.new(driver, { allowNonAtomicTransactions = true })`: the queries then run **one by one, without atomicity**; if one fails after others were applied, `commit()` returns `false` but still invalidates the cache of the tables it touched. See [setAdapter](/docs/api/orm#ormsetadapteradapter).

## Real-world examples

### Money transfer

The classic trap: a conditional debit (`AND money >= ?`) followed by a credit. If player A does not have enough money, the debit matches 0 rows **without an error**, the credit still runs and money appears out of nowhere. A transaction cannot prevent it, since it does not read the affected row count between two queries.

The safe solution: **one conditional statement** that debits and credits at the same time, then a check of its result. A single statement is atomic by nature (InnoDB): either both rows change, or none does.

```lua
--- Returns true if the transfer happened.
local function transferMoney(fromId, toId, amount)
    if fromId == toId or type(amount) ~= "number" or amount <= 0 then
        return false
    end

    local affected = OrvexORM.rawExec([[
        UPDATE users AS sender
        JOIN users AS receiver ON receiver.identifier = ?
        SET sender.money = sender.money - ?,
            receiver.money = receiver.money + ?
        WHERE sender.identifier = ? AND sender.money >= ?
    ]], { toId, amount, amount, fromId, amount })

    -- 2 rows changed (sender + receiver): transfer done.
    -- 0: insufficient balance or unknown player, nothing changed.
    return affected == 2
end
```

`OrvexORM.rawExec` returns what the driver returns for an `UPDATE`: the number of changed rows (oxmysql and mysql-async). It also invalidates the shared cache: here the whole cache, because OrvexORM cannot tell the table of an `UPDATE ... JOIN` (a simple statement only invalidates its table).

### Buying a vehicle

Two statements are needed here (an `INSERT` and an `UPDATE`): they cannot be merged. So **each statement is made conditional on the same check**, and the player's row is **locked** with `FOR UPDATE` so that no other purchase changes the balance in between:

```lua
--- Returns true if the vehicle was bought.
local function buyVehicle(playerId, vehicleModel, price)
    local plate = GeneratePlate()  -- your function, unique plates

    local committed = OrvexORM.transaction(function(tx)
        -- 1. Create the vehicle only if the player can pay, and lock their row
        tx:addRaw([[
            INSERT INTO vehicles (owner, model, plate, fuel)
            SELECT identifier, ?, ?, 100 FROM users
            WHERE identifier = ? AND money >= ?
            FOR UPDATE
        ]], { vehicleModel, plate, playerId, price })

        -- 2. Debit with the same condition (the row is locked since step 1)
        tx:addRaw(
            "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
            { price, playerId, price }
        )
    end)

    -- Insufficient balance: both statements matched 0 rows, nothing changed.
    -- So check that the vehicle really exists.
    return committed and Vehicle.exists({ plate = plate })
end
```

If the balance is too low, neither statement finds a row: nothing is created or debited, and `Vehicle.exists` returns `false`. If two purchases arrive at the same time, the second waits for the first one's lock, then sees the new balance. If MySQL detects a deadlock, the whole transaction fails.

:::tip Lock-free alternative
When the order allows it, debit first with a conditional statement **outside a transaction**, check the affected row count, then create the vehicle; if the creation fails, refund. It is easier to read, but not atomic: prefer the version above.
:::

### Deleting a player and their data

Here every statement is unconditional: the transaction is enough.

```lua
local function deletePlayer(identifier)
    local tx = OrvexORM.transaction()

    tx:delete("vehicles", { owner = identifier })
    tx:delete("inventories", { owner = identifier })
    tx:delete("user_roles", { user_id = identifier })
    tx:delete("users", { identifier = identifier })

    return tx:commit()
end
```

:::tip When should I use a transaction?
Use a transaction when several writes must succeed or fail **together** and none depends on the result of another. When a write depends on a condition (enough money, stock available...), put the condition **in every statement** and check the result, as in the examples above.
:::

:::info Async
`commit()` waits for the database: call it from a thread, an event or a command. See [Async and threads](/docs/getting-started#async-and-threads).
:::
