---
sidebar_position: 4
---

# Builder (Query Builder)

Le Query Builder te permet de construire des requetes complexes en chainant des methodes. Tu l'obtiens avec `Model.query()`.

```lua
local builder = User.query()
```

:::info Identifiants et valeurs
- Les **valeurs** passent toujours par des parametres `?` : jamais concatenees au SQL. Une valeur de condition (y compris les elements de `IN` / `BETWEEN` et les curseurs `after` / `before`) doit etre une chaine, un booleen ou un nombre fini : une table, `NaN` ou l'infini levent une erreur. Voir [Valeurs venues du client](/docs/guides/query-builder#valeurs-venues-du-client).
- Les **noms** de colonnes et de tables sont valides (lettres, chiffres, `_` et `.` uniquement, sans segment vide : `a..b`, `.a` ou `a.` sont refuses ; sinon `Invalid SQL identifier`) puis entoures de backticks : `` `group` ``, `` `users`.`money` ``. Les mots reserves de MySQL (`group`, `key`, `order`, `rank`...) sont donc utilisables comme noms de colonnes.
- Les operateurs sont limites a `=`, `!=`, `<>`, `>`, `<`, `>=`, `<=`, `LIKE`, `NOT LIKE`, `IN`, `NOT IN`, `BETWEEN`, `IS`, `IS NOT`.
- `:whereRaw()`, `:having()`, `:whereExists()`, `:whereInSub()` et `:whereNotInSub()` sont inseres **tels quels** : n'y mets jamais de donnees du joueur, passe-les en parametres. `:whereIn()` / `:whereNotIn()` n'acceptent qu'un tableau, toujours lie en parametres : une chaine (par exemple un payload d'event client mal forme) leve une erreur au lieu d'etre inseree comme sous-requete.

Un modele avec `softDelete` ajoute le filtre `deleted_at IS NULL` comme une **contrainte** : elle est toujours combinee en `AND` devant tes conditions, qu'un `orWhere` ne peut pas contourner.
:::

---

## Methodes chainables

Toutes ces methodes retournent le builder, ce qui permet de les chainer.

### `:where(conditions)`

Ajoute une condition WHERE (reliee par AND).

**4 facons de l'utiliser :**

```lua
-- 1. Egalite simple (table)
:where({ job = "police" })

-- 2. Raccourci egalite (2 arguments, = implicite)
:where("job", "police")

-- 3. Avec operateur (3 arguments), y compris IN / BETWEEN / IS
:where("money", ">", 1000)
:where("id", "IN", { 1, 2, 3 })
:where("money", "BETWEEN", { 500, 5000 })

-- 4. Operateur dans la table, avec OrvexORM.op(operateur, valeur)
:where({ money = OrvexORM.op(">", 1000) })
:where({ job = OrvexORM.op("LIKE", "%poli%") })
:where({ id = OrvexORM.op("IN", { 1, 2, 3 }) })
:where({ money = OrvexORM.op("BETWEEN", { 500, 5000 }) })
:where({ status = OrvexORM.op("!=", "banned") })
:where({ job = OrvexORM.op("IS", "NULL") })
:where({ job = OrvexORM.op("IS NOT", "NULL") })
```

:::caution Pas de table ordinaire comme valeur
Dans la forme table, seule une valeur creee par `OrvexORM.op` (alias `OrvexBuilder.op`) est lue comme un operateur. Une table ordinaire, comme l'ancienne syntaxe `{ money = { ">", 1000 } }`, leve une erreur (`a plain table is not a value; build operator conditions with ORM.op(operator, value)`). Un client ne peut donc pas transformer une egalite en `LIKE '%'` en envoyant `{ "LIKE", "%" }` a la place d'une chaine.
:::

:::tip Raccourci 2 arguments
`:where("job", "police")` est equivalent a `:where({ job = "police" })`. C'est plus court quand tu n'as qu'une seule condition.
:::

:::caution Valeur `nil`
`:where("job", nil)` ou `:where("job", "=", nil)` leve une erreur (`value is nil, use whereNull() / whereNotNull()`) au lieu de generer une condition silencieusement fausse. Utilise `:whereNull("job")`. Dans la forme table, une cle a `nil` n'existe pas en Lua et est donc ignoree.
:::

