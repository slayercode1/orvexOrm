---
sidebar_position: 2
---

# Model

Toutes les methodes disponibles sur un modele cree avec `ORM.model()`.

```lua
local User = ORM.model("users", { ... })
-- User est un OrvexModel
```

---

## CRUD

### `Model.create(data)` → `OrvexInstance`

Insere une nouvelle ligne.

```lua
local player = User.create({ identifier = "license:abc", money = 500 })
```

---

### `Model.find(where)` → `OrvexInstance | nil`

Retourne la premiere ligne correspondante, ou `nil`.

```lua
local player = User.find({ identifier = "license:abc" })
```

---

### `Model.findAll(where)` → `OrvexInstance[]`

Retourne toutes les lignes correspondantes.

```lua
local cops = User.findAll({ job = "police" })
```

---

### `Model.upsert(data)` → `boolean`

Insere ou met a jour si la cle primaire existe deja.

```lua
User.upsert({ identifier = "license:abc", money = 2000 })
```

---

### `Model.update(data, where)` → `boolean`

Met a jour les lignes correspondant a `where`.

```lua
User.update({ money = 0 }, { job = "unemployed" })
```

:::caution
Le parametre `where` est **obligatoire** et doit etre non-vide pour eviter de modifier toute la table.
:::

---

### `Model.delete(where)` → `boolean`

Supprime les lignes correspondant a `where`. Si le soft delete est active, marque les lignes comme supprimees (met `deleted_at`).

```lua
User.delete({ job = "unemployed" })
```

---

### `Model.createMany(rows)` → `boolean`

Insere plusieurs lignes en une seule requete.

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
```

---

### `Model.findOrCreate(where, defaults?)` → `OrvexInstance, boolean`

Cherche un enregistrement, ou le cree s'il n'existe pas. Retourne l'instance et un boolean `created`.

```lua
local player, created = User.findOrCreate(
    { identifier = "license:abc" },        -- condition de recherche
    { money = 500, job = "unemployed" }     -- valeurs par defaut si creation
)

if created then
    print("Nouveau joueur cree !")
end
```

---

### `Model.updateOrCreate(where, data)` → `OrvexInstance, boolean`

Met a jour un enregistrement existant, ou en cree un nouveau.

```lua
local player, created = User.updateOrCreate(
    { identifier = "license:abc" },   -- condition de recherche
    { money = 1000, job = "police" }  -- donnees a mettre a jour ou creer
)
```

---

### `Model.increment(column, amount, where)` → `boolean`

Incremente une colonne numerique.

```lua
User.increment("money", 100, { identifier = "license:abc" })
-- SQL: UPDATE users SET money = money + 100 WHERE identifier = ?
```

---

### `Model.decrement(column, amount, where)` → `boolean`

Decremente une colonne numerique.

```lua
User.decrement("money", 50, { identifier = "license:abc" })
```

---

### `Model.findOrFail(where, opts?)` → `OrvexInstance`

Comme `find()`, mais lance une erreur si aucun enregistrement n'est trouve.

```lua
local player = User.findOrFail({ identifier = "license:abc" })
-- Erreur si non trouve : "Record not found in 'users' where identifier=license:abc"
```

---

### `Model.first(where?)` → `OrvexInstance | nil`

Retourne le premier enregistrement correspondant. Raccourci pour `query():where(...):first()`.

```lua
local cop = User.first({ job = "police" })
local anyone = User.first()  -- premier de la table
```

---

### `Model.exists(where)` → `boolean`

Verifie si un enregistrement existe sans charger les donnees.

```lua
if User.exists({ identifier = "license:abc" }) then
    print("Le joueur existe")
