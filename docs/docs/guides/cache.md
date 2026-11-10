---
sidebar_position: 8
---

# Cache

Le **cache** stocke les resultats de requetes en memoire pour eviter de faire des appels inutiles a la base de donnees. Si tu cherches le meme joueur 10 fois en 1 seconde, la base de donnees n'est interrogee qu'une seule fois.

## Activer le cache

Par defaut, le cache est **desactive**. Pour l'activer :

```lua
-- Activer avec un TTL de 60 secondes (duree de vie des donnees en cache)
OrvexORM.enableCache({ ttl = 60 })
```

Le **TTL** (Time To Live) est la duree en secondes pendant laquelle une donnee reste en cache avant d'etre consideree comme perimee.

Le cache global garde au plus **1000 entrees**. Quand il est plein, l'entree **la moins recemment lue** est evincee (LRU). Les entrees expirees sont purgees au fil des ecritures, au plus une fois par TTL : la memoire ne grossit pas indefiniment.

:::info Un cache par ressource
Le cache vit dans la memoire de la ressource. Avec `@orvexorm/lib/import.lua`, chaque ressource a **son propre** cache : `enableCache()` dans la ressource A n'active rien dans la ressource B, et une ecriture faite par B n'invalide pas le cache de A. Si plusieurs ressources (ou un autre script, ou un outil comme HeidiSQL) ecrivent dans les memes tables, garde un TTL court ou laisse le cache desactive pour ces modeles.
:::

## Comment ca marche

### Sans cache

```lua
-- Chaque appel interroge la base de donnees
local p1 = User.find({ identifier = "license:abc" })  -- → requete SQL
local p2 = User.find({ identifier = "license:abc" })  -- → requete SQL (encore)
local p3 = User.find({ identifier = "license:abc" })  -- → requete SQL (encore)
-- = 3 requetes SQL
```

### Avec cache

```lua
OrvexORM.enableCache({ ttl = 30 })

local p1 = User.find({ identifier = "license:abc" })  -- → requete SQL (cache miss)
local p2 = User.find({ identifier = "license:abc" })  -- → cache (pas de SQL !)
local p3 = User.find({ identifier = "license:abc" })  -- → cache (pas de SQL !)
-- = 1 seule requete SQL
```

## Invalidation automatique

Le cache est **automatiquement invalide** quand tu modifies des donnees. Tu n'as pas a t'en occuper.

```lua
local player = User.find({ identifier = "license:abc" })  -- cache miss → SQL
local player = User.find({ identifier = "license:abc" })  -- cache hit

-- Modification → le cache de la table "users" est vide
User.update({ money = 1000 }, { identifier = "license:abc" })

local player = User.find({ identifier = "license:abc" })  -- cache miss → SQL (donnees fraiches)
```

Les operations qui invalident le cache :

| Operation | Invalide le cache ? |
|---|---|
| `create()`, `createMany()`, `createWith()` | Oui |
| `upsert()` | Oui |
| `update()` / `updateWhere()` (classe et instance) | Oui |
| `delete()`, `forceDelete()`, `restore()` (classe et instance) | Oui |
| `increment()` / `decrement()` | Oui |
| `attach()` / `detach()` | Oui (table pivot) |
| `OrvexORM.transaction` / `tx:commit()` | Oui, pour chaque table ecrite, **apres** un commit reussi |
| `OrvexORM.raw()` / `rawExec()` qui ecrit | Oui : la table ecrite, ou **tout** le cache si elle ne peut pas etre determinee |
| `find()` / `findAll()` | Non (lecture seule) |
| `query():get()` | Non (lecture seule) |

L'invalidation est **exacte** : ecrire dans `users` ne vide que les entrees qui lisent `users` (y compris via une jointure ou une sous-requete), pas celles de `users_logs`. Elle ne coute que le nombre d'entrees de cette table.

