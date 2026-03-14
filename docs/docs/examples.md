---
sidebar_position: 10
slug: /examples
---

# Exemples concrets

Des exemples prets a l'emploi pour les cas d'usage les plus courants sur un serveur FiveM.

---

## Systeme de joueurs

### Tables SQL

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

### Code Lua

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    bank       = "number",
    job        = "string",
    group      = "string",
}, { primaryKey = "identifier" })

-- Connexion d'un joueur
AddEventHandler("playerConnecting", function()
    local src = source
    local license = GetPlayerIdentifierByType(src, "license")

    local player = User.find({ identifier = license })

    if not player then
        player = User.create({
            identifier = license,
            money      = 500,
            bank       = 5000,
            job        = "unemployed",
            group      = "user",
        })
    end
end)

-- Sauvegarder a la deconnexion
AddEventHandler("playerDropped", function()
    local src = source
    local license = GetPlayerIdentifierByType(src, "license")

    User.upsert({
        identifier = license,
        money      = GetPlayerMoney(src),
        bank       = GetPlayerBank(src),
    })
end)

-- Donner de l'argent
RegisterCommand("givemoney", function(src, args)
    local targetId = tonumber(args[1])
    local amount = tonumber(args[2])
    local license = GetPlayerIdentifierByType(targetId, "license")

    local player = User.find({ identifier = license })
    if player then
        player:update({ money = player.money + amount })
        print("Donne " .. amount .. "$ a " .. license)
    end
end, true)
```

---

## Systeme de vehicules

### Tables SQL

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

### Code Lua

```lua
local Vehicle = OrvexORM.model("vehicles", {
    id     = "number",
    owner  = "string",
    plate  = "string",
    model  = "string",
    garage = "string",
    fuel   = "number",
})

-- Relation : un joueur a plusieurs vehicules
User.hasMany("vehicles", Vehicle, { foreignKey = "owner" })
Vehicle.belongsTo("owner_player", User, { foreignKey = "owner" })

-- Acheter un vehicule
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

    print(license .. " a achete un " .. modelName .. " (" .. plate .. ")")
end, false)

-- Voir mes vehicules
RegisterCommand("mygarage", function(src)
    local license = GetPlayerIdentifierByType(src, "license")

    local vehicles = Vehicle.findAll({ owner = license, garage = "main" })

    for _, v in ipairs(vehicles) do
        print(v.plate .. " — " .. v.model .. " (" .. v.fuel .. "% fuel)")
    end
end, false)

-- Chercher les vehicules d'un joueur avec la relation
RegisterCommand("checkvehicles", function(src)
    local license = GetPlayerIdentifierByType(src, "license")
    local player = User.find({ identifier = license })

    if player then
        local vehicles = player:get("vehicles")
        print(player.identifier .. " a " .. #vehicles .. " vehicule(s)")
    end
end, false)
```

---

## Systeme de roles (permissions)

### Tables SQL

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

### Code Lua

```lua
local Role = OrvexORM.model("roles", {
    id   = "number",
    name = "string",
})

-- Relation many-to-many
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",
    foreignKey = "user_id",
    otherKey   = "role_id",
})

-- Donner un role
RegisterCommand("giverole", function(src, args)
    local targetLicense = args[1]
    local roleName = args[2]

    local player = User.find({ identifier = targetLicense })
    local role = Role.find({ name = roleName })

    if player and role then
        player:attach("roles", role)
        print("Role " .. roleName .. " attribue a " .. targetLicense)
    end
end, true)

-- Retirer un role
RegisterCommand("removerole", function(src, args)
    local targetLicense = args[1]
    local roleName = args[2]

    local player = User.find({ identifier = targetLicense })
    local role = Role.find({ name = roleName })

    if player and role then
        player:detach("roles", role)
        print("Role " .. roleName .. " retire de " .. targetLicense)
    end
end, true)

-- Verifier si un joueur a un role
RegisterCommand("checkadmin", function(src)
    local license = GetPlayerIdentifierByType(src, "license")
    local player = User.find({ identifier = license })

    if player then
        local roles = player:get("roles")
        for _, role in ipairs(roles) do
            if role.name == "admin" then
                print(license .. " est admin !")
                return
            end
        end
        print(license .. " n'est pas admin")
    end
end, false)
```

---

## Classement (Leaderboard)

```lua
-- Top 10 des joueurs les plus riches
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