---

### `:orWhere(conditions)`

Ajoute une condition reliee par OR. Memes formes que `:where()`.

```lua
:where({ job = "police" })
:orWhere({ job = "medic" })
-- SQL: WHERE `job` = ? OR `job` = ?

-- Sur un modele avec softDelete, tes conditions sont groupees apres le filtre :
-- WHERE `deleted_at` IS NULL AND (`job` = ? OR `job` = ?)
```

:::caution Priorite de AND / OR
Tes conditions sont jointes dans l'ordre ou tu les ajoutes, et MySQL evalue `AND` avant `OR` : `:where(a):where(b):orWhere(c)` donne `a AND b OR c`, c'est-a-dire `(a AND b) OR c`. Pour un autre groupement, ecris-le avec `:whereRaw("(job = ? OR job = ?)", { "police", "medic" })`.
:::

---

### `:whereColumn(first, operator?, second)`

Compare deux colonnes (sans parametre). Seuls les operateurs de comparaison sont acceptes : `=`, `!=`, `<>`, `>`, `<`, `>=`, `<=`. `IN`, `BETWEEN`, `LIKE` ou `IS` levent une erreur.

```lua
:whereColumn("updated_at", ">", "created_at")
:whereColumn("users.identifier", "vehicles.owner")  -- = implicite
```

---

### `:orderBy(column, direction?)`

Trie les resultats. Un seul tri a la fois : un nouvel appel remplace le precedent.

| Parametre | Type | Defaut | Description |
|---|---|---|---|
| `column` | `string` | — | Colonne de tri |
| `direction` | `"ASC" \| "DESC"` | `"ASC"` | Sens du tri (insensible a la casse ; toute autre valeur leve une erreur) |

```lua
:orderBy("money", "DESC")
:orderBy("name")  -- ASC par defaut
```

---

### `:orderByDesc(column)`

Raccourci pour ORDER BY ... DESC.

```lua
:orderByDesc("money")
```

---

### `:orderByAsc(column)`

Raccourci pour ORDER BY ... ASC.

```lua
:orderByAsc("name")
```

---

### `:latest(column?)`

Trie par la colonne donnee en DESC. Defaut : `"created_at"`.

```lua
:latest()              -- ORDER BY created_at DESC
:latest("updated_at")  -- ORDER BY updated_at DESC
```

---

### `:oldest(column?)`

Trie par la colonne donnee en ASC. Defaut : `"created_at"`.

```lua
:oldest()  -- ORDER BY created_at ASC
```

---

### `:limit(n)`

Limite le nombre de resultats. `n` doit etre un entier >= 0 (un nombre entier ou une chaine numerique comme `"10"`) ; toute autre valeur leve une erreur, si bien qu'une saisie du joueur ne peut jamais atteindre le SQL.

```lua
:limit(10)
```

---

### `:offset(n)`

Saute les N premiers resultats (pour la pagination). Memes regles que `:limit()`. Fonctionne aussi sans `:limit()`.

```lua
:offset(20)
```

---

### `:select(columns)`

Specifie les colonnes a selectionner (defaut: `"*"`), sous forme de **chaine** separee par des virgules (alors que `opts.select` de `find` prend un tableau). Les noms simples (`money`, `users.money`, `users.*`) sont echappes ; les expressions (`COUNT(*) AS nb`, `SUM(money) AS total`) sont gardees telles quelles : ne construis jamais cette chaine avec une saisie du joueur.

```lua
:select("identifier, money")
:select("users.*, profiles.bio")
:select("job, COUNT(*) AS nb")
```

---

### `:leftJoin(table, col1, col2)`

Ajoute un LEFT JOIN.

```lua
:select("users.*, profiles.bio")
:leftJoin("profiles", "profiles.user_id", "users.identifier")
```

---

### `:innerJoin(table, col1, col2)`

Ajoute un INNER JOIN.

