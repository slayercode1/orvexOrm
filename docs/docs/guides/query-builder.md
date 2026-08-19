---
sidebar_position: 3
---

# Query Builder

Le **Query Builder** te permet de construire des requetes avancees en chainant des methodes. C'est comme construire une phrase piece par piece.

## Le principe

Au lieu d'ecrire du SQL a la main, tu chaines des methodes :

```lua
-- Au lieu de :
-- SELECT * FROM users WHERE job = 'police' AND money > 1000 ORDER BY money DESC LIMIT 10

-- Tu ecris :
local results = User.query()
    :where({ job = "police" })
    :where("money", ">", 1000)
    :orderBy("money", "DESC")
    :limit(10)
    :get()
```

Chaque methode ajoute une piece a la requete. A la fin, `:get()` execute la requete et retourne les resultats.

---

## Filtrer avec `:where()`

### Egalite simple

```lua
-- Tous les policiers (table)
User.query()
    :where({ job = "police" })
    :get()
-- SQL: WHERE job = ?

-- Ou en raccourci (2 arguments, = implicite)
User.query()
    :where("job", "police")
    :get()
-- SQL: WHERE job = ?
```

### Avec un operateur

```lua
-- Joueurs avec plus de 1000$
User.query()
    :where("money", ">", 1000)
    :get()
-- SQL: WHERE money > ?
```

### Combiner plusieurs conditions

```lua
-- Policiers avec plus de 1000$
User.query()
    :where({ job = "police" })
    :where("money", ">", 1000)
    :get()
-- SQL: WHERE job = ? AND money > ?
```

Quand tu chaines plusieurs `:where()`, ils sont relies par **AND** (les deux conditions doivent etre vraies).

---

## Tous les operateurs

### Plus grand / plus petit

```lua
:where("money", ">", 1000)    -- plus grand que 1000
:where("money", ">=", 1000)   -- plus grand ou egal a 1000
:where("money", "<", 500)     -- plus petit que 500
:where("money", "<=", 500)    -- plus petit ou egal a 500
```

### Different de

```lua
:where({ status = { "!=", "banned" } })
-- SQL: WHERE status != ?
```

### LIKE (recherche de texte)

```lua
-- Tous les jobs qui contiennent "poli"
:where({ job = { "LIKE", "%poli%" } })
-- SQL: WHERE job LIKE ?
```

Le `%` est un joker qui remplace n'importe quel texte :
- `"%poli%"` → contient "poli" n'importe ou
- `"poli%"` → commence par "poli"
- `"%poli"` → finit par "poli"

### IN (parmi une liste)

```lua
-- Policiers, medecins ou pompiers
:where({ job = { "IN", { "police", "medic", "firefighter" } } })
-- SQL: WHERE job IN (?, ?, ?)
```

### BETWEEN (entre deux valeurs)

```lua
-- Joueurs qui ont entre 500$ et 5000$
:where({ money = { "BETWEEN", { 500, 5000 } } })
-- SQL: WHERE money BETWEEN ? AND ?
```

### IS NULL / IS NOT NULL

```lua
-- Joueurs sans job
:where({ job = { "IS", "NULL" } })
-- SQL: WHERE job IS NULL

-- Joueurs avec un job
:where({ job = { "IS NOT", "NULL" } })
-- SQL: WHERE job IS NOT NULL
```

---

### Raccourcis pour les filtres courants

Au lieu d'utiliser la syntaxe `{ col = { "OP", val } }`, tu peux utiliser des methodes dediees :

```lua
-- whereIn : parmi une liste de valeurs
User.query():whereIn("job", { "police", "medic", "fire" }):get()

-- whereNotIn : pas dans la liste
User.query():whereNotIn("id", { 1, 2, 3 }):get()

-- whereBetween : entre deux valeurs
User.query():whereBetween("money", 500, 5000):get()

-- whereNotBetween : en dehors de la plage
User.query():whereNotBetween("money", 0, 100):get()

-- whereLike : recherche de texte
User.query():whereLike("name", "%john%"):get()
```

---

## SQL libre avec `:whereRaw()`

Quand aucune methode ne couvre ton besoin, `:whereRaw(clause, params?)` te permet d'ecrire une clause SQL libre. Elle est entouree de parentheses et combinee en **AND** avec les autres conditions.

