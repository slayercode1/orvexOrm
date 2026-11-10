<div align="center">

# OrvexORM

**L'ORM le plus simple et performant pour FiveM.**

Zero SQL. Zero galere. Juste du Lua propre.

[![Lua](https://img.shields.io/badge/Lua-5.4-blue?logo=lua&logoColor=white)](https://www.lua.org/)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-orange)](https://fivem.net/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![oxmysql](https://img.shields.io/badge/oxmysql-Compatible-purple)](https://github.com/overextended/oxmysql)
[![mysql-async](https://img.shields.io/badge/mysql--async-Compatible-purple)](https://github.com/brouznouf/fivem-mysql-async)

[Documentation](https://slayercode1.github.io/orvexOrm/) | [GitHub](https://github.com/slayercode1/orvexOrm) | [Installation](#installation) | [Exemples](#exemples-rapides)

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

-- Avec OrvexORM (dans un thread : event, commande ou Citizen.CreateThread)
local player = User.find({ identifier = id })
player:update({ money = 1000 })
```

| | Sans ORM | Avec OrvexORM |
|---|---|---|
| SQL a la main | Oui | Non |
| Risque d'erreurs SQL | Eleve | Reduit par les requetes parametrees |
| Validation des types | Non | Automatique |
| Relations entre tables | Complexe | 1 ligne |
| Performance | Depend de toi | Requetes et chargements groupes |

---

## Installation

1. Telecharge la derniere release sur [GitHub Releases](https://github.com/slayercode1/orvexOrm/releases)
2. Extrait le dossier `orvexorm` dans `resources/` de ton serveur
3. Ajoute dans ton `server.cfg` :

```cfg
ensure oxmysql    # ou mysql-async
ensure orvexorm
```

> OrvexORM choisit le driver au premier appel, sans configuration : **oxmysql** (via ses exports
> `executeSync`/`insertSync`/`updateSync`/`transactionSync`) s'il est demarre, sinon **mysql-async**
> (via `exports['mysql-async']`). Si les deux tournent, oxmysql gagne. La librairie MySQL doit etre
> demarree **avant** `orvexorm`. Les transactions sous mysql-async demandent mysql-async **3.3 ou plus**.
> Details : [Installation](https://slayercode1.github.io/orvexOrm/docs/installation#driver-mysql).

4. Dans chaque ressource qui utilise l'ORM, charge OrvexORM avant tes scripts serveur :

```lua
dependency 'orvexorm'
server_script '@orvexorm/lib/import.lua'

server_script 'server/**/*.lua'
```

`lib/import.lua` charge l'ORM **dans ta ressource** : `OrvexORM` y est une vraie table Lua, et les
instances, les query builders et les `tx` gardent leurs methodes. Chaque ressource a donc sa propre
instance de l'ORM (son propre cache, son propre `debug`, son propre adaptateur). L'ancien
`exports.orvexorm:lib()` reste disponible mais **ne transmet pas les methodes** (les exports FiveM
perdent les metatables) : ne l'utilise plus.

### A savoir : les appels attendent la base

Chaque appel a l'ORM attend la reponse de MySQL (il *yield* la coroutine courante). Appelle-le
depuis un handler d'event, une commande ou un `Citizen.CreateThread`, jamais au niveau superieur
d'un script :

```lua
-- server/main.lua
local User = OrvexORM.model("users", { identifier = "string", money = "number" },
    { primaryKey = "identifier" })  -- OK : definir un modele ne touche pas la base

CreateThread(function()
    OrvexORM.migrate()               -- une fois, au demarrage
    print(User.count() .. " joueurs")
end)
```

Hors thread, l'ORM leve une erreur claire (`database calls yield and must run inside
Citizen.CreateThread...`). Voir [Async et threads](https://slayercode1.github.io/orvexOrm/docs/getting-started#async-et-threads).

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
local tous   = User.all()
local first  = User.first({ job = "police" })

-- Recharger depuis la base
player:refresh()

-- Envoyer au client (table propre, sans champs internes)
TriggerClientEvent("monScript:player", src, player:toTable())

-- Verifier
if User.exists({ identifier = "license:abc" }) then ... end

-- Modifier : les ecritures retournent le nombre de lignes touchees
player:update({ money = 1000 })
player:increment("money", 500)
local n = User.update({ job = "medic" }, { identifier = "license:abc" })  -- data, puis where
if n == 0 then print("aucun joueur modifie") end

-- Supprimer
player:delete()
User.delete({ job = "unemployed" })
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

-- Operateurs dans une table de conditions : OrvexORM.op(operateur, valeur)
local riches = User.findAll({ job = "police", money = OrvexORM.op(">", 10000) })

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

-- Traiter par lots (keyset : cout constant, meme sur une grosse table)
User.query():chunkById(100, function(players)
    for _, p in ipairs(players) do p:update({ money = 0 }) end
end, "identifier")

-- Clause SQL libre (toujours avec des parametres, jamais de concatenation !)
User.query():whereRaw("JSON_EXTRACT(position, '$.x') > ?", { 100 }):get()
```

### Cache

```lua
OrvexORM.enableCache({ ttl = 60 })  -- cache lecture 60s (1000 entrees max, LRU)
-- invalide a chaque ecriture : modeles, transactions, OrvexORM.raw / rawExec

-- Surveiller l'efficacite du cache
local stats = OrvexORM.cacheStats()
print(("hits: %d, misses: %d, hit rate: %.0f%%"):format(stats.hits, stats.misses, stats.hitRate * 100))
```

### Relations

```lua
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
User.hasOne("profile", Profile, { foreignKey = "user_id" })
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })

local player   = User.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")
local profile  = player:get("profile")

-- Eager loading batche : 1 seule requete par relation, meme pour 1000 joueurs
local players = User.findAll({ job = "police" }, { include = { "vehicles", "profile" } })
for _, p in ipairs(players) do
    print(p.identifier, #p.vehicles)  -- deja charge, zero requete supplementaire
end

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
-- Toutes les requetes partent ensemble, de facon atomique
local ok = OrvexORM.transaction(function(tx)
    tx:insert("vehicles", { owner = id, model = "sultan", plate = plate })
    tx:delete("vehicle_orders", { plate = plate })
end)
```

Seules les methodes `tx:*` font partie de la transaction (un `User.create` dans la callback part
tout de suite, hors transaction), et elles ne passent ni par la validation, ni par le JSON, ni par
les timestamps, ni par les hooks. Une transaction ne peut pas lire ni verifier le nombre de lignes
touchees entre deux requetes : pour un transfert d'argent, utilise **une seule requete
conditionnelle** et verifie son resultat. Voir le
[guide Transactions](https://slayercode1.github.io/orvexOrm/docs/guides/transactions).

### Migrations

```lua
OrvexORM.migrations({
    {
        name = "maressource_001_create_users",  -- nom unique sur toute la base : prefixe-le
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

CreateThread(function()
    OrvexORM.migrate()  -- leve une erreur a la premiere migration en echec
end)
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
| `"auto"` | `TEXT` | table encodee en JSON, chaine JSON decodee a la lecture |

Une cle absente du schema est refusee (`Unknown field 'x'`), sauf `created_at` / `updated_at`
(avec `timestamps = true`) et `deleted_at` (avec `softDelete = true`), geres par l'ORM.

---

## Performance

Cout cote Lua (hors aller-retour MySQL), mesure par `tests/benchmark.lua` sur Lua 5.4 avec une base simulee :

| Operation | Temps | Requetes |
|---|---|---|
| `Model.find()` | **0.007 ms** | 1 |
| `Model.create()` | **0.006 ms** | 1 |
| `Model.update()` | **0.009 ms** | 1 |
| `Model.delete()` | **0.006 ms** | 1 |
| `instance:increment()` | **0.003 ms** | 1 |
| `Model.findAll()` 1000 lignes | **1.3 ms** | 1 |
| `findAll()` 1000 lignes + `include` hasMany | **3.7 ms** | 2 |
| Query builder (simple) | **0.007 ms** | 0 |
| Cache hit | **0.006 ms** | 0 |

> Le vrai cout est le nombre d'allers-retours vers la base : les requetes sont parametrees et les
> chargements de relations sont groupes (1 requete par relation). Mesure sur ta propre charge.

---

## API complete

<details>
<summary><strong>Model (classe)</strong></summary>

Les ecritures (`update`, `delete`, `forceDelete`, `restore`, `increment`, `decrement`, et leurs
versions instance) retournent le **nombre de lignes touchees** (`0` = rien n'a change).

| Methode | Description |
|---|---|
| `Model.create(data)` | Inserer une ligne |
| `Model.createMany(rows)` | Inserer en masse |
| `Model.createWith(data)` | Inserer avec relations |
| `Model.find(where?, opts?)` | Trouver un enregistrement (`LIMIT 1`, `opts.include` pour les relations) |
| `Model.findOrFail(where)` | Trouver ou erreur |
| `Model.findAll(where?, opts?)` | Trouver tous (`opts.include` = eager loading batche) |
| `Model.all(opts?)` | Toutes les lignes |
| `Model.first(where?)` | Premier resultat |
| `Model.exists(where)` | Existe ? |
| `Model.pluck(col, where?)` | Extraire une colonne |
| `Model.update(data, where)` | Modifier (**data d'abord**) |
| `Model.updateWhere(where, data)` | Modifier (alias, **where d'abord**) |
| `Model.upsert(data)` | Insert ou update |
| `Model.delete(where)` | Supprimer |
| `Model.deleteWhere(where)` | Supprimer (alias) |
| `Model.forceDelete(where)` | Supprimer definitivement |
| `Model.restore(where)` | Restaurer (soft delete) |
| `Model.increment(col, n, where)` | Incrementer (`n` obligatoire) |
| `Model.decrement(col, n, where)` | Decrementer (`n` obligatoire) |
| `Model.findOrCreate(where, defaults)` | Trouver ou creer |
| `Model.updateOrCreate(where, data)` | MAJ ou creer |
| `Model.count(where?)` | Compter (**where d'abord**) |
| `Model.sum/avg/min/max(col, where?)` | Agregations (**colonne d'abord**) |
| `Model.query()` | Query builder |
| `Model.whereHas(rel, fn?)` | Filtrer par relation (`EXISTS`) |
| `Model.countByRelation(rel, where?)` | Compter les relations (1 requete) |
| `Model.scope(name, fn)` | Definir un scope |
| `Model.hook(event, fn)` | Ajouter un hook (instance ou bulk) |
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
| `instance:increment(col, n?)` | Incrementer (`n` = 1 par defaut) |
| `instance:decrement(col, n?)` | Decrementer (`n` = 1 par defaut) |
| `instance:get(relation)` | Charger une relation |
| `instance:attach(relation, inst)` | Lier (pivot) |
| `instance:detach(relation, inst)` | Delier (pivot) |
| `instance:toTable()` | Table propre (safe pour `TriggerClientEvent` / `json.encode`) |
| `instance:refresh()` | Recharger depuis la base |
| `instance:getAttribute(col)` | Lire une colonne nommee comme une methode (`update`, `get`...) |

</details>

<details>
<summary><strong>Query Builder</strong></summary>

| Methode | Description |
|---|---|
| `:where(field, value)` | Egalite (raccourci) |
| `:where(field, op, value)` | Avec operateur |
| `:where({ field = value })` | Table (egalites) |
| `:where({ field = OrvexORM.op(op, value) })` | Table avec operateur (une table ordinaire leve une erreur) |
| `:orWhere(...)` | OR (groupe entre parentheses apres les contraintes du modele) |
| `:whereColumn(a, op?, b)` | Comparer deux colonnes |
| `:whereIn(col, values)` | IN |
| `:whereNotIn(col, values)` | NOT IN |
| `:whereInSub(col, subSQL, params?)` / `:whereNotInSub(...)` | IN / NOT IN sous-requete |
| `:whereBetween(col, min, max)` | BETWEEN |
| `:whereNotBetween(col, min, max)` | NOT BETWEEN |
| `:whereLike(col, pattern)` | LIKE |
| `:whereNull(col)` | IS NULL |
| `:whereNotNull(col)` | IS NOT NULL |
| `:whereExists(subSQL)` | EXISTS |
| `:whereRaw(clause, params?)` | Clause SQL libre (parametree) |
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
| `:chunk(size, fn)` | Traiter par lots (OFFSET) |
| `:chunkById(size, fn, col?)` | Traiter par lots (keyset, recommande) |
| `:toSQL()` | Voir le SQL |

</details>

---

## OrvexORM Studio

Interface web integree pour visualiser et gerer ta base de donnees. **Zero dependance, 100% Lua.**

Dans la console txAdmin :
```
orvexstudio
```

Le studio genere un token secret (ou utilise `orvex_studio_token`, obligatoire sur Windows ; un token trop faible fait refuser le demarrage, genere-le avec `openssl rand -hex 32`) et affiche l'URL d'acces :
```
http://localhost:30120/orvexorm/?token=a1b2c3d4...
```

- Voir toutes les tables et leur schema
- Parcourir, filtrer et trier les donnees
- Ajouter, modifier et supprimer des lignes
- **Loopback uniquement par defaut** (`127.0.0.1`, `::1`) : les autres adresses recoivent un `404`
- Token dans l'URL accepte seulement au premier chargement, puis envoye dans l'en-tete `X-Studio-Token`
- Verrouillage anti-bruteforce (5 echecs = IP bloquee 5 min), 120 requetes/min par adresse, corps limite a 1 Mio
- Filtrage et verrouillage sur l'adresse TCP : derriere un reverse proxy sur la meme machine, tout le monde est `127.0.0.1`
- Session en memoire limitee a 30 minutes, sans cookie persistant
- Fonctionne avec oxmysql **et** mysql-async (meme detection que l'ORM)

Depuis ton PC, passe par un **tunnel SSH** plutot que d'ouvrir le Studio au reseau (le trafic est en HTTP clair) :

```bash
ssh -L 30120:127.0.0.1:30120 user@ton-serveur
# puis ouvre l'URL affichee : http://localhost:30120/orvexorm/?token=...
```

Pour autoriser d'autres adresses (deconseille), avant `orvexstudio` :

```cfg
set orvex_studio_allow "127.0.0.1, ::1, 10.0.0.0/24"   # IP, plages IPv4 CIDR, ou "*"
```

> Arrete le Studio (`orvexstudio stop`) des que tu as fini. Ne partage jamais l'URL.
>
> Documentation complete : [Studio](https://slayercode1.github.io/orvexOrm/docs/guides/studio)

---

## Compatibilite

| | Supporte |
|---|---|
| FiveM | Lua 5.4 |
| oxmysql | Detecte (exports, ou `@oxmysql/lib/MySQL.lua`) |
| mysql-async | Detecte (exports, ou `@mysql-async/lib/MySQL.lua`) ; 3.3+ pour les transactions |
| MySQL | 5.7+ |
| MariaDB | 10.2+ |

---

## Nouveautes v1.3.0

Version de corrections et de durcissement. Liste complete et changements de comportement dans le
[CHANGELOG](CHANGELOG.md). Les points a verifier avant de mettre a jour :

- **Import** : `server_script '@orvexorm/lib/import.lua'` charge l'ORM dans ta ressource (les
  methodes des instances et des builders fonctionnent enfin entre ressources).
- **Valeurs de retour** : `update`, `delete`, `increment`... retournent le nombre de lignes touchees.
- **Conditions** : les operateurs en table s'ecrivent `{ money = OrvexORM.op(">", 100) }` ; l'ancienne forme
  `{ money = { ">", 100 } }` leve une erreur. Les valeurs doivent etre des chaines, booleens ou nombres finis :
  ne passe jamais un argument d'event client sans le convertir. Les ecritures de classe n'acceptent que des egalites.
- **Migrations** : `migrate()` / `rollback()` levent une erreur a la premiere migration en echec. Les noms
  sont uniques sur toute la base (prefixe-les avec ta ressource) et `rollback()` n'annule que les migrations
  de la ressource qui l'appelle.
- **Studio** : loopback uniquement par defaut (`orvex_studio_allow`), token en en-tete pour l'API,
  `orvex_studio_token` trop faible refuse. Les ecritures du Studio fonctionnent enfin sur un vrai FXServer.
- **Drivers** : un driver personnalise sans `:transaction()` est refuse pour les transactions, sauf
  `OrvexAdapter.new(driver, { allowNonAtomicTransactions = true })`.
- **Requetes** : une jointure sur un modele selectionne `table.*` par defaut ; un type de champ inconnu leve
  une erreur.
- **Hooks** : les ecritures de classe declenchent les nouveaux hooks `before/afterBulkUpdate`,
  `before/afterBulkDelete`, `before/afterUpsert`, `afterBulkCreate`.
- **SQL** : identifiants entre backticks (`group`, `key`, `order` utilisables comme colonnes),
  `orWhere` ne contourne plus le soft delete, `limit`/`offset` valides.

## Nouveautes v1.2.0

- **Fix important** : les lectures via l'API globale oxmysql (`MySQL.prepare`) pouvaient
  renvoyer une ligne "aplatie" au lieu d'un tableau de lignes — `find()`/`findAll()`
  utilisent maintenant `MySQL.query`. Sous mysql-async, `create()` recupere desormais
  le vrai `insertId`.
- **Eager loading batche** : `findAll(where, { include = {...} })` charge chaque relation
  en 1 seule requete `IN (...)` au lieu d'une requete par ligne.
- **`countByRelation`** : une seule requete `GROUP BY` au lieu de N requetes COUNT.
- **`instance:toTable()`** : copie propre sans champs internes, safe pour
  `TriggerClientEvent` et `json.encode`.
- **`instance:refresh()`**, **`Model.all()`**, **`Builder:whereRaw()`**,
  **`OrvexORM.cacheStats()`**.
- **Cache** : les lignes en cache ne sont plus mutees par le decodage JSON (corruption
  possible en cas de hits repetes) ; compteurs hits/misses.
- **`upsert`** avec `timestamps = true` ne reecrase plus `created_at` sur les doublons.
- **Studio** : anti-bruteforce par IP, compatible mysql-async, garde-fous supplementaires.

### Correctif v1.2.1

- Mutualisation de l'execution et de la gestion des erreurs SQL du Studio.
- Centralisation des conventions de cles et de tables pour les relations.
- Suppression de traitements dupliques lors du comptage des relations.

---

## Contribuer

Les contributions sont les bienvenues ! N'hesite pas a ouvrir une [issue](https://github.com/slayercode1/orvexOrm/issues) ou une [pull request](https://github.com/slayercode1/orvexOrm/pulls).

---

## Licence

[MIT](LICENSE) - Open source, libre d'utilisation.