```lua
:select("users.*, vehicles.plate")
:innerJoin("vehicles", "vehicles.owner_id", "users.identifier")
```

---

### `:rightJoin(table, col1, col2)`

Ajoute un RIGHT JOIN.

```lua
:select("vehicles.*, users.identifier AS owner_name")
:rightJoin("users", "users.identifier", "vehicles.owner_id")
```

:::caution Selection par defaut avec une jointure
Sur une requete de modele (`Model.query()`) avec une jointure, la selection par defaut est `table.*` de la table du modele, pas `*` : sinon une colonne de meme nom de la table jointe (`id`...) ecraserait la cle primaire de l'instance, et ses ecritures viseraient une autre ligne. Les colonnes de la table jointe ne sont lues que si tu les listes avec `:select()`.
:::

---

### `:groupBy(columns)`

Regroupe les resultats.

```lua
:groupBy("job")
:groupBy("job, department")
```

---

### `:having(clause, ...params)`

Filtre les groupes (utilise avec `groupBy`).

```lua
:having("COUNT(*) > ?", 5)
:having("SUM(money) > ?", 10000)
```

---

### `:distinct()`

Active `SELECT DISTINCT` sur la requete.

```lua
:distinct()
-- SQL: SELECT DISTINCT * FROM users ...
```

---

### `:whereNull(column)`

Filtre les lignes ou la colonne est NULL.

```lua
:whereNull("deleted_at")
-- SQL: WHERE deleted_at IS NULL
```

---

### `:whereNotNull(column)`

Filtre les lignes ou la colonne n'est pas NULL.

```lua
:whereNotNull("email")
-- SQL: WHERE email IS NOT NULL
```

---

### `:whereIn(column, values)`

Filtre avec une liste de valeurs, liees en parametres. Une liste vide leve une erreur (`whereIn requires a non-empty array`) : teste `#values > 0` avant d'appeler. Tout autre type qu'un tableau leve une erreur : pour une sous-requete, utilise `:whereInSub()`. La liste est limitee a `OrvexBuilder.MAX_IN_VALUES` valeurs (10 000 par defaut) : au-dela, une erreur est levee avant tout envoi.

```lua
:whereIn("job", { "police", "medic", "fire" })
-- SQL: WHERE job IN (?, ?, ?)
```

---

### `:whereNotIn(column, values)`

Filtre avec NOT IN (tableau uniquement, comme `:whereIn()`).

```lua
:whereNotIn("id", { 1, 2, 3 })
-- SQL: WHERE id NOT IN (?, ?, ?)
```

---

### `:whereInSub(column, subSQL, params?)`

Filtre avec une sous-requete IN. `subSQL` est insere tel quel : passe les valeurs dans `params`.

```lua
:whereInSub("id", "SELECT user_id FROM active_users WHERE last_login > ?", { "2024-01-01" })
-- SQL: WHERE id IN (SELECT user_id FROM active_users WHERE last_login > ?)
```

---

### `:whereNotInSub(column, subSQL, params?)`

Filtre avec une sous-requete NOT IN.

```lua
:whereNotInSub("id", "SELECT user_id FROM banned_users")
-- SQL: WHERE id NOT IN (SELECT user_id FROM banned_users)
```

---

### `:whereBetween(column, min, max)`

Raccourci pour BETWEEN.

```lua
:whereBetween("money", 500, 5000)
-- SQL: WHERE money BETWEEN ? AND ?
```

---

### `:whereNotBetween(column, min, max)`

Raccourci pour NOT BETWEEN.

```lua
:whereNotBetween("money", 0, 100)
-- SQL: WHERE money NOT BETWEEN ? AND ?
```

---

### `:whereLike(column, pattern)`

Raccourci pour LIKE.

```lua
:whereLike("name", "%john%")
-- SQL: WHERE name LIKE ?
```

---

### `:whereExists(subSQL, params?)`

Filtre avec `WHERE EXISTS` (sous-requete).

```lua
:whereExists("SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.id")
-- SQL: WHERE EXISTS (SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.id)
```

---

### `:whereRaw(clause, params?)`

Ajoute une clause SQL libre, entouree de parentheses et combinee en AND avec les autres conditions.

