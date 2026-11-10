---
sidebar_position: 3
slug: /getting-started
---

# Premier pas

Ce guide va te montrer comment utiliser OrvexORM de A a Z avec un exemple concret : **gerer les joueurs de ton serveur**.

## Le concept de "Model"

Un **modele**, c'est comme un plan qui decrit une table de ta base de donnees.

Imagine ta table `users` dans MySQL. Elle a des colonnes : `identifier`, `money`, `job`. Le modele, c'est la meme chose mais en Lua :

```lua
local User = OrvexORM.model("users", {
    identifier = "string",   -- le type de la colonne
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

Decomposons ce code :

| Partie | Signification |
|---|---|
| `"users"` | Le nom de ta table dans MySQL |
| `identifier = "string"` | La colonne `identifier` contient du texte |
| `money = "number"` | La colonne `money` contient un nombre |
| `primaryKey = "identifier"` | La colonne qui identifie chaque joueur de facon unique |

:::info C'est quoi une primaryKey ?
La **primaryKey** (cle primaire), c'est la colonne qui permet d'identifier chaque ligne de facon unique. Pour les joueurs FiveM, c'est souvent `identifier` (le license du joueur). Pour d'autres tables, ca peut etre `id` (un numero qui augmente tout seul).

Si tu ne mets pas de `primaryKey`, OrvexORM utilisera `id` par defaut.
:::

---

## Async et threads

Chaque appel qui touche la base (`create`, `find`, `update`, `query():get()`, `sync()`, `migrate()`, `transaction`...) **attend la reponse de MySQL** : il suspend (*yield*) la coroutine FiveM courante jusqu'au resultat. Il doit donc tourner dans un contexte qui peut etre suspendu :

| Contexte | Appels a l'ORM ? |
|---|---|
| `Citizen.CreateThread(function() ... end)` / `CreateThread` | Oui |
| Handler `AddEventHandler` / `RegisterNetEvent` | Oui |
| Callback de `RegisterCommand` | Oui |
| Niveau superieur d'un fichier (`server.lua` charge par le manifest) | **Non** |
| Definir un modele, une relation, un scope ou un hook (`OrvexORM.model`, `User.hasMany`...) | Oui partout : aucune requete |

Hors thread, l'appel echoue avec un message explicite :

```
OrvexORM: database calls yield and must run inside Citizen.CreateThread, an event handler or another thread (...)
```

### Le schema d'un script serveur

```lua title="server.lua"
-- 1. Niveau superieur : seulement des definitions (aucune requete)
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

local ready = false

-- 2. Un thread de demarrage : migrations / sync une seule fois, avant le reste
CreateThread(function()
    OrvexORM.migrate()   -- ou User.sync()
    ready = true
end)

-- 3. Les handlers utilisent les modeles
RegisterNetEvent("monScript:getMoney", function()
    local src = source
    if not ready then return end
    local player = User.find({ identifier = GetPlayerIdentifierByType(src, "license") })
    TriggerClientEvent("monScript:money", src, player and player.money or 0)
end)
```

:::tip Ordre migrations / premieres requetes
Les threads tournent en parallele : un handler peut s'executer avant la fin de `migrate()`. Si tes handlers ont besoin des tables, attends la fin des migrations (un drapeau comme `ready` ci-dessus, ou fais tes migrations dans une ressource demarree avant).
:::

:::caution playerConnecting
`playerConnecting` laisse le joueur entrer des que le handler cede la main, sauf si tu utilises les **deferrals**. Pour lire la base pendant la connexion :

```lua
AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)                       -- obligatoire avant d'utiliser les deferrals
    deferrals.update("Chargement de ton profil...")

    local license = GetPlayerIdentifierByType(src, "license")
    local player = User.findOrCreate({ identifier = license }, { money = 500 })

    deferrals.done()              -- ou deferrals.done("raison") pour refuser