:::caution Ce que le cache ne voit pas
Une ecriture faite **hors de cette ressource** (autre ressource, autre script SQL, Studio, outil externe) n'invalide rien : les lectures peuvent rester perimees jusqu'au TTL. Les transactions et `raw` n'invalident que le cache **global** : un modele avec son propre `opts.cache` doit etre vide a la main (`Model.flushCache()`).
:::

## Gerer le cache manuellement

### Vider le cache d'un modele

```lua
User.flushCache()
```

### Vider tout le cache

```lua
OrvexORM.flushCache()
```

### Desactiver le cache

```lua
OrvexORM.disableCache()  -- desactive et vide le cache global
```

### Consulter les statistiques

`OrvexORM.cacheStats()` te dit si ton cache est efficace :

```lua
local stats = OrvexORM.cacheStats()

print(stats.hits)     -- lectures servies depuis le cache
print(stats.misses)   -- lectures qui ont interroge la base
print(stats.hitRate)  -- ratio hits / (hits + misses)
print(stats.entries)  -- nombre d'entrees actuellement en cache
print(stats.maxEntries) -- taille maximale (1000 pour le cache global)
```

:::tip Interpreter le hitRate
Un `hitRate` proche de 1 signifie que la plupart des lectures viennent du cache. S'il est tres bas, ton TTL est peut-etre trop court, ou tes requetes sont trop variees pour beneficier du cache.
:::

## Quel TTL choisir ?

| Situation | TTL recommande |
|---|---|
| Donnees qui changent rarement (configs, roles) | `300` (5 minutes) |
| Donnees qui changent souvent (argent, inventaire) | `10` - `30` secondes |
| Donnees en temps reel (position, sante) | Ne pas utiliser le cache |

:::caution Attention au cache avec les donnees critiques
Le cache peut retourner des donnees legerement obsoletes (jusqu'au TTL). Pour des operations critiques comme les transferts d'argent, il est plus sur de ne **pas** cacher ces donnees ou d'utiliser un TTL tres court.
:::

## Le cache avec le Query Builder

Le cache fonctionne aussi avec le Query Builder :

```lua
-- Cette requete est cachee
local cops = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :limit(10)
    :get()

-- Si la meme requete est refaite dans le TTL, le cache est utilise
local cops2 = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :limit(10)
    :get()
-- → pas de requete SQL, resultat identique depuis le cache
```

Les agregations (`count`, `sum`, `avg`, `min`, `max`) sont aussi cachees. Les parcours `chunk` / `chunkById` ne le sont pas (ils evinceraient les entrees utiles).

Une requete dont un parametre est une table, une fonction ou un userdata n'est **pas** mise en cache (sa cle ne serait pas fiable). Les parametres sont distingues par leur type : `1` et `"1"`, ou `true` et `"true"`, donnent des entrees differentes.

## Un cache par modele

Un modele peut avoir son propre cache, avec ses propres reglages, via l'option `cache`. La classe globale `OrvexCache` est disponible dans orvexorm et dans chaque ressource qui utilise `lib/import.lua` :

```lua
local Config = OrvexORM.model("server_config", { key = "string", value = "json" }, {
    primaryKey = "key",
    cache = OrvexCache.new({
        ttl = 300,          -- 5 minutes
        maxEntries = 200,   -- defaut : 1000
    }),
})
```

| Option de `OrvexCache.new` | Defaut | Description |
|---|---|---|
| `ttl` | `60` | Duree de vie en secondes |
| `maxEntries` | `1000` | Nombre maximal d'entrees (eviction LRU) |
| `sweepInterval` | `ttl` (min. 1 s) | Intervalle minimal entre deux purges des entrees expirees |
| `enabled` | `true` | Un cache cree ainsi est **actif** des sa creation, meme si le cache global est desactive |

Ce cache n'est pas concerne par `OrvexORM.enableCache`, `disableCache`, `flushCache` ni `cacheStats`. Utilise ses methodes : `cache:setEnabled(bool)`, `cache:flush()`, `cache:stats()`, `cache:purgeExpired()` (retourne le nombre d'entrees supprimees), ou `Model.flushCache()`.