```lua
-- Fonction SQL dans la condition
User.query()
    :whereRaw("LOWER(job) = ?", { "police" })
    :get()
-- SQL: WHERE (LOWER(job) = ?)

-- OR imbrique dans un groupe
User.query()
    :where({ status = "active" })
    :whereRaw("money > ? OR job = ?", { 10000, "police" })
    :get()
-- SQL: WHERE status = ? AND (money > ? OR job = ?)
```

:::caution Injection SQL
Passe **toujours** les valeurs via `params`, jamais par concatenation de chaine. `:whereRaw("name = '" .. input .. "'")` est une porte ouverte a l'injection SQL.
:::

---

## OR WHERE (ou)

Par defaut, les conditions sont reliees par **AND**. Pour utiliser **OR** :

```lua
-- Policiers OU medecins
User.query()
    :where({ job = "police" })
    :orWhere({ job = "medic" })
    :get()
-- SQL: WHERE job = ? OR job = ?
```

```lua
-- Policiers OU medecins OU pompiers
User.query()
    :where({ job = "police" })
    :orWhere({ job = "medic" })
    :orWhere({ job = "firefighter" })
    :get()
-- SQL: WHERE job = ? OR job = ? OR job = ?
```

---

## Trier avec `:orderBy()`

```lua
-- Du plus riche au plus pauvre
User.query()
    :orderBy("money", "DESC")
    :get()
-- SQL: ORDER BY money DESC

-- Par ordre alphabetique de job
User.query()
    :orderBy("job")  -- ASC par defaut
    :get()
-- SQL: ORDER BY job ASC
```

| Direction | Signification |
|---|---|
| `"ASC"` | Croissant (A → Z, 0 → 9). C'est le defaut. |
| `"DESC"` | Decroissant (Z → A, 9 → 0) |

### Raccourcis de tri

```lua
-- Raccourcis sans preciser la direction
User.query():orderByDesc("money"):get()   -- ORDER BY money DESC
User.query():orderByAsc("name"):get()     -- ORDER BY name ASC

-- Les plus recents / les plus anciens (utilise created_at par defaut)
User.query():latest():get()               -- ORDER BY created_at DESC
User.query():oldest():get()               -- ORDER BY created_at ASC

-- Avec une colonne custom
User.query():latest("updated_at"):get()   -- ORDER BY updated_at DESC
```

---

## Paginer avec `:limit()` et `:offset()`

La pagination permet d'afficher les resultats par "pages".

```lua
-- Page 1 : les 10 premiers resultats
User.query()
    :limit(10)
    :offset(0)
    :get()

-- Page 2 : les 10 suivants
User.query()
    :limit(10)
    :offset(10)
    :get()

-- Page 3
User.query()
    :limit(10)
    :offset(20)
    :get()
```

:::tip Formule de pagination
Pour une page donnee :
- `limit` = nombre de resultats par page
- `offset` = (numero de page - 1) * limit

Exemple : page 3, 10 resultats par page → `offset = (3-1) * 10 = 20`
:::

### Raccourci : `:paginate(page, perPage)`

Au lieu de calculer limit/offset toi-meme, utilise `:paginate()` :

```lua
local page = User.query()
    :where({ job = "police" })
    :orderBy("money", "DESC")
    :paginate(2, 10)

print(page.total)     -- nombre total de resultats (ex: 25)
print(page.page)      -- 2
print(page.perPage)   -- 10
print(page.lastPage)  -- 3 (ceil(25/10))
print(#page.data)     -- 10 (les resultats de la page 2)

for _, player in ipairs(page.data) do
    print(player.identifier .. " — " .. player.money .. "$")
end
```

| Champ | Type | Description |
|---|---|---|
| `data` | `OrvexInstance[]` | Les resultats de la page |
| `total` | `integer` | Nombre total d'enregistrements |
| `page` | `integer` | Numero de la page actuelle |
| `perPage` | `integer` | Nombre d'elements par page (defaut: 15) |
| `lastPage` | `integer` | Numero de la derniere page |

### Raccourci : `:first()`

Si tu veux juste le **premier** resultat :

```lua
local richest = User.query()
    :orderBy("money", "DESC")
    :first()
-- Ajoute automatiquement LIMIT 1

if richest then
    print(richest.identifier .. " est le plus riche avec " .. richest.money .. "$")
end
```

---

## Jointures

Les jointures permettent de **combiner des donnees de plusieurs tables** dans une seule requete.

### LEFT JOIN

Retourne toutes les lignes de la table principale, meme si elles n'ont pas de correspondance dans la table jointe.