```lua
:whereRaw("money > ? OR job = ?", { 1000, "police" })
-- SQL: WHERE (money > ? OR job = ?)

:whereRaw("LOWER(name) = ?", { "john" })
-- SQL: WHERE (LOWER(name) = ?)
```

:::caution Injection SQL
Passe **toujours** les valeurs via `params`, jamais par concatenation de chaine. `:whereRaw("name = '" .. input .. "'")` est une porte ouverte a l'injection SQL.
:::

---

### `:after(column, value, direction?)`

Pagination par curseur : recupere les lignes apres une valeur donnee, et trie sur la colonne. `direction` vaut `"ASC"` (defaut) ou `"DESC"` ; en `DESC`, "apres" signifie "plus petit".

```lua
-- Recuperer les 10 joueurs apres l'ID 50
User.query():after("id", 50):limit(10):get()
-- SQL: WHERE `id` > ? ORDER BY `id` ASC LIMIT 10

User.query():after("id", 50, "DESC"):limit(10):get()
-- SQL: WHERE `id` < ? ORDER BY `id` DESC LIMIT 10
```

---

### `:before(column, value, direction?)`

Pagination par curseur : recupere les lignes avant une valeur donnee.

```lua
User.query():before("id", 50):limit(10):get()
-- SQL: WHERE `id` < ? ORDER BY `id` ASC LIMIT 10
```

---

## Methodes terminales