end
```

---

### `Model.pluck(column, where?)` → `any[]`

Retourne un tableau avec uniquement les valeurs d'une colonne.

```lua
local jobs = User.pluck("job")                        -- tous les jobs
local moneys = User.pluck("money", { job = "police" }) -- argent des policiers
```

---

### `Model.updateWhere(where, data)` → `boolean`

Alias de `update(data, where)` avec les arguments dans un ordre plus lisible.

```lua
User.updateWhere({ identifier = "license:abc" }, { money = 9999 })
```

---

### `Model.deleteWhere(where)` → `boolean`

Alias de `delete(where)`.

```lua
User.deleteWhere({ job = "unemployed" })
```

---

### `Model.forceDelete(where)` → `boolean`

Supprime definitivement (ignore le soft delete).

```lua
User.forceDelete({ identifier = "license:old" })
```

---

### `Model.restore(where)` → `boolean`

Restaure des lignes supprimees en douceur (soft delete).

```lua
User.restore({ identifier = "license:abc" })
```

---

### `Model.createWith(data)` → `OrvexInstance`

Cree un enregistrement avec des relations imbriquees (nested writes). Les cles de relation sont automatiquement detectees.

```lua
-- Definir les relations
User.hasOne("profile", Profile, { foreignKey = "user_id" })
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })

-- Creer avec des relations imbriquees
local player = User.createWith({
    identifier = "license:abc",
    money      = 500,
    -- Nested hasOne
    profile = { bio = "Salut !", avatar = "avatar.png" },
    -- Nested hasMany
    vehicles = {
        { plate = "ABC123", model = "sultan" },
        { plate = "XYZ789", model = "adder" },
    },
})
```

Cela execute 4 requetes :
1. `INSERT INTO users ...`
2. `INSERT INTO profiles (user_id, bio, avatar) ...`
3. `INSERT INTO vehicles (owner_id, plate, model) ...`
4. `INSERT INTO vehicles (owner_id, plate, model) ...`

---

### `Model.whereHas(relationName, callback?)` → `OrvexBuilder`

Filtre les enregistrements qui ont au moins un enregistrement lie. Utilise `WHERE EXISTS` en SQL.

```lua
-- Joueurs qui ont au moins un vehicule
local players = User.whereHas("vehicles"):get()

-- Joueurs qui ont un vehicule avec la plaque "ABC123"
local players = User.whereHas("vehicles", function(b)
    b:where({ plate = "ABC123" })
end):get()
```

**SQL genere :**
```sql
SELECT * FROM users WHERE EXISTS (
    SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.identifier
)
```

---

### `Model.countByRelation(relationName, where?)` → `table`

Compte les enregistrements lies pour chaque enregistrement parent.

```lua
local results = User.countByRelation("vehicles", { job = "police" })

for _, entry in ipairs(results) do
    print(entry.instance.identifier .. " a " .. entry.count .. " vehicule(s)")
end
-- Chaque instance a aussi un champ _count_vehicles
```

---

## Query Builder

### `Model.query()` → `OrvexBuilder`

Retourne un query builder chainable.

```lua
local results = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :limit(10)
    :get()
```

Voir la [reference complete du Builder](/docs/api/builder).

---

## Agregations

### `Model.count(where?)` → `integer`

```lua
User.count()                    -- tous
User.count({ job = "police" }) -- avec filtre
```

### `Model.sum(column, where?)` → `number`

```lua
User.sum("money")
User.sum("money", { job = "police" })
```

### `Model.avg(column, where?)` → `number`

```lua
User.avg("money", { job = "police" })
```

### `Model.min(column, where?)` → `any`

```lua
User.min("money")
```

### `Model.max(column, where?)` → `any`

```lua
User.max("money")
```

---

## Table

### `Model.sync()`

Cree la table du modele si elle n'existe pas. Genere automatiquement le SQL `CREATE TABLE IF NOT EXISTS` a partir du schema.

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

User.sync() -- Cree la table "users" si elle n'existe pas
```

---

### `Model.flushCache()`

Vide le cache de ce modele.

```lua
User.flushCache()
```

---

## Relations

### `Model.hasOne(name, relatedModel, opts)`

Definit une relation 1 → 1.

| Option | Type | Description |
|---|---|---|
| `foreignKey` | `string` | Colonne sur la table **liee** |
| `localKey` | `string?` | Colonne sur cette table (defaut: primaryKey) |

```lua
User.hasOne("profile", Profile, { foreignKey = "user_id" })
```

---

### `Model.hasMany(name, relatedModel, opts)`

Definit une relation 1 → N.

| Option | Type | Description |
|---|---|---|
| `foreignKey` | `string` | Colonne sur la table **liee** |
| `localKey` | `string?` | Colonne sur cette table (defaut: primaryKey) |

```lua
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
```

---