```lua
-- Tous les joueurs, avec leur profil (si ils en ont un)
User.query()
    :select("users.*, profiles.bio")
    :leftJoin("profiles", "profiles.user_id", "users.identifier")
    :get()
-- SQL: SELECT users.*, profiles.bio FROM users
--      LEFT JOIN profiles ON profiles.user_id = users.identifier
```

### INNER JOIN

Retourne **uniquement** les lignes qui ont une correspondance dans les deux tables.

```lua
-- Seulement les joueurs qui ont au moins un vehicule
User.query()
    :select("users.identifier, vehicles.plate")
    :innerJoin("vehicles", "vehicles.owner_id", "users.identifier")
    :get()
```

### RIGHT JOIN

L'inverse du LEFT JOIN — retourne toutes les lignes de la table jointe.

```lua
Vehicle.query()
    :select("vehicles.*, users.identifier as owner_name")
    :rightJoin("users", "users.identifier", "vehicles.owner_id")
    :get()
```

:::info Quelle jointure choisir ?
- **LEFT JOIN** : "Je veux tous les joueurs, avec ou sans vehicule"
- **INNER JOIN** : "Je veux seulement les joueurs qui ont un vehicule"
- **RIGHT JOIN** : rarement utilise, prefere LEFT JOIN en inversant les tables
:::

---

## GROUP BY et HAVING

### GROUP BY

Regroupe les resultats par une colonne, utile avec les fonctions d'agregation.

```lua
-- Compter le nombre de joueurs par job
User.query()
    :select("job, COUNT(*) as nb_joueurs")
    :groupBy("job")
    :get()
-- Resultat : { { job = "police", nb_joueurs = 5 }, { job = "medic", nb_joueurs = 3 } }
```

### HAVING

Filtre les groupes (comme WHERE, mais pour les groupes).

```lua
-- Seulement les jobs avec plus de 5 joueurs
User.query()
    :select("job, COUNT(*) as nb_joueurs")
    :groupBy("job")
    :having("COUNT(*) > ?", 5)
    :get()
```

---

## Selectionner des colonnes specifiques

Par defaut, OrvexORM selectionne toutes les colonnes (`*`). Tu peux choisir lesquelles :

```lua
-- Seulement identifier et money
User.query()
    :select("identifier, money")
    :where({ job = "police" })
    :get()
-- SQL: SELECT identifier, money FROM users WHERE job = ?
```

---

## Debugger avec `:toSQL()`

Tu peux voir le SQL genere sans executer la requete :

```lua
local sql, params = User.query()
    :where({ job = "police" })
    :where("money", ">", 500)
    :orderBy("money", "DESC")
    :limit(5)
    :toSQL()

print(sql)
-- SELECT * FROM users WHERE job = ? AND money > ? ORDER BY money DESC LIMIT 5

print(params[1], params[2])
-- police    500
```

:::tip Utile pour le debug
Utilise `:toSQL()` quand quelque chose ne fonctionne pas comme prevu. Ca te montre exactement quelle requete SQL serait generee.
:::

---

## Methodes utilitaires

### `:pluck(column)` — Extraire une colonne

Retourne un tableau avec uniquement les valeurs d'une colonne, sans creer d'instances.

```lua
local jobs = User.query():pluck("job")
-- { "police", "medic", "firefighter" }

local richJobs = User.query():where("money", ">", 10000):pluck("job")
```

### `:exists()` — Verifier l'existence

Retourne `true` ou `false` sans charger les donnees. Plus rapide que `:get()`.

```lua
local hasCops = User.query():where("job", "police"):exists()
if hasCops then
    print("Il y a des policiers !")
end
```

### `:chunk(size, callback)` — Traiter par lots

Traite les resultats par paquets pour eviter de tout charger en memoire.

```lua
-- Traiter tous les joueurs par lots de 100
User.query():chunk(100, function(players, chunkIndex)
    print("Lot " .. chunkIndex .. " : " .. #players .. " joueurs")
    for _, player in ipairs(players) do
        -- traitement...
    end
    -- Retourner false pour arreter
end)
```

---

## Exemple complet

Voici un exemple realiste — un systeme de classement des joueurs les plus riches :

```lua
-- Top 10 des joueurs les plus riches qui ne sont pas bannis
local top10 = User.query()
    :where({ status = { "!=", "banned" } })
    :where("money", ">", 0)
    :orderBy("money", "DESC")
    :limit(10)
    :get()

for i, player in ipairs(top10) do
    print(("#%d — %s : %d$"):format(i, player.identifier, player.money))
end
-- #1 — license:xyz : 50000$
-- #2 — license:abc : 35000$
-- ...
```
