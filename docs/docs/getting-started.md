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

-- Definir le modele
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- Quand un joueur se connecte
AddEventHandler("playerConnecting", function()
    local src = source
    local identifier = GetPlayerIdentifierByType(src, "license")

    -- Chercher ou creer le joueur
    local player = User.find({ identifier = identifier })

    if not player then
        player = User.create({
            identifier = identifier,
            money      = 500,
            job        = "unemployed",
        })
        print("Nouveau joueur cree : " .. identifier)
    else
        print("Joueur existant : " .. identifier .. " avec " .. player.money .. "$")
    end
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
