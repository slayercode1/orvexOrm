---
sidebar_position: 2
---

# CRUD (Creer, Lire, Modifier, Supprimer)

CRUD est un acronyme pour les 4 operations de base qu'on fait avec une base de donnees :

- **C**reate (Creer)
- **R**ead (Lire)
- **U**pdate (Modifier)
- **D**elete (Supprimer)

Tout le long de cette page, on utilisera ce modele :

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

:::info Avant de commencer
- Tous ces appels attendent la base : ils doivent tourner dans un thread, un event ou une commande ([Async et threads](/docs/getting-started#async-et-threads)).
- Les ecritures (`update`, `delete`, `increment`...) retournent le **nombre de lignes touchees** (`0` = rien n'a change).
- Le SQL montre ici est simplifie : en vrai, chaque nom de colonne et de table est entre backticks (`` `users`.`money` ``), ce qui permet d'utiliser des mots reserves comme `group` ou `key` comme noms de colonnes.
:::

---

## Create — Creer

### `Model.create(data)`

Insere une nouvelle ligne dans la base de donnees et retourne une **instance**.

```lua
local player = User.create({
    identifier = "license:abc",
    money      = 500,
    job        = "unemployed",
})

-- "player" est une instance, tu peux l'utiliser directement
print(player.money)  -- 500
```

Ta table `data` n'est pas modifiee : l'ORM travaille sur une copie (tu peux reutiliser un meme modele de donnees pour plusieurs `create`). Avec une cle primaire auto-increment, l'instance recoit l'id genere.

**SQL genere :**
```sql
INSERT INTO users (identifier, job, money) VALUES (?, ?, ?)
```

### `Model.upsert(data)`

Insere une ligne, **ou met a jour** si elle existe deja (basee sur la cle primaire ou unique).

C'est tres utile pour sauvegarder des donnees sans se soucier de savoir si le joueur existe deja :

```lua
-- Si "license:abc" n'existe pas → INSERT
-- Si "license:abc" existe deja  → UPDATE money
User.upsert({
    identifier = "license:abc",
    money      = 2000,
})
```

**SQL genere :**
```sql
INSERT INTO users (identifier, money) VALUES (?, ?)
ON DUPLICATE KEY UPDATE identifier = VALUES(identifier), money = VALUES(money)
```

:::tip Quand utiliser upsert ?
Utilise `upsert` quand tu veux sauvegarder des donnees sans savoir si la ligne existe deja. C'est parfait pour les systemes de sauvegarde automatique.
:::

:::info upsert et timestamps
Avec `timestamps = true`, `created_at` n'est pas reecrase quand la ligne existe deja : seuls les autres champs sont mis a jour.
:::

---

## Read — Lire

### `Model.find(where)`

Cherche **une seule** ligne correspondant aux conditions et retourne une instance (ou `nil`). La requete porte un `LIMIT 1`.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    print(player.money)  -- 500
    print(player.job)    -- "unemployed"
else
    print("Joueur introuvable")
end
```

**SQL genere :**
```sql
SELECT * FROM users WHERE identifier = ? LIMIT 1
```

### `Model.findAll(where?)`

Cherche **toutes les lignes** correspondant aux conditions et retourne une liste. Sans argument, `User.findAll()` retourne toute la table (comme `User.all()`).

```lua
local cops = User.findAll({ job = "police" })

print(#cops .. " policiers trouves")  -- "3 policiers trouves"

for _, cop in ipairs(cops) do
    print(cop.identifier .. " a " .. cop.money .. "$")
end
```

**SQL genere :**
```sql
SELECT * FROM users WHERE job = ?
```

### `Model.findAll` avec des operateurs

Tu peux utiliser des operateurs directement dans `find()` et `findAll()`, comme dans le query builder, avec `OrvexORM.op(operateur, valeur)` :

```lua
-- Policiers avec plus de 1000$
local richCops = User.findAll({
    job   = "police",
    money = OrvexORM.op(">", 1000),
})

-- Joueurs actifs avec un job specifique
local players = User.findAll({
    job    = OrvexORM.op("IN", { "police", "medic", "firefighter" }),
    money  = OrvexORM.op("BETWEEN", { 500, 50000 }),
    status = OrvexORM.op("!=", "banned"),
})
```

Une table ordinaire comme valeur (l'ancienne syntaxe `{ money = { ">", 1000 } }`) leve une erreur : seule une valeur creee par `OrvexORM.op` est lue comme un operateur, si bien qu'un argument d'event client ne peut pas changer la condition. Voir [Valeurs venues du client](/docs/guides/query-builder#valeurs-venues-du-client).

:::info Difference entre find et findAll
- `find()` retourne **un seul** resultat (le premier) ou `nil`
- `findAll()` retourne **une liste** (qui peut etre vide `{}`)
:::

### `Model.all(opts?)`

Retourne **toutes les lignes** de la table. C'est un raccourci pour `findAll({}, opts)`.

```lua
local everyone = User.all()
print(#everyone .. " joueurs dans la base")
```

**SQL genere :**
```sql
SELECT * FROM users
```

---

## Update — Modifier

Il y a deux facons de modifier des donnees.

### Instance : `player:update(data)`

Modifie **un joueur specifique** qu'on a deja recupere avec `find()`.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    player:update({ money = 1000, job = "police" })

    -- L'objet local est aussi mis a jour
    print(player.money)  -- 1000
    print(player.job)    -- "police"
end
```

**SQL genere :**
```sql
UPDATE users SET job = ?, money = ? WHERE identifier = ?
```

### Classe : `User.update(data, where)`

Modifie des lignes **sans les chercher d'abord**. Plus rapide si tu n'as pas besoin de lire les donnees. Attention a l'ordre : **les donnees d'abord, le `where` ensuite** (`updateWhere` prend l'ordre inverse).

```lua
-- Mettre tous les chomeurs a 0$
local n = User.update({ money = 0 }, { job = "unemployed" })
print(n .. " joueur(s) modifie(s)")

-- Changer le job d'un joueur specifique
if User.update({ job = "medic" }, { identifier = "license:abc" }) == 0 then
    print("Joueur introuvable")
end
```

Le `where` est obligatoire et ne doit pas etre vide : `User.update({ money = 0 }, {})` leve une erreur, pour ne jamais modifier toute la table par accident. Il n'accepte que des **egalites** (chaine, booleen ou nombre fini) : un `OrvexORM.op` ou une table y levent une erreur. C'est vrai aussi pour `delete`, `forceDelete`, `restore`, `increment` / `decrement` de classe et pour `tx:update` / `tx:delete` des transactions. Pour une condition avec operateur, utilise `User.query():where(...)` puis ecris chaque instance, ou une requete parametree `OrvexORM.rawExec`. Les hooks `beforeBulkUpdate` / `afterBulkUpdate` sont declenches (pas `beforeUpdate`, qui recoit une instance). Sur un modele `softDelete`, `update`, `increment` / `decrement` et `delete` de classe ne touchent pas les lignes deja supprimees (`deleted_at IS NULL` est ajoute).

**SQL genere :**
```sql
UPDATE users SET money = ? WHERE job = ?
```

### Quelle methode choisir ?

| Situation | Methode |
|---|---|
| Tu as deja l'objet joueur | `player:update()` |
| Tu veux modifier sans lire d'abord | `User.update()` |
| Tu veux modifier plusieurs lignes d'un coup | `User.update()` |

---

## Delete — Supprimer

### Instance : `player:delete()`

Supprime **un joueur specifique**.

```lua
local player = User.find({ identifier = "license:abc" })

if player then
    player:delete()
    print("Joueur supprime !")
end
```

**SQL genere :**
```sql
DELETE FROM users WHERE identifier = ?
```

### Classe : `User.delete(where)`

Supprime des lignes **par condition**, sans les chercher d'abord. Retourne le nombre de lignes supprimees et declenche `beforeBulkDelete` / `afterBulkDelete`.

```lua
-- Supprimer tous les chomeurs
local n = User.delete({ job = "unemployed" })
```

**SQL genere :**
```sql
DELETE FROM users WHERE job = ?
```

:::caution Attention aux suppressions en masse
`User.delete({ job = "unemployed" })` supprime **toutes** les lignes qui correspondent. Verifie bien ta condition avant de lancer une suppression en masse.
:::

---

## Methodes avancees

### `findOrFail` — Trouver ou erreur

Comme `find()`, mais lance une erreur si le joueur n'est pas trouve. Utile quand tu es **sur** que la ligne doit exister.

```lua
local player = User.findOrFail({ identifier = "license:abc" })
-- Si le joueur n'existe pas → erreur : "Record not found in 'users' where identifier=license:abc"

-- Plus besoin de verifier nil !
print(player.money)
```

### `first` — Premier resultat

Raccourci pour trouver le premier enregistrement correspondant.

```lua
-- Avec un filtre
local cop = User.first({ job = "police" })

-- Sans filtre (premier de la table)
local anyone = User.first()
```

### `exists` — Verifier l'existence

Retourne `true` ou `false` sans charger les donnees. Plus rapide que `find()`.

```lua
if User.exists({ identifier = "license:abc" }) then
    print("Le joueur existe !")
end
```

### `pluck` — Extraire une colonne

Retourne un tableau avec uniquement les valeurs d'une colonne.

```lua
local jobs = User.pluck("job")
-- { "police", "medic", "firefighter", "unemployed" }

local moneys = User.pluck("money", { job = "police" })
-- { 1500, 3000, 800 }
```

### `toTable` — Envoyer au client

Une instance contient des champs internes et une metatable : elle ne passe pas telle quelle dans `TriggerClientEvent` ou `json.encode`. Utilise `:toTable()` pour obtenir une copie plate, prete a etre envoyee.

```lua
local player = User.find({ identifier = "license:abc" })
TriggerClientEvent("myresource:playerData", src, player:toTable())
```

### `refresh` — Recharger depuis la base

Recharge les colonnes d'une instance depuis la base de donnees. Retourne `false` si la ligne n'existe plus. Comme `update`, `delete`, `forceDelete`, `restore`, `increment` et `decrement` d'instance, il a besoin de la valeur de la cle primaire : une instance chargee par un `:select()` du query builder qui ne la contient pas leve une erreur au lieu de viser une autre ligne.

```lua
if player:refresh() then
    print(player.money)  -- donnees fraiches
end
```

### `updateWhere` / `deleteWhere` — Alias lisibles

```lua
-- Meme chose que User.update(data, where), mais le where d'abord
User.updateWhere({ identifier = "license:abc" }, { money = 9999 })

-- Plus lisible que User.delete(where)
User.deleteWhere({ job = "unemployed" })
```

---

### `findOrCreate` — Trouver ou creer

```lua
local player, created = User.findOrCreate(
    { identifier = "license:abc" },        -- cherche avec ces conditions
    { money = 500, job = "unemployed" }     -- valeurs par defaut si creation
)

if created then
    print("Nouveau joueur !")
else
    print("Joueur existant : " .. player.money .. "$")
end
```

### `updateOrCreate` — Mettre a jour ou creer

```lua
local player, created = User.updateOrCreate(
    { identifier = "license:abc" },
    { money = 1000, job = "police" }
)
```

Le `where` de `findOrCreate` et `updateOrCreate` sert aussi de donnees a la ligne creee : il n'accepte que des egalites (un `OrvexORM.op` leve une erreur). Avec `softDelete`, la recherche ne voit pas les lignes supprimees en douceur : une ligne supprimee qui correspond donne une nouvelle ligne. Pose un **index unique** sur les colonnes du `where` (par exemple `identifier`) pour empecher les doublons.

### `createMany` — Inserer en masse

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
-- SQL: INSERT INTO users (...) VALUES (...), (...), (...)
```

Si les lignes n'ont pas toutes les memes cles, `createMany` fait un `INSERT` par jeu de cles, tous dans une meme transaction : aucune colonne n'est perdue.

### `increment` / `decrement` — Incrementer / Decrementer

```lua
-- Sur la classe : modifier sans chercher d'abord
User.increment("money", 100, { identifier = "license:abc" })
User.decrement("money", 50, { identifier = "license:abc" })

-- Sur l'instance : modifier un joueur qu'on a deja (amount = 1 par defaut)
player:increment("money", 100)
player:decrement("money", 50)
player:increment("kills")
-- SQL: UPDATE users SET money = money + ? WHERE identifier = ?
```

:::tip Prefere increment a update pour les compteurs
`player:update({ money = player.money + 100 })` ecrit une valeur calculee a partir d'une lecture : si une autre ecriture a eu lieu entre-temps, elle est ecrasee. `increment` fait le calcul dans MySQL (`money = money + ?`) et ne perd rien. Sur la classe, `amount` est **obligatoire** : `User.increment("money", 100, where)`. Il doit etre un nombre fini : une chaine, `NaN` ou l'infini levent une erreur (convertis un montant venu du client avec `tonumber` et borne-le).
:::

---

## Soft Delete (Suppression douce)

Si ton modele a `softDelete = true`, les suppressions mettent `deleted_at` au lieu de supprimer la ligne.

```lua
local User = ORM.model("users", { ... }, { softDelete = true })

player:delete()          -- Met deleted_at
player:forceDelete()     -- Supprime vraiment
player:restore()         -- Restaure (remet deleted_at a NULL)
```

Les queries `find`, `findAll`, `first`, `count` et `query()` excluent automatiquement les lignes supprimees, y compris quand tu combines des `orWhere` (le filtre reste toujours applique). Pour lire une ligne supprimee avec `find`, mets une condition explicite sur `deleted_at`, ou utilise `withTrashed()`.

```lua
User.withTrashed():get()    -- Inclure les supprimes
User.onlyTrashed():get()    -- Seulement les supprimes
```

---

## Timestamps automatiques

Si ton modele a `timestamps = true`, `created_at` et `updated_at` sont geres automatiquement.

```lua
local User = ORM.model("users", { ... }, { timestamps = true })

local p = User.create({ identifier = "license:abc", money = 500 })
-- created_at et updated_at sont remplis automatiquement

p:update({ money = 1000 })
-- updated_at est mis a jour automatiquement
```

Tu n'as pas besoin de declarer `created_at` / `updated_at` (ni `deleted_at` avec `softDelete`) dans les champs du modele : la validation les accepte quand l'option est active. Les dates sont ecrites en UTC, au format `AAAA-MM-JJ HH:MM:SS`.

---

## Recapitulatif

| Operation | Methode classe (`.`) | Methode instance (`:`) |
|---|---|---|
| Creer | `User.create(data)` | — |
| Creer avec relations | `User.createWith(data)` | — |
| Creer en masse | `User.createMany(rows)` | — |
| Upsert | `User.upsert(data)` | — |
| Trouver ou creer | `User.findOrCreate(where, defaults)` | — |
| MAJ ou creer | `User.updateOrCreate(where, data)` | — |
| Lire un | `User.find(where)` | — |
| Lire un (ou erreur) | `User.findOrFail(where)` | — |
| Premier resultat | `User.first(where?)` | — |
| Lire plusieurs | `User.findAll(where, opts?)` | — |
| Lire tout | `User.all(opts?)` | — |
| Existe ? | `User.exists(where)` | — |
| Extraire colonne | `User.pluck(col, where?)` | — |
| Modifier | `User.update(data, where)` → lignes touchees | `player:update(data)` |
| Modifier (alias, where d'abord) | `User.updateWhere(where, data)` | — |
| Supprimer | `User.delete(where)` | `player:delete()` |
| Supprimer (alias) | `User.deleteWhere(where)` | — |
| Supprimer (force) | `User.forceDelete(where)` | `player:forceDelete()` |
| Restaurer | `User.restore(where)` | `player:restore()` |
| Incrementer | `User.increment(col, n, where)` | `player:increment(col, n)` |
| Decrementer | `User.decrement(col, n, where)` | `player:decrement(col, n)` |
| Recharger | — | `player:refresh()` |
| Convertir en table | — | `player:toTable()` |
| Lire une colonne nommee comme une methode | — | `player:getAttribute(col)` |
