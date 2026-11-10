---
sidebar_position: 1
---

# ORM

Le module principal. C'est le point d'entree de la librairie.

```lua
-- OrvexORM est une table globale, dans orvexorm et dans chaque ressource
-- qui inclut server_script '@orvexorm/lib/import.lua'
print(OrvexORM.version)  -- version lue dans le fxmanifest.lua d'orvexorm
```

:::info Async
Toutes les fonctions qui touchent la base (`transaction`, `migrate`, `rollback`, `raw`, `rawExec`, `seed` selon son contenu, `introspect`, `fromTable`) attendent la reponse de MySQL : appelle-les depuis un thread, un event ou une commande. Voir [Async et threads](/docs/getting-started#async-et-threads). `model`, `enableCache`, `debug`, `setAdapter`, `migrations` et `schema` ne font aucune requete.
:::

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
| `timestamps` | `boolean` | `false` | Remplit `created_at` / `updated_at` ; ces colonnes sont acceptees meme si elles ne sont pas dans `fields` |
| `softDelete` | `boolean` | `false` | `delete()` remplit `deleted_at` au lieu de supprimer ; les lectures excluent ces lignes |
| `hooks` | `table` | `nil` | Un hook par evenement : `{ beforeCreate = fn, afterBulkUpdate = fn, ... }` (voir [Hooks](/docs/api/model#hooks-lifecycle)) |
| `scopes` | `table` | `nil` | Filtres reutilisables : `{ rich = function(b) b:where(...) end }`, appelables comme `User.rich()` |
| `relations` | `function` | `nil` | `function(M) M.hasMany(...) end`, executee par `Model.applyRelations()` |
| `adapter` | `OrvexAdapter` | adaptateur par defaut | Adaptateur de ce modele (autre base, driver de test...) |
| `cache` | `OrvexCache` | cache global | Cache propre a ce modele (voir [Cache](/docs/guides/cache#un-cache-par-modele)) |

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

## `ORM.transaction(fn, adapter?)` / `ORM.transaction(adapter?)`

Cree un nouveau builder de transaction, ou execute une callback transactionnelle avec auto-commit. Seules les methodes `tx:*` font partie de la transaction ; lis le [guide Transactions](/docs/guides/transactions) avant d'ecrire une operation conditionnelle (transfert, achat).

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
| `fn` | `function` | Non | Callback recevant le transaction builder. Si fourni, auto-commit a la fin. Si elle leve une erreur, rien n'est envoye et l'erreur remonte. |
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise (utilise le defaut sinon). En mode callback, c'est le **2e** argument : `ORM.transaction(fn, adapter)`. |

### Retour

- Mode callback : `boolean` — `true` si la transaction a reussi. Selon le driver, un echec peut aussi lever une erreur (voir [commit](/docs/guides/transactions#txcommit--boolean)).
- Mode builder : `OrvexTransaction` — Un objet transaction avec les methodes `insert`, `update`, `delete`, `upsert`, `addRaw`, `getQueries`, `commit`

Apres un commit reussi, le cache global est invalide pour chaque table ecrite.

---

## `ORM.enableCache(opts?)`

Active le cache global avec un TTL optionnel. Le cache global garde au plus **1000 entrees** ; au-dela, les moins recemment lues sont evincees (LRU). Pour une autre limite, donne a un modele son propre cache (`opts.cache`).

### Parametres

| Option | Type | Defaut | Description |
|---|---|---|---|
| `ttl` | `number` | `60` | Duree de vie en secondes |

Le cache vit dans la ressource qui l'active : avec `lib/import.lua`, chaque ressource a le sien.

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
| `maxEntries` | `number` | Taille maximale du cache (1000 pour le cache global) |

### Exemple

```lua
local stats = OrvexORM.cacheStats()
print(("Cache : %d hits, %d misses (%.0f%%), %d entrees")
    :format(stats.hits, stats.misses, stats.hitRate * 100, stats.entries))
```

---

## `ORM.setAdapter(adapter)`

Remplace l'adaptateur de base de donnees par defaut (utilise par les modeles crees **apres** l'appel, les transactions, `raw`, `rawExec` et les migrations). Un adaptateur se construit avec la classe globale `OrvexAdapter`, disponible dans orvexorm et dans chaque ressource qui utilise `lib/import.lua` :

```lua
local MyDriver = {}
MyDriver.__index = MyDriver

function MyDriver:execute(sql, params)   -- SELECT : retourne une liste de lignes
    return exports.oxmysql:executeSync(sql, params) or {}
end

function MyDriver:scalar(sql, params)    -- INSERT : id insere ; UPDATE / DELETE : lignes touchees
    if sql:match("^%s*[Ii][Nn][Ss][Ee][Rr][Tt]") then
        return exports.oxmysql:insertSync(sql, params)
    end
    return exports.oxmysql:updateSync(sql, params)
end

function MyDriver:transaction(queries)   -- optionnel : { { query = "...", values = {...} }, ... }
    return exports.oxmysql:transactionSync(queries) == true
end

OrvexORM.setAdapter(OrvexAdapter.new(setmetatable({}, MyDriver)))
```

### Contrat d'un driver

| Methode | Obligatoire | Recoit | Retourne |
|---|---|---|---|
| `driver:execute(sql, params)` | Oui | requete et tableau de parametres | `table[]` : les lignes (`{}` si aucune) |
| `driver:scalar(sql, params)` | Oui | requete d'ecriture | `INSERT` : l'id insere ; `UPDATE`/`DELETE` : le nombre de lignes touchees (`number` ou `{ affectedRows = n }`) |
| `driver:transaction(queries)` | Non | `{ { query, values }, ... }` | `boolean` : `true` si tout a ete applique |

Sans `transaction`, l'adaptateur execute les requetes une par une et **n'est pas atomique** : une requete en echec n'annule pas les precedentes. Les methodes du driver peuvent *yield* (`Citizen.Await`).

Le driver livre est `OrvexMySQLDriver` (`OrvexAdapter.new(OrvexMySQLDriver.new())`), voir [Driver MySQL](/docs/installation#driver-mysql).

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

Execute toutes les migrations en attente, dans l'ordre. **A la premiere migration en echec**, elle n'est pas enregistree, les suivantes ne sont pas lancees, et une erreur est levee : `[OrvexORM] Migration of migration '<nom>' failed (N migration(s) applied before it): <erreur du driver>`. Une requete pour laquelle le driver retourne `nil` compte comme un echec.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise (utilise le defaut sinon) |

### Retour

`number` — Le nombre de migrations appliquees.

### Exemple

```lua
CreateThread(function()
    local ok, result = pcall(OrvexORM.migrate)
    if ok then
        print(result .. " migration(s) appliquee(s)")
    else
        print("^1Migration en echec : " .. tostring(result) .. "^0")
    end
end)
```

:::caution DDL non transactionnel
MySQL valide chaque `CREATE` / `ALTER` immediatement : si une migration contient plusieurs requetes et que la 3e echoue, les 2 premieres restent appliquees. Corrige la base a la main ou ecris des migrations d'une seule requete.
:::

---

## `ORM.rollback(adapter?)`

Annule le dernier lot de migrations (la plus recente d'abord). Si un `down` echoue, sa migration reste enregistree et une erreur est levee, comme pour `migrate()`.

### Parametres

| Parametre | Type | Requis | Description |
|---|---|---|---|
| `adapter` | `OrvexAdapter` | Non | Adaptateur personnalise (utilise le defaut sinon) |

### Retour

`number` — Le nombre de migrations annulees.

### Exemple

```lua
CreateThread(function()
    local count = OrvexORM.rollback()
    print(count .. " migration(s) annulee(s)")
end)
```

---

## `ORM.raw(sql, params?)`

Execute une requete SQL brute (SELECT) et retourne les lignes (`{}` si aucune). Les lignes sont des tables simples, pas des instances.

```lua
local rows = OrvexORM.raw("SELECT * FROM users WHERE money > ?", { 1000 })
```

Si la requete ecrit (`INSERT`, `UPDATE`, `DELETE`...), le cache global est invalide pour la table ecrite, ou vide entierement quand la table ne peut pas etre determinee (jointures, sous-requetes complexes).

---

## `ORM.rawExec(sql, params?)`

Execute une requete SQL brute (INSERT/UPDATE/DELETE) et retourne ce que le driver renvoie : l'id insere pour un `INSERT`, le nombre de lignes touchees pour un `UPDATE` / `DELETE`. Invalide le cache global comme `ORM.raw`.

```lua
local affected = OrvexORM.rawExec("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
print(affected .. " policier(s) paye(s)")
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
CreateThread(function()
    OrvexORM.seed(function(orm)
        local User = orm.model("users", { identifier = "string", money = "number" })
        User.create({ identifier = "license:admin", money = 99999 })
        User.create({ identifier = "license:test", money = 500 })
    end)
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

`function, function, function, function` — `model`, `raw`, `migrate`, `transaction` (types pour LuaLS : chaque fonction garde la signature de `OrvexORM.*`)

### Exemple

```lua
local model, raw, migrate, transaction = OrvexORM.unpack()

local User = model("users", { identifier = "string", money = "number" })

CreateThread(function()
    migrate()
    local rows = raw("SELECT * FROM logs")
end)
```
