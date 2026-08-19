---
sidebar_position: 1
---

# ORM

Le module principal. C'est le point d'entree de la librairie.

```lua
-- OrvexORM est disponible globalement
```

---

## `ORM.model(tableName, fields, opts?)`

Cree un nouveau modele lie a une table MySQL.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `tableName` | `string` | Oui | Nom de la table MySQL |
| `fields` | `table` | Oui | Schema : `{ colonne = "type", ... }` |
| `opts` | `table` | Non | Options (voir ci-dessous) |

### Options (`opts`)

| Option | Type | Defaut | Description |
|---|---|---|---|
| `primaryKey` | `string` | `"id"` | Nom de la colonne cle primaire |

### Types de champs disponibles

| Type | Description |
|---|---|
| `"string"` | Texte |
| `"number"` | Nombre |
| `"boolean"` | Vrai/faux |
| `"json"` | Table Lua convertie en JSON automatiquement |
| `"date"` | Date (`"2024-03-15"`) |
| `"datetime"` | Date et heure (`"2024-03-15 14:30:00"`) |
| `"timestamp"` | Horodatage (`"2024-03-15 14:30:00"`) |
| `"auto"` | Detection automatique (table → JSON, JSON string → table) |

### Retour

`OrvexModel` — Un objet modele avec toutes les methodes CRUD, le query builder, et les relations.

### Exemple

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
    position   = "json",
    metadata   = "auto",
}, { primaryKey = "identifier" })
```

---

## `ORM.transaction(fn?)` / `ORM.transaction(adapter?)`

Cree un nouveau builder de transaction, ou execute une callback transactionnelle avec auto-commit.

### Mode callback (recommande)

```lua
local success = OrvexORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:abc", money = 500 })
    tx:update("vehicles", { owner = "license:abc" }, { plate = "ABC123" })
end) -- auto-commit !
```

### Mode builder

```lua
local tx = OrvexORM.transaction()
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("vehicles", { owner = "license:abc" }, { plate = "ABC123" })
local success = tx:commit()
```

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `fn` | `function` | Non | Callback recevant le transaction builder. Si fourni, auto-commit a la fin. |
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise (utilise le defaut sinon) |

### Retour

- Mode callback : `boolean` — `true` si la transaction a reussi
- Mode builder : `OrvexTransaction` — Un objet transaction avec les methodes `insert`, `update`, `delete`, `upsert`, `addRaw`, `commit`

---

## `ORM.enableCache(opts?)`

Active le cache global avec un TTL optionnel.

### Parametres

| Option | Type | Defaut | Description |
|---|---|---|---|
| `ttl` | `number` | `60` | Duree de vie en secondes |

### Exemple

```lua
OrvexORM.enableCache({ ttl = 30 })
```

---

## `ORM.disableCache()`

Desactive et vide le cache global.

```lua
OrvexORM.disableCache()
```

---

## `ORM.flushCache()`

Vide toutes les entrees du cache sans le desactiver.

```lua
OrvexORM.flushCache()
```

---

## `ORM.cacheStats()`

Retourne les statistiques du cache global.

### Retour

| Champ | Type | Description |
|---|---|---|
| `hits` | `number` | Nombre de lectures servies depuis le cache |
| `misses` | `number` | Nombre de lectures qui ont interroge la base |
| `hitRate` | `number` | Ratio hits / (hits + misses) |
| `entries` | `number` | Nombre d'entrees actuellement en cache |

### Exemple

```lua
local stats = OrvexORM.cacheStats()
print(("Cache : %d hits, %d misses (%.0f%%), %d entrees")
    :format(stats.hits, stats.misses, stats.hitRate * 100, stats.entries))
```

---

## `ORM.setAdapter(adapter)`

Remplace l'adaptateur de base de donnees par defaut.

```lua
OrvexORM.setAdapter(Adapter.new(MyDriver.new()))
```

---

## `ORM.migrations(migrations)`

Enregistre une liste de migrations a appliquer.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `migrations` | `table[]` | Oui | Liste de migrations avec `name`, `up`, `down` |

### Exemple

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
})
```

---

## `ORM.migrate(adapter?)`

Execute toutes les migrations en attente.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise (utilise le defaut sinon) |

### Retour

`number` — Le nombre de migrations appliquees.

### Exemple

```lua
local count = OrvexORM.migrate()
print(count .. " migration(s) appliquee(s)")
```

---

## `ORM.rollback(adapter?)`

Annule le dernier lot de migrations.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise (utilise le defaut sinon) |

### Retour

`number` — Le nombre de migrations annulees.

### Exemple

```lua
local count = OrvexORM.rollback()
print(count .. " migration(s) annulee(s)")
```

---

## `ORM.raw(sql, params?)`

Execute une requete SQL brute (SELECT) et retourne les lignes.

```lua
local rows = OrvexORM.raw("SELECT * FROM users WHERE money > ?", { 1000 })
```

---

## `ORM.rawExec(sql, params?)`

Execute une requete SQL brute (INSERT/UPDATE/DELETE).

```lua
OrvexORM.rawExec("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
```

---

## `ORM.debug(enabled)`

Active ou desactive le mode debug. Quand active, toutes les requetes SQL sont affichees dans la console.

```lua
OrvexORM.debug(true)   -- Active les logs SQL
OrvexORM.debug(false)  -- Desactive les logs
```

---

## `ORM.seed(fn)`

Execute une fonction de seed pour remplir la base de donnees avec des donnees initiales.

```lua
OrvexORM.seed(function(orm)
    local User = orm.model("users", { identifier = "string", money = "number" })
    User.create({ identifier = "license:admin", money = 99999 })
    User.create({ identifier = "license:test", money = 500 })
end)
```

---

## `ORM.introspect(tableName, adapter?)`

Analyse une table MySQL existante et retourne sa definition de champs et sa cle primaire. Utilise `DESCRIBE` en interne.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `tableName` | `string` | Oui | Nom de la table MySQL a analyser |
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise |

### Retour

`table<string, OrvexFieldType>, string` — Les champs detectes et le nom de la cle primaire.

### Mapping des types MySQL

| Type MySQL | Type OrvexORM |
|---|---|
| `int`, `bigint`, `float`, `double`, `decimal` | `"number"` |
| `varchar`, `char`, `text`, `enum` | `"string"` |
| `tinyint(1)` | `"boolean"` |
| `json` | `"json"` |
| `date` | `"date"` |
| `datetime` | `"datetime"` |
| `timestamp` | `"timestamp"` |

### Exemple

```lua
local fields, pk = OrvexORM.introspect("users")
-- fields = { id = "number", name = "string", money = "number", ... }
-- pk = "id"

-- Creer un modele automatiquement
local User = OrvexORM.model("users", fields, { primaryKey = pk })
```

---

## `ORM.fromTable(tableName, opts?)`

Raccourci qui combine `introspect()` et `model()` : analyse la table et cree le modele automatiquement.

```lua
local User = OrvexORM.fromTable("users")
-- Equivalent a :
-- local fields, pk = OrvexORM.introspect("users")
-- local User = OrvexORM.model("users", fields, { primaryKey = pk })
```

---

## `ORM.unpack()`

Retourne les fonctions les plus courantes pour eviter de repeter `OrvexORM.` partout.

### Retour

`function, function, function, function` — `model`, `raw`, `migrate`, `transaction`

### Exemple

```lua
local model, raw, migrate, transaction = OrvexORM.unpack()

local User = model("users", { identifier = "string", money = "number" })
local rows = raw("SELECT * FROM logs")
migrate()
```