end)
```
:::

Dans la suite de la documentation, les extraits de code supposent qu'ils tournent dans un de ces contextes.

---

## Creer un joueur

Pour ajouter un nouveau joueur dans la base de donnees :

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

Ce code genere automatiquement cette requete SQL :

```sql
INSERT INTO users (identifier, job, money) VALUES (?, ?, ?)
```

Tu n'as pas besoin de l'ecrire toi-meme !

---

## Chercher un joueur

Pour retrouver un joueur qui existe deja :

```lua
local player = User.find({ identifier = "license:abc123" })

if player then
    print("Joueur trouve ! Il a " .. player.money .. "$")
else
    print("Joueur introuvable")
end
```

:::tip Toujours verifier si le joueur existe
`User.find()` retourne `nil` si aucun joueur ne correspond. Pense toujours a verifier avec `if player then` avant d'utiliser le resultat.
:::

---

## Modifier un joueur

Une fois que tu as trouve un joueur, tu peux le modifier :

```lua
local player = User.find({ identifier = "license:abc123" })

if player then
    player:update({ money = 1000, job = "police" })
    print(player.money)  -- 1000 (la valeur est aussi mise a jour localement)
end
```

:::caution Attention a la syntaxe
Remarque le `:` (deux-points) dans `player:update()`. C'est parce que `update` est une methode d'**instance** — elle s'applique a un joueur specifique qu'on a deja trouve.

- `player:update()` = modifier CE joueur (avec `:`)
- `User.update()` = modifier des joueurs par condition (avec `.`)

On verra la difference plus en detail dans la page [CRUD](/docs/guides/crud).
:::

---

## Supprimer un joueur

```lua
local player = User.find({ identifier = "license:abc123" })

if player then
    player:delete()
    print("Joueur supprime !")
end
```

---

## Exemple complet

Voici un exemple realiste pour un serveur FiveM — un systeme qui sauvegarde l'argent d'un joueur quand il se deconnecte :

```lua
-- server.lua

-- Definir le modele (niveau superieur : aucune requete)
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- Creer la table au demarrage, dans un thread
CreateThread(function()
    User.sync()
end)

-- Quand un joueur se connecte (deferrals : la connexion attend la base)
AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)

    local identifier = GetPlayerIdentifierByType(src, "license")

    -- Chercher ou creer le joueur
    local player, created = User.findOrCreate(
        { identifier = identifier },
        { money = 500, job = "unemployed" }
    )

    if created then
        print("Nouveau joueur cree : " .. identifier)
    else
        print("Joueur existant : " .. identifier .. " avec " .. player.money .. "$")
    end
    deferrals.done()
end)

-- Quand un joueur se deconnecte, sauvegarder son argent
AddEventHandler("playerDropped", function()
    local src = source
    local identifier = GetPlayerIdentifierByType(src, "license")
    local currentMoney = GetPlayerMoney(src) -- ta fonction pour recuperer l'argent

    User.update({ money = currentMoney }, { identifier = identifier })
    print("Argent sauvegarde pour " .. identifier)
end)
```

---

## Et ensuite ?

Maintenant que tu connais les bases, tu peux explorer les guides :

| Guide | Description |
|---|---|
| **[Les Models](/docs/guides/models)** | Tout sur la creation et la configuration des modeles |
| **[CRUD](/docs/guides/crud)** | Creer, lire, modifier, supprimer en detail |
| **[Query Builder](/docs/guides/query-builder)** | Requetes avancees : filtres, tri, pagination, jointures |
| **[Relations](/docs/guides/relations)** | Lier des tables entre elles (vehicules d'un joueur, etc.) |
| **[Migrations](/docs/guides/migrations)** | Creer tes tables automatiquement ou gerer l'evolution de ta BDD |
| **[Transactions](/docs/guides/transactions)** | Executer plusieurs requetes de maniere atomique (avec auto-commit) |
| **[Cache](/docs/guides/cache)** | Reduire les requetes SQL avec un cache TTL |
| **[JSON](/docs/guides/json-columns)** | Stocker des tables Lua en JSON automatiquement |
| **[Studio](/docs/guides/studio)** | Interface web pour visualiser et gerer ta base de donnees |
| **[Conventions de l'API](/docs/api/model#conventions)** | Valeurs de retour, erreurs, ordre des arguments |
