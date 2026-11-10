---
sidebar_position: 10
slug: /examples
---

# Practical Examples

Ready-to-use examples for the most common use cases on a FiveM server. Models are defined at the top level of the script (no query); database calls are made in event handlers, commands or threads, which can wait for MySQL ([Async and threads](/docs/getting-started#async-and-threads)).

---

## Player System

### SQL Tables

```sql
CREATE TABLE `users` (
    `identifier` VARCHAR(60) NOT NULL,
    `money` INT NOT NULL DEFAULT 0,
    `bank` INT NOT NULL DEFAULT 0,
    `job` VARCHAR(50) NOT NULL DEFAULT 'unemployed',
    `group` VARCHAR(50) NOT NULL DEFAULT 'user',
    PRIMARY KEY (`identifier`)
);
```

### Lua Code

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    bank       = "number",
    job        = "string",
    group      = "string",
}, { primaryKey = "identifier" })

-- Player connection (deferrals: the connection waits for the database)
AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)

    local license = GetPlayerIdentifierByType(src, "license")
    User.findOrCreate({ identifier = license }, {
        money = 500,
        bank  = 5000,
        job   = "unemployed",
        group = "user",   -- `group` is a MySQL reserved word: the ORM quotes it
    })

    deferrals.done()
end)

-- Save on disconnect
AddEventHandler("playerDropped", function()
    local src = source
    local license = GetPlayerIdentifierByType(src, "license")

    User.upsert({
        identifier = license,
        money      = GetPlayerMoney(src),
        bank       = GetPlayerBank(src),
    })
end)

-- Give money
RegisterCommand("givemoney", function(src, args)
    local targetId = tonumber(args[1])
    local amount = tonumber(args[2])
    local license = GetPlayerIdentifierByType(targetId, "license")

    -- increment computes in MySQL (money = money + ?): no concurrent write is lost
    if amount and User.increment("money", amount, { identifier = license }) > 0 then
        print("Gave " .. amount .. "$ to " .. license)
    end
end, true)
```

---

## Vehicle System

### SQL Tables

```sql
CREATE TABLE `vehicles` (
    `id` INT AUTO_INCREMENT,
    `owner` VARCHAR(60) NOT NULL,
    `plate` VARCHAR(10) NOT NULL,
    `model` VARCHAR(50) NOT NULL,
    `garage` VARCHAR(50) DEFAULT 'main',
    `fuel` INT DEFAULT 100,
    PRIMARY KEY (`id`)
);
```

### Lua Code

```lua
local Vehicle = OrvexORM.model("vehicles", {
    id     = "number",
    owner  = "string",
    plate  = "string",
    model  = "string",
    garage = "string",
    fuel   = "number",
})

-- Relation: a player has many vehicles
User.hasMany("vehicles", Vehicle, { foreignKey = "owner" })
Vehicle.belongsTo("owner_player", User, { foreignKey = "owner" })

-- Buy a vehicle
RegisterCommand("buycar", function(src, args)
    local license = GetPlayerIdentifierByType(src, "license")
    local modelName = args[1]
    local plate = GeneratePlate()

    Vehicle.create({
        owner  = license,
        plate  = plate,
        model  = modelName,
        garage = "main",
        fuel   = 100,
    })

    print(license .. " bought a " .. modelName .. " (" .. plate .. ")")
end, false)

-- View my vehicles
RegisterCommand("mygarage", function(src)
    local license = GetPlayerIdentifierByType(src, "license")

    local vehicles = Vehicle.findAll({ owner = license, garage = "main" })

    for _, v in ipairs(vehicles) do
        print(v.plate .. " — " .. v.model .. " (" .. v.fuel .. "% fuel)")
    end
end, false)

-- Get a player's vehicles using the relation
RegisterCommand("checkvehicles", function(src)
    local license = GetPlayerIdentifierByType(src, "license")
    local player = User.find({ identifier = license })

    if player then
        local vehicles = player:get("vehicles")
        print(player.identifier .. " has " .. #vehicles .. " vehicle(s)")
    end
end, false)
```

---

## Role System (Permissions)

### SQL Tables

```sql
CREATE TABLE `roles` (
    `id` INT AUTO_INCREMENT,
    `name` VARCHAR(50) NOT NULL UNIQUE,
    PRIMARY KEY (`id`)
);

CREATE TABLE `user_roles` (
    `user_id` VARCHAR(60) NOT NULL,
    `role_id` INT NOT NULL,
    PRIMARY KEY (`user_id`, `role_id`)
);
```

### Lua Code

```lua
local Role = OrvexORM.model("roles", {
    id   = "number",
    name = "string",
})

-- Many-to-many relation
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",
    foreignKey = "user_id",
    otherKey   = "role_id",
})

-- Assign a role
RegisterCommand("giverole", function(src, args)
    local targetLicense = args[1]
    local roleName = args[2]

    local player = User.find({ identifier = targetLicense })
    local role = Role.find({ name = roleName })

    if player and role then
        player:attach("roles", role)
        print("Role " .. roleName .. " assigned to " .. targetLicense)
    end
end, true)

-- Remove a role
RegisterCommand("removerole", function(src, args)
    local targetLicense = args[1]
    local roleName = args[2]

    local player = User.find({ identifier = targetLicense })
    local role = Role.find({ name = roleName })

    if player and role then
        player:detach("roles", role)
        print("Role " .. roleName .. " removed from " .. targetLicense)
    end
end, true)

