---
sidebar_position: 4
---

# Builder (Query Builder)

Le Query Builder te permet de construire des requetes complexes en chainant des methodes. Tu l'obtiens avec `Model.query()`.

```lua
local builder = User.query()
```

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

-- 3. Avec operateur (3 arguments)
:where("money", ">", 1000)

-- 4. Operateur dans la table
:where({ money = { ">", 1000 } })
:where({ job = { "LIKE", "%poli%" } })
:where({ id = { "IN", { 1, 2, 3 } } })
:where({ money = { "BETWEEN", { 500, 5000 } } })
:where({ status = { "!=", "banned" } })
:where({ job = { "IS", "NULL" } })
:where({ job = { "IS NOT", "NULL" } })
```

:::tip Raccourci 2 arguments
`:where("job", "police")` est equivalent a `:where({ job = "police" })`. C'est plus court quand tu n'as qu'une seule condition.
:::

---

### `:orWhere(conditions)`

Ajoute une condition reliee par OR.

```lua
:where({ job = "police" })
:orWhere({ job = "medic" })
-- SQL: WHERE job = ? OR job = ?
```

---

### `:orderBy(column, direction?)`

Trie les resultats.

| Parametre | Type | Defaut | Description |
|---|---|---|---|
| `column` | `string` | — | Colonne de tri |
| `direction` | `"ASC" \| "DESC"` | `"ASC"` | Sens du tri |

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

Limite le nombre de resultats.

```lua
:limit(10)
```

---

### `:offset(n)`

Saute les N premiers resultats (pour la pagination).

```lua
:offset(20)
```

---

### `:select(columns)`

Specifie les colonnes a selectionner (defaut: `"*"`).

```lua
:select("identifier, money")
:select("users.*, profiles.bio")
```

---

### `:leftJoin(table, col1, col2)`

Ajoute un LEFT JOIN.

```lua
:leftJoin("profiles", "profiles.user_id", "users.identifier")
```

---

### `:innerJoin(table, col1, col2)`

Ajoute un INNER JOIN.

```lua
:innerJoin("vehicles", "vehicles.owner_id", "users.identifier")
```

---

### `:rightJoin(table, col1, col2)`

Ajoute un RIGHT JOIN.

```lua
:rightJoin("users", "users.identifier", "vehicles.owner_id")
```

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

### `:whereIn(column, valuesOrSubSQL, params?)`

Filtre avec une liste de valeurs OU une sous-requete IN.

```lua
-- Avec un tableau de valeurs
:whereIn("job", { "police", "medic", "fire" })
-- SQL: WHERE job IN (?, ?, ?)

-- Avec une sous-requete
:whereIn("id", "SELECT user_id FROM active_users WHERE last_login > ?", { "2024-01-01" })
-- SQL: WHERE id IN (SELECT user_id FROM active_users WHERE last_login > ?)
```

---

### `:whereNotIn(column, valuesOrSubSQL, params?)`

Filtre avec NOT IN (tableau ou sous-requete).

```lua
:whereNotIn("id", { 1, 2, 3 })
-- SQL: WHERE id NOT IN (?, ?, ?)

:whereNotIn("id", "SELECT user_id FROM banned_users")
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

### `:after(column, value, direction?)`

Pagination par curseur : recupere les lignes apres une valeur donnee.

```lua
-- Recuperer les 10 joueurs apres l'ID 50
User.query():after("id", 50):limit(10):get()
-- SQL: WHERE id > 50 ORDER BY id ASC LIMIT 10
```

---

### `:before(column, value, direction?)`

Pagination par curseur : recupere les lignes avant une valeur donnee.

```lua
User.query():before("id", 50):limit(10):get()
-- SQL: WHERE id < 50 ORDER BY id ASC LIMIT 10
```

---

## Methodes terminales

Ces methodes **executent** la requete et retournent un resultat.

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

Compte les lignes.

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

Retourne un tableau des valeurs d'une seule colonne.

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

Traite les resultats par lots pour eviter de tout charger en memoire.

```lua
User.query():chunk(100, function(rows, chunkIndex)
    -- traiter le lot...
    return false -- retourner false pour arreter
end)
```

---

### `:paginate(page, perPage?)` → `table`

Pagine les resultats automatiquement. Retourne un objet avec les donnees et les metadonnees de pagination.

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

print(sql)     -- SELECT * FROM users WHERE job = ? AND money > ?
print(params)  -- { "police", 500 }
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
    :where({ job = { "IN", { "police", "medic" } } })
    :where({ money = { "BETWEEN", { 1000, 50000 } } })
    :orderBy("money", "DESC")
    :limit(20)
    :get()
```