Ces methodes **executent** la requete et retournent un resultat. Elles attendent la base : appelle-les depuis un thread, un event ou une commande ([Async et threads](/docs/getting-started#async-et-threads)).

### `:get()` → `OrvexInstance[]`

Execute la requete et retourne toutes les lignes.

```lua
local results = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :get()
```

---

### `:first()` → `OrvexInstance | nil`

Execute la requete et retourne la premiere ligne (ajoute automatiquement `LIMIT 1`).

```lua
local richest = User.query()
    :orderBy("money", "DESC")
    :first()
```

---

### `:count()` → `integer`

Compte les lignes que la requete retournerait, en ignorant `orderBy`, `limit` et `offset`. Avec `:distinct()`, `:groupBy()` ou `:having()`, la requete est comptee comme une table derivee : `count()` retourne le nombre de lignes distinctes ou de groupes, pas le nombre de lignes brutes. Avec la selection par defaut, la table derivee selectionne les colonnes du `groupBy`, ou sinon `table.*` de la table principale, pour eviter les noms de colonnes en double d'une jointure.

```lua
local nb = User.query()
    :where({ job = "police" })
    :count()
```

---

### `:sum(column)` → `number`

Additionne les valeurs d'une colonne.

```lua
local total = User.query()
    :where({ job = "police" })
    :sum("money")
```

---

### `:avg(column)` → `number`

Calcule la moyenne.

```lua
local avg = User.query():avg("money")
```

---

### `:min(column)` → `any`

Retourne la valeur minimale.

```lua
local min = User.query():min("money")
```

---

### `:max(column)` → `any`

Retourne la valeur maximale.

```lua
local max = User.query():max("money")
```

---

### `:pluck(column)` → `any[]`

Retourne un tableau des valeurs d'une seule colonne. Une colonne qualifiee (`"users.job"`) fonctionne aussi.

```lua
local jobs = User.query():pluck("job")
-- { "police", "medic", "firefighter" }
```

---

### `:exists()` → `boolean`

Verifie si au moins une ligne correspond. Ne charge pas les donnees.

```lua
local hasCops = User.query():where("job", "police"):exists()
```

---

### `:chunk(size, callback)`

Traite les resultats par lots avec `LIMIT` / `OFFSET`, pour eviter de tout charger en memoire. La callback recoit `(rows, chunkIndex)` ; retourner `false` arrete le parcours. Les lots ne sont pas mis en cache. Un `:limit(n)` pose sur le builder borne le nombre total de lignes parcourues, et le parcours commence a son `:offset()`.

```lua
User.query():chunk(100, function(rows, chunkIndex)
    -- traiter le lot...
    return false -- retourner false pour arreter
end)
```

:::caution Prefere `chunkById` sur les grosses tables
Avec `OFFSET`, MySQL relit toutes les lignes precedentes a chaque lot : le cout grandit avec la table. Et si la callback modifie les lignes de facon qu'elles ne correspondent plus au filtre (ou les supprime), les lots suivants **sautent des lignes**.
:::

---

### `:chunkById(size, callback, column?)`

Traite par lots en pagination **keyset** : `WHERE column > dernierCle ORDER BY column LIMIT size`. Cout constant par lot quelle que soit la taille de la table, et aucune ligne sautee si la callback modifie ou supprime les lignes du lot.

| Parametre | Type | Defaut | Description |
|---|---|---|---|
| `size` | `integer` | — | Taille d'un lot (>= 1) |
| `callback` | `function(rows, chunkIndex)` | — | Retourner `false` arrete le parcours |
| `column` | `string` | `"id"` | Colonne **unique** et presente dans les colonnes selectionnees (souvent la cle primaire) |

```lua
User.query():where("job", "police"):chunkById(200, function(cops)
    for _, cop in ipairs(cops) do cop:update({ money = 0 }) end
end, "identifier")
```

Le tri du builder est remplace par celui de `column`. Un `:limit(n)` pose sur le builder borne le nombre total de lignes parcourues ; `:offset()` est refuse (une page keyset ne saute pas de lignes : filtre avec `:where(column, ">", cle)`).

---

### `:paginate(page, perPage?)` → `table`

Pagine les resultats automatiquement (2 requetes : un `count()` et la page). Retourne un objet avec les donnees et les metadonnees de pagination. Le total est juste aussi avec `distinct`, `groupBy` et `having`. `page` et `perPage` doivent etre des entiers >= 1 ; une page si grande que l'`OFFSET` deborderait leve une erreur. `perPage` est limite a `OrvexBuilder.MAX_PER_PAGE` (1000 par defaut) : une valeur venue d'un joueur ne peut pas faire charger une table entiere.

| Parametre | Type | Defaut | Description |
|---|---|---|---|
| `page` | `integer` | — | Numero de la page (commence a 1) |
| `perPage` | `integer` | `15` | Nombre d'elements par page |

```lua
local page = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :paginate(2, 10)

-- page.data     → OrvexInstance[] (les resultats)
-- page.total    → nombre total d'enregistrements
-- page.page     → 2
-- page.perPage  → 10
-- page.lastPage → ceil(total / perPage)
```

---

### `:toSQL()` → `string, table`

Retourne le SQL genere et les parametres **sans executer** la requete.

```lua
local sql, params = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :toSQL()

print(sql)     -- SELECT * FROM `users` WHERE `job` = ? AND `money` > ?
print(params)  -- { "police", 500 }
```

---

### `:clone()` → `OrvexBuilder`

Retourne une copie independante du builder : les conditions ajoutees a la copie n'affectent pas l'original.

```lua
local cops = User.query():where("job", "police")
local richCops = cops:clone():where("money", ">", 10000)
print(cops:count(), richCops:count())
```

---

## Exemples complets

### Classement avec pagination

```lua
-- Page 2 du top des joueurs (10 par page)
local page2 = User.query()
    :where("money", ">", 0)
    :orderBy("money", "DESC")
    :limit(10)
    :offset(10)
    :get()
```

### Statistiques par job

```lua
local stats = User.query()
    :select("job, COUNT(*) as nb, AVG(money) as avg_money")
    :groupBy("job")
    :having("COUNT(*) >= ?", 2)
    :orderBy("avg_money", "DESC")
    :get()
```

### Joueurs avec profil (jointure)

```lua
local players = User.query()
    :select("users.*, profiles.bio, profiles.avatar")
    :leftJoin("profiles", "profiles.user_id", "users.identifier")
    :where({ job = OrvexORM.op("IN", { "police", "medic" }) })
    :where({ money = OrvexORM.op("BETWEEN", { 1000, 50000 }) })
    :orderBy("money", "DESC")
    :limit(20)
    :get()
```
