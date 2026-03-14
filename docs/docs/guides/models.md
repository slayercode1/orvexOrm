---
sidebar_position: 1
---

# Les Models

Un **modele** est le lien entre ton code Lua et une table dans ta base de donnees. C'est grace au modele que tu peux creer, lire, modifier et supprimer des donnees sans ecrire de SQL.

## Creer un modele

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

### Les 3 arguments de `OrvexORM.model()`

| Argument | Description | Exemple |
|---|---|---|
| `tableName` | Le nom exact de ta table MySQL | `"users"` |
| `fields` | Les colonnes et leurs types | `{ money = "number" }` |
| `opts` | Options (optionnel) | `{ primaryKey = "identifier" }` |

## Les types disponibles

Quand tu definis ton schema, tu dois dire quel **type** de donnee chaque colonne contient :

| Type | Description | Exemple de valeur |
|---|---|---|
| `"string"` | Du texte | `"license:abc"`, `"police"` |
| `"number"` | Un nombre | `500`, `3.14` |
| `"boolean"` | Vrai ou faux | `true`, `false` |
| `"json"` | Une table Lua (sauvegardee en JSON) | `{ x = 1, y = 2 }` |
| `"date"` | Une date | `"2024-03-15"` |
| `"datetime"` | Date et heure | `"2024-03-15 14:30:00"` |
| `"timestamp"` | Horodatage | `"2024-03-15 14:30:00"` |

### Le type `json` en detail

Le type `json` est special : il te permet de sauvegarder des **tables Lua** directement dans la base de donnees. OrvexORM les convertit automatiquement en JSON pour le stockage, et les reconvertit en table quand tu les lis.

```lua
local Player = OrvexORM.model("players", {
    identifier = "string",
    position   = "json",    -- sera stocke comme '{"x":100,"y":200,"z":50}'
    inventory  = "json",    -- sera stocke comme '[{"item":"bread","count":5}]'
})

-- Sauvegarder une position
Player.create({
    identifier = "license:abc",
    position   = { x = 100.0, y = 200.0, z = 50.0 },   -- table Lua
    inventory  = { { item = "bread", count = 5 } },
})

-- Quand tu lis, c'est automatiquement reconverti en table Lua
local p = Player.find({ identifier = "license:abc" })
print(p.position.x)  -- 100.0 (c'est une table, pas du texte)
```

## La cle primaire

La **cle primaire** (`primaryKey`) indique a OrvexORM quelle colonne identifie chaque ligne de facon unique.

```lua
-- Cle primaire personnalisee
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

-- Cle primaire par defaut (= "id")
local Vehicle = OrvexORM.model("vehicles", {
    id    = "number",
    plate = "string",
    model = "string",
})
-- Pas besoin de preciser primaryKey, c'est "id" par defaut
```

:::info Pourquoi c'est important ?
La cle primaire est utilisee automatiquement par `:update()` et `:delete()` pour savoir **quelle ligne** modifier ou supprimer. Si tu definis mal la cle primaire, OrvexORM pourrait modifier la mauvaise ligne !
:::

## Exemples de modeles courants

### Joueurs

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    bank       = "number",
    job        = "string",
    group      = "string",
}, { primaryKey = "identifier" })
```

### Vehicules

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

### Maisons

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

### Inventaire

```lua
local Inventory = OrvexORM.model("inventories", {
    id         = "number",
    owner      = "string",
    item_name  = "string",
    quantity   = "number",
    metadata   = "json",
}, { primaryKey = "id" })
```

## Hooks et Scopes inline

Tu peux declarer les hooks et scopes directement dans la definition du modele :

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, {
    primaryKey = "identifier",
    hooks = {
        beforeCreate = function(data)
            data.money = data.money or 500  -- valeur par defaut
        end,
        afterDelete = function(instance)
            print("Joueur supprime : " .. instance.identifier)
        end,
    },
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where({ job = "police" }) end,
    },
})

-- Les scopes sont accessibles comme methodes directes !
local riches = User.rich():get()
local richCops = User.rich():where({ job = "police" }):get()
```

## Relations inline

Tu peux aussi declarer les relations dans la definition du modele via une callback :

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
}, {
    primaryKey = "identifier",
    relations = function(M)
        M.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
        M.hasOne("profile", Profile, { foreignKey = "user_id" })
    end,
})

-- Appeler apres que tous les modeles sont crees
User.applyRelations()
```

:::tip Pourquoi `applyRelations()` ?
Les relations referencent d'autres modeles. Si tu les declares inline, il faut que ces modeles existent deja. Appelle `applyRelations()` une fois que tous tes modeles sont crees.
:::
