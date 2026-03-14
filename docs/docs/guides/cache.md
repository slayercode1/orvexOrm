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
| `create()` | Oui |
| `upsert()` | Oui |
| `update()` (classe et instance) | Oui |
| `delete()` (classe et instance) | Oui |
| `attach()` / `detach()` | Oui (table pivot) |
| `find()` / `findAll()` | Non (lecture seule) |
| `query():get()` | Non (lecture seule) |

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
OrvexORM.disableCache()
```

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

Les agregations (`count`, `sum`, `avg`, `min`, `max`) sont aussi cachees.