-- Statistiques du serveur
RegisterCommand("stats", function()
    local totalPlayers = User.count()
    local totalMoney   = User.sum("money")
    local avgMoney     = User.avg("money")
    local richest      = User.max("money")

    print(("Joueurs: %d | Argent total: %d$ | Moyenne: %d$ | Max: %d$"):format(
        totalPlayers, totalMoney, avgMoney, richest
    ))
end, false)

-- Joueurs par job
RegisterCommand("jobstats", function()
    local stats = User.query()
        :select("job, COUNT(*) as nb, SUM(money) as total")
        :groupBy("job")
        :orderBy("nb", "DESC")
        :get()

    for _, s in ipairs(stats) do
        print(("%s : %d joueurs, %d$ au total"):format(s.job, s.nb, s.total))
    end
end, false)
```

---

## Recherche avancee

```lua
-- Chercher des joueurs avec des filtres combines
RegisterCommand("search", function(src, args)
    local results = User.query()
        :where({ job = { "IN", { "police", "medic" } } })
        :where({ money = { "BETWEEN", { 1000, 50000 } } })
        :where({ group = { "!=", "banned" } })
        :orderBy("money", "DESC")
        :limit(20)
        :get()

    print(#results .. " resultats trouves")
    for _, p in ipairs(results) do
        print(p.identifier .. " | " .. p.job .. " | " .. p.money .. "$")
    end
end, true)
```

---

## Pagination

```lua
-- Afficher les joueurs page par page
RegisterCommand("players", function(src, args)
    local pageNum = tonumber(args[1]) or 1

    local page = User.query()
        :orderBy("money", "DESC")
        :paginate(pageNum, 10)

    print(("Page %d/%d (%d joueurs au total)"):format(
        page.page, page.lastPage, page.total
    ))

    for i, player in ipairs(page.data) do
        print(("  %s — %d$"):format(player.identifier, player.money))
    end
end, false)
```

---

## Transaction callback

```lua
-- Transfert d'argent securise avec la syntaxe callback
local function transferMoney(fromId, toId, amount)
    local success = OrvexORM.transaction(function(tx)
        tx:addRaw(
            "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
            { amount, fromId, amount }
        )
        tx:addRaw(
            "UPDATE users SET money = money + ? WHERE identifier = ?",
            { amount, toId }
        )
    end)

    if success then
        print(("Transfert de %d$ reussi"):format(amount))
    else
        print("Transfert echoue — rien n'a ete modifie")
    end
end
```

---

## findOrFail, exists, pluck

```lua
-- findOrFail : pas besoin de verifier nil
RegisterCommand("getplayer", function(src, args)
    local ok, err = pcall(function()
        local player = User.findOrFail({ identifier = args[1] })
        print(player.identifier .. " a " .. player.money .. "$")
    end)
    if not ok then
        print("Joueur introuvable : " .. args[1])
    end
end, true)

-- exists : verifier rapidement sans charger les donnees
RegisterCommand("checkplayer", function(src, args)
    if User.exists({ identifier = args[1] }) then
        print("Le joueur existe")
    else
        print("Joueur introuvable")
    end
end, true)

-- pluck : juste les valeurs d'une colonne
RegisterCommand("alljobs", function()
    local jobs = User.pluck("job")
    print("Jobs : " .. table.concat(jobs, ", "))
end, false)

-- chunk : traiter par lots (utile pour les grosses tables)
RegisterCommand("resetall", function()
    User.query():chunk(50, function(players, idx)
        print("Traitement lot " .. idx .. " (" .. #players .. " joueurs)")
        for _, p in ipairs(players) do
            p:update({ money = 0 })
        end
    end)
    print("Tous les joueurs ont ete reinitialises")
end, true)
```

---

## Scopes reutilisables

```lua
-- Definir des scopes pour filtrer facilement
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

-- Utiliser les scopes comme methodes
local richPlayers = User.rich():orderBy("money", "DESC"):get()
local vipCops     = User.vip():where("job", "police"):get()

-- Combiner avec findAll et operateurs
local richCops = User.findAll({
    job   = "police",
    money = { ">", 10000 },
})
```

---

## OrvexORM Studio

Pour visualiser et gerer ta base de donnees sans ecrire de code, tape dans la console txAdmin :

```
orvexstudio
```

Le studio s'ouvre dans ton navigateur avec un lien securise. Zero installation, c'est integre a la ressource. Voir le guide complet : [Studio](/docs/guides/studio).