-- Check if a player has a role
RegisterCommand("checkadmin", function(src)
    local license = GetPlayerIdentifierByType(src, "license")
    local player = User.find({ identifier = license })

    if player then
        local roles = player:get("roles")
        for _, role in ipairs(roles) do
            if role.name == "admin" then
                print(license .. " is an admin!")
                return
            end
        end
        print(license .. " is not an admin")
    end
end, false)
```

---

## Leaderboard

```lua
-- Top 10 richest players
RegisterCommand("top10", function()
    local top = User.query()
        :where("money", ">", 0)
        :orderBy("money", "DESC")
        :limit(10)
        :get()

    for i, player in ipairs(top) do
        print(("#%d — %s : %d$"):format(i, player.identifier, player.money))
    end
end, false)

-- Server statistics
RegisterCommand("stats", function()
    local totalPlayers = User.count()
    local totalMoney   = User.sum("money")
    local avgMoney     = User.avg("money")
    local richest      = User.max("money")

    print(("Players: %d | Total money: %d$ | Average: %d$ | Max: %d$"):format(
        totalPlayers, totalMoney, avgMoney, richest
    ))
end, false)

-- Players by job
RegisterCommand("jobstats", function()
    local stats = User.query()
        :select("job, COUNT(*) as nb, SUM(money) as total")
        :groupBy("job")
        :orderBy("nb", "DESC")
        :get()

    for _, s in ipairs(stats) do
        print(("%s : %d players, %d$ total"):format(s.job, s.nb, s.total))
    end
end, false)
```

---

## Advanced Search

```lua
-- Search for players with combined filters
RegisterCommand("search", function(src, args)
    local results = User.query()
        :where({ job = { "IN", { "police", "medic" } } })
        :where({ money = { "BETWEEN", { 1000, 50000 } } })
        :where({ group = { "!=", "banned" } })
        :orderBy("money", "DESC")
        :limit(20)
        :get()

    print(#results .. " results found")
    for _, p in ipairs(results) do
        print(p.identifier .. " | " .. p.job .. " | " .. p.money .. "$")
    end
end, true)
```

---

## Pagination

```lua
-- Show players page by page
RegisterCommand("players", function(src, args)
    local pageNum = tonumber(args[1]) or 1

    local page = User.query()
        :orderBy("money", "DESC")
        :paginate(pageNum, 10)

    print(("Page %d/%d (%d players in total)"):format(
        page.page, page.lastPage, page.total
    ))

    for i, player in ipairs(page.data) do
        print(("  %s — %d$"):format(player.identifier, player.money))
    end
end, false)
```

---

## Money transfer

A transaction does not check the affected row count between two statements: a conditional debit that finds too little money does not stop the credit that follows. So the transfer is done with **one conditional statement**, whose result is checked (details in the [Transactions guide](/docs/guides/transactions#money-transfer)).

```lua
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

    return affected == 2  -- sender + receiver changed
end

RegisterCommand("pay", function(src, args)
    local from = GetPlayerIdentifierByType(src, "license")
    local to = GetPlayerIdentifierByType(tonumber(args[1]), "license")
    local amount = math.floor(tonumber(args[2]) or 0)

    if transferMoney(from, to, amount) then
        print(("Transfer of %d$ succeeded"):format(amount))
    else
        print("Transfer refused: insufficient balance or unknown player")
    end
end, false)
```

## Transaction callback

For several **unconditional** writes that must succeed together:

```lua
local function resetPlayer(identifier)
    return OrvexORM.transaction(function(tx)
        tx:delete("vehicles", { owner = identifier })
        tx:delete("inventories", { owner = identifier })
        tx:update("users", { money = 500, bank = 0 }, { identifier = identifier })
    end)
end
```

---

## findOrFail, exists, pluck

```lua
-- findOrFail: no need to check for nil
RegisterCommand("getplayer", function(src, args)
    local ok, err = pcall(function()
        local player = User.findOrFail({ identifier = args[1] })
        print(player.identifier .. " has " .. player.money .. "$")
    end)
    if not ok then
        print("Player not found: " .. args[1])
    end
end, true)

-- exists: check quickly without loading the data
RegisterCommand("checkplayer", function(src, args)
    if User.exists({ identifier = args[1] }) then
        print("The player exists")
    else
        print("Player not found")
    end
end, true)

-- pluck: just the values of one column
RegisterCommand("alljobs", function()
    local jobs = User.pluck("job")
    print("Jobs: " .. table.concat(jobs, ", "))
end, false)

-- chunkById: batch processing (constant cost, even on a large table)
RegisterCommand("resetall", function()
    User.query():chunkById(50, function(players, idx)
        print("Processing batch " .. idx .. " (" .. #players .. " players)")
        for _, p in ipairs(players) do
            p:update({ money = 0 })
        end
    end, "identifier")
    print("Every player has been reset")
end, true)
```

---

## Reusable scopes

```lua
-- Define scopes to filter easily
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
    group      = "string",
}, {
    primaryKey = "identifier",
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        vip  = function(b) b:where("group", "vip") end,
        cops = function(b) b:where("job", "police") end,
    },
})

RegisterCommand("vipcops", function()
    -- Use the scopes as methods
    local richPlayers = User.rich():orderBy("money", "DESC"):get()
    local vipCops     = User.vip():where("job", "police"):get()

    -- Combine with findAll and operators
    local richCops = User.findAll({
        job   = "police",
        money = { ">", 10000 },
    })
    print(#richPlayers, #vipCops, #richCops)
end, true)
```

---

## OrvexORM Studio

To view and manage your database without writing code, type in the txAdmin console:

```
orvexstudio
```

The studio opens in your browser with a secure link. Zero installation, it's built into the resource. See the full guide: [Studio](/docs/guides/studio).
