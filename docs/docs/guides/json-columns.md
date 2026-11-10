---
sidebar_position: 9
---

# Colonnes JSON automatiques

OrvexORM peut automatiquement convertir des **tables Lua** en **JSON** pour le stockage en base de donnees, et les reconvertir quand tu les lis. C'est parfait pour sauvegarder des positions, inventaires, configurations, etc.

## Le type `"json"` (explicite)

Quand tu declares un champ comme `"json"`, OrvexORM sait qu'il faut convertir les tables en JSON :

```lua
local Player = ORM.model("players", {
    identifier = "string",
    position   = "json",     -- table Lua ↔ JSON automatiquement
    inventory  = "json",
})
```

### Sauvegarde

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

En base de donnees, `position` est stocke comme :
```json
{"x":100.5,"y":200.3,"z":50.0}
```

### Lecture

```lua
local player = Player.find({ identifier = "license:abc" })

-- C'est automatiquement reconverti en table Lua
print(player.position.x)            -- 100.5
print(player.inventory[1].item)     -- "bread"
```

Tu n'as **rien a faire** — la conversion est transparente.

## Le type `"auto"` (detection automatique)

Le type `"auto"` detecte automatiquement si une valeur doit etre convertie :

- **A l'ecriture** : si la valeur est une table → encode en JSON
- **A la lecture** : si la valeur ressemble a du JSON (commence par `{` ou `[`) → decode en table

```lua
local Config = ORM.model("configs", {
    key   = "string",
    value = "auto",     -- detecte automatiquement
})

-- Sauvegarder une table → stocke en JSON
Config.create({ key = "spawn_point", value = { x = 100, y = 200, z = 50 } })

-- Sauvegarder un string → reste un string
Config.create({ key = "server_name", value = "Mon Serveur RP" })

-- Sauvegarder un nombre → reste un nombre
Config.create({ key = "max_players", value = 64 })

-- A la lecture, tout est reconverti correctement
local spawn = Config.find({ key = "spawn_point" })
print(spawn.value.x)  -- 100 (table Lua)

local name = Config.find({ key = "server_name" })
print(name.value)  -- "Mon Serveur RP" (string)
```

## Difference entre `"json"` et `"auto"`

| | `"json"` | `"auto"` |
|---|---|---|
| Ecriture d'une table | Encode en JSON | Encode en JSON |
| Ecriture d'un string | Pas de conversion | Pas de conversion |
| Lecture d'un JSON string | Decode en table | Decode en table |
| Lecture d'un string normal | Decode en table (peut casser) | Reste un string |
| Validation | Verifie que c'est une table | Pas de validation stricte |

:::tip Lequel choisir ?
- **`"json"`** : quand la colonne contient **toujours** du JSON (position, inventaire, mods vehicule)
- **`"auto"`** : quand la colonne peut contenir **differents types** de valeurs (configurations, metadata)
:::

## Exemples de colonnes JSON

### Position d'un joueur

```lua
local Player = ORM.model("players", {
    identifier = "string",
    position   = "json",
})

-- Sauvegarde
Player.upsert({
    identifier = "license:abc",
    position   = { x = 123.4, y = 567.8, z = 90.1, heading = 180.0 },
})
```

### Modifications d'un vehicule

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

### Inventaire

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

:::caution Transactions et SQL brut
L'encodage JSON est fait par le modele. Les methodes `tx:insert` / `tx:update` des [transactions](/docs/guides/transactions) et `OrvexORM.raw` / `rawExec` ne passent pas par le modele : encode toi-meme avec `json.encode(valeur)`, et decode les lignes de `OrvexORM.raw` avec `json.decode`.
:::

### Table SQL recommandee

Pour les colonnes JSON, utilise le type `JSON` ou `LONGTEXT` en MySQL :

```sql
CREATE TABLE `players` (
    `identifier` VARCHAR(60) NOT NULL,
    `position` JSON DEFAULT NULL,
    `inventory` JSON DEFAULT NULL,
    PRIMARY KEY (`identifier`)
);
```