### `Model.belongsTo(name, relatedModel, opts)`

Definit une relation N → 1.

| Option | Type | Description |
|---|---|---|
| `foreignKey` | `string` | Colonne sur **cette** table |
| `ownerKey` | `string?` | Colonne sur la table liee (defaut: sa primaryKey) |

```lua
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
```

---

### `Model.belongsToMany(name, relatedModel, opts)`

Definit une relation N → N via une table pivot.

| Option | Type | Description |
|---|---|---|
| `pivot` | `string` | Nom de la table pivot **(obligatoire)** |
| `foreignKey` | `string` | Colonne pivot → cette table |
| `otherKey` | `string` | Colonne pivot → table liee |
| `localKey` | `string?` | Colonne sur cette table (defaut: primaryKey) |

```lua
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",
    foreignKey = "user_id",
    otherKey   = "role_id",
})
```

---

## Options du modele

| Option | Type | Defaut | Description |
|---|---|---|---|
| `primaryKey` | `string` | `"id"` | Nom de la cle primaire |
| `softDelete` | `boolean` | `false` | Active le soft delete (colonne `deleted_at`) |
| `timestamps` | `boolean` | `false` | Auto-gestion de `created_at` et `updated_at` |
| `hooks` | `table` | `nil` | Hooks inline `{ beforeCreate = fn, ... }` |
| `scopes` | `table` | `nil` | Scopes inline `{ rich = fn, ... }` |
| `relations` | `function` | `nil` | Callback pour declarer les relations `function(M) ... end` |

```lua
local User = ORM.model("users", { ... }, {
    primaryKey = "identifier",
    softDelete = true,
    timestamps = true,
    hooks = {
        beforeCreate = function(data)
            data.money = data.money or 500
        end,
    },
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where({ job = "police" }) end,
    },
    relations = function(M)
        M.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
    end,
})

-- Appeler apres creation de tous les modeles
User.applyRelations()
```

---

## Soft Delete

Quand `softDelete = true`, les suppressions marquent la ligne avec `deleted_at` au lieu de la supprimer.

```lua
local User = ORM.model("users", { ... }, { softDelete = true })

-- Supprime en douceur (met deleted_at)
User.delete({ identifier = "license:abc" })

-- Supprime definitivement
User.forceDelete({ identifier = "license:abc" })

-- Restaure un enregistrement supprime
User.restore({ identifier = "license:abc" })

-- Query builder : inclure les supprimes
User.withTrashed():get()

-- Query builder : seulement les supprimes
User.onlyTrashed():get()
```

---

## Hooks (Lifecycle)

Les hooks permettent d'executer du code avant/apres les operations CRUD.

```lua
User.beforeCreate(function(data)
    data.money = data.money or 500  -- valeur par defaut
end)

User.afterCreate(function(instance)
    print("Joueur cree : " .. instance.identifier)
end)

User.beforeUpdate(function(instance, data)
    print("Mise a jour de " .. instance.identifier)
end)

User.afterUpdate(function(instance)
    print("Apres mise a jour")
end)

User.beforeDelete(function(instance)
    print("Suppression de " .. instance.identifier)
end)

User.afterDelete(function(instance)
    print("Supprime !")
end)
```

---

## Scopes

Les scopes sont des filtres reutilisables pour le query builder. Quand tu definis un scope, il devient **directement accessible comme methode** du modele.

```lua
-- Definir un scope
User.scope("rich", function(b)
    b:where("money", ">", 10000)
end)

User.scope("cops", function(b)
    b:where({ job = "police" })
end)

-- Utiliser un scope comme methode directe
local richPlayers = User.rich():get()
local copPlayers  = User.cops():get()

-- Chainable avec d'autres conditions
local richCops = User.rich():where({ job = "police" }):get()

-- Ou via scoped() (ancienne syntaxe, toujours supportee)
local richPlayers = User.scoped("rich"):get()
```

Tu peux aussi declarer les scopes inline dans la definition du modele :

```lua
local User = ORM.model("users", { ... }, {
    scopes = {
        rich = function(b) b:where("money", ">", 10000) end,
        cops = function(b) b:where({ job = "police" }) end,
    },
})

-- Directement utilisable !
User.rich():limit(10):get()
```
