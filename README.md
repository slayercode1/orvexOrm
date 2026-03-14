<div align="center">

# OrvexORM

**L'ORM le plus simple et performant pour FiveM.**

Zero SQL. Zero galere. Juste du Lua propre.

[![Lua](https://img.shields.io/badge/Lua-5.4-blue?logo=lua&logoColor=white)](https://www.lua.org/)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-orange)](https://fivem.net/)
[![License](https://img.shields.io/badge/License-Proprietary-red)](LICENSE)
[![oxmysql](https://img.shields.io/badge/oxmysql-Compatible-purple)](https://github.com/overextended/oxmysql)
[![mysql-async](https://img.shields.io/badge/mysql--async-Compatible-purple)](https://github.com/brouznouf/fivem-mysql-async)

[Documentation](https://orvexorm.dev) | [Installation](#installation) | [Exemples](#exemples-rapides)

---

</div>

## Pourquoi OrvexORM ?

```lua
-- Sans ORM
MySQL.prepare("SELECT * FROM users WHERE identifier = ?", { id }, function(result)
    if result[1] then
        MySQL.prepare("UPDATE users SET money = ? WHERE identifier = ?", { 1000, id }, function() end)
    end
end)

-- Avec OrvexORM
local player = User.find({ identifier = id })
player:update({ money = 1000 })
```

| | Sans ORM | Avec OrvexORM |
|---|---|---|
| SQL a la main | Oui | Non |
| Risque d'erreurs SQL | Eleve | Zero |
| Validation des types | Non | Automatique |
| Relations entre tables | Complexe | 1 ligne |
| Performance | Depend de toi | < 0.01ms/op |

---

## Installation

```bash
npx orvexorm install
```

```cfg
# server.cfg
ensure oxmysql    # ou mysql-async
ensure orvexorm
```

> OrvexORM detecte automatiquement **oxmysql** ou **mysql-async**. Aucune configuration necessaire.

---

## Exemples rapides

### Definir un modele

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
    position   = "json",
    created_at = "datetime",
}, {
    primaryKey = "identifier",
    timestamps = true,
    softDelete = true,
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where("job", "police") end,
    },
})
```

### CRUD

```lua
-- Creer
local player = User.create({ identifier = "license:abc", money = 500, job = "police" })

-- Lire
local player = User.find({ identifier = "license:abc" })
local player = User.findOrFail({ identifier = "license:abc" })  -- erreur si non trouve
local cops   = User.findAll({ job = "police" })
local first  = User.first({ job = "police" })

-- Verifier
if User.exists({ identifier = "license:abc" }) then ... end

-- Modifier
player:update({ money = 1000 })
player:increment("money", 500)
User.updateWhere({ identifier = "license:abc" }, { job = "medic" })

-- Supprimer
player:delete()
User.deleteWhere({ job = "unemployed" })
```

### Query Builder

```lua
-- Chainable, lisible, puissant
local top10 = User.query()
    :where("job", "police")
    :where("money", ">", 1000)
    :whereNotIn("identifier", { "license:banned1", "license:banned2" })
    :orderByDesc("money")
    :limit(10)
    :get()

-- Pagination automatique
local page = User.query():where("job", "police"):paginate(2, 10)
-- page.data, page.total, page.page, page.lastPage

-- Scopes comme methodes
local riches = User.rich():orderByDesc("money"):get()

-- Agregations
User.count({ job = "police" })
User.sum("money")
User.avg("money", { job = "medic" })

-- Extraire une colonne
local jobs = User.pluck("job")

-- Traiter par lots
User.query():chunk(100, function(players)
    for _, p in ipairs(players) do p:update({ money = 0 }) end
end)
```

### Relations

```lua
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
User.hasOne("profile", Profile, { foreignKey = "user_id" })
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })

local player   = User.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")
local profile  = player:get("profile")

-- Creer avec les relations
User.createWith({
    identifier = "license:new",
    money = 500,
    profile  = { bio = "Hello" },
    vehicles = {
        { plate = "ABC123", model = "sultan" },
        { plate = "XYZ789", model = "adder" },
    },
})
```

### Transactions

```lua
OrvexORM.transaction(function(tx)
    tx:update("users", { money = 900 }, { identifier = fromId })
    tx:update("users", { money = 1100 }, { identifier = toId })
end)
```

### Migrations

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
                t:json("position")
                t:date("birth_date")
                t:timestamps()
                t:softDeletes()
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
})

OrvexORM.migrate()
```

---

## Types disponibles

| Type | MySQL | Lua |
|---|---|---|
| `"string"` | `VARCHAR(255)` | `"texte"` |
| `"number"` | `INT` | `42` |
| `"boolean"` | `TINYINT(1)` | `true/false` |
| `"json"` | `JSON` | `{ x = 1 }` (auto encode/decode) |
| `"date"` | `DATE` | `"2024-03-15"` |
| `"datetime"` | `DATETIME` | `"2024-03-15 14:30:00"` |
| `"timestamp"` | `TIMESTAMP` | `"2024-03-15 14:30:00"` |

---

## Performance

Benchmarks sur Lua 5.3 (FiveM utilise Lua 5.4 = encore plus rapide) :

| Operation | Temps |
|---|---|
| `Model.find()` | **0.005 ms** |
| `Model.create()` | **0.009 ms** |
| `Model.update()` | **0.007 ms** |
| `Model.delete()` | **0.005 ms** |
| `instance:increment()` | **0.004 ms** |
| Query builder (simple) | **0.008 ms** |
| Cache hit | **0.0002 ms** |

> Toutes les operations courantes sont sous **0.01ms**. Ton serveur ne lag pas.

---

## API complete

<details>
<summary><strong>Model (classe)</strong></summary>

| Methode | Description |
|---|---|
| `Model.create(data)` | Inserer une ligne |
| `Model.createMany(rows)` | Inserer en masse |
| `Model.createWith(data)` | Inserer avec relations |
| `Model.find(where)` | Trouver un enregistrement |
| `Model.findOrFail(where)` | Trouver ou erreur |
| `Model.findAll(where)` | Trouver tous |
| `Model.first(where?)` | Premier resultat |
| `Model.exists(where)` | Existe ? |
| `Model.pluck(col, where?)` | Extraire une colonne |
| `Model.update(data, where)` | Modifier |
| `Model.updateWhere(where, data)` | Modifier (alias lisible) |
| `Model.upsert(data)` | Insert ou update |
| `Model.delete(where)` | Supprimer |
| `Model.deleteWhere(where)` | Supprimer (alias) |
| `Model.forceDelete(where)` | Supprimer definitivement |
| `Model.restore(where)` | Restaurer (soft delete) |
| `Model.increment(col, n, where)` | Incrementer |
| `Model.decrement(col, n, where)` | Decrementer |
| `Model.findOrCreate(where, defaults)` | Trouver ou creer |
| `Model.updateOrCreate(where, data)` | MAJ ou creer |
| `Model.count/sum/avg/min/max` | Agregations |
| `Model.query()` | Query builder |
| `Model.scope(name, fn)` | Definir un scope |
| `Model.sync()` | Creer la table |

</details>

<details>
<summary><strong>Instance</strong></summary>

| Methode | Description |
|---|---|
| `instance:update(data)` | Modifier cette ligne |
| `instance:delete()` | Supprimer cette ligne |
| `instance:forceDelete()` | Supprimer definitivement |
| `instance:restore()` | Restaurer |
| `instance:increment(col, n?)` | Incrementer |
| `instance:decrement(col, n?)` | Decrementer |
| `instance:get(relation)` | Charger une relation |
| `instance:attach(relation, inst)` | Lier (pivot) |
| `instance:detach(relation, inst)` | Delier (pivot) |

</details>

<details>
<summary><strong>Query Builder</strong></summary>

| Methode | Description |
|---|---|
| `:where(field, value)` | Egalite (raccourci) |
| `:where(field, op, value)` | Avec operateur |
| `:where({ field = value })` | Table |
| `:orWhere(...)` | OR |
| `:whereIn(col, values)` | IN |
| `:whereNotIn(col, values)` | NOT IN |
| `:whereBetween(col, min, max)` | BETWEEN |
| `:whereNotBetween(col, min, max)` | NOT BETWEEN |
| `:whereLike(col, pattern)` | LIKE |
| `:whereNull(col)` | IS NULL |
| `:whereNotNull(col)` | IS NOT NULL |
| `:whereExists(subSQL)` | EXISTS |
| `:orderBy(col, dir?)` | Trier |
| `:orderByDesc(col)` | Trier DESC |
| `:orderByAsc(col)` | Trier ASC |
| `:latest(col?)` | Plus recent |
| `:oldest(col?)` | Plus ancien |
| `:limit(n)` | Limiter |
| `:offset(n)` | Decaler |
| `:select(cols)` | Colonnes |
| `:distinct()` | Distinct |
| `:leftJoin/innerJoin/rightJoin` | Jointures |
| `:groupBy(cols)` | Grouper |
| `:having(clause, ...)` | Filtrer les groupes |
| `:get()` | Executer |
| `:first()` | Premier resultat |
| `:count()` | Compter |
| `:sum/avg/min/max(col)` | Agregations |
| `:pluck(col)` | Extraire colonne |
| `:exists()` | Existe ? |
| `:paginate(page, perPage?)` | Pagination |
| `:chunk(size, fn)` | Traiter par lots |
| `:toSQL()` | Voir le SQL |

</details>

---

## Compatibilite

| | Supporte |
|---|---|
| FiveM | Lua 5.4 |
| oxmysql | Auto-detecte |
| mysql-async | Auto-detecte |
| MySQL | 5.7+ |
| MariaDB | 10.2+ |

---

## Licence

[Proprietary](LICENSE) - OrvexORM est un logiciel proprietaire. L'utilisation est autorisee uniquement via les fichiers compiles (`.luac`) distribues officiellement. Le code source n'est pas open source.
