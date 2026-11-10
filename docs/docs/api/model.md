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

## Conventions

Ces regles valent pour toutes les methodes de cette page.

### Valeurs de retour

| Famille | Retour |
|---|---|
| `update`, `updateWhere`, `delete`, `deleteWhere`, `forceDelete`, `restore`, `increment`, `decrement` | `integer` : le nombre de lignes que le driver declare touchees. `0` = rien n'a change (aucune ligne ne correspondait). Un nombre est toujours "vrai" en Lua : teste `n > 0`, pas `if n then`. |
| `create`, `createWith` | L'instance creee |
| `createMany`, `upsert` | `true` (un `INSERT` renvoie un id, pas un nombre de lignes) |
| `find`, `first`, `findOrFail` | Une instance, ou `nil` (`findOrFail` leve une erreur) |
| `findAll`, `all` | Une liste, eventuellement vide `{}` |

### Erreurs

Une mauvaise utilisation **leve une erreur Lua** dont la position pointe vers **ta** ligne de code (pas vers l'interieur de la librairie) :

- `update` / `delete` / `forceDelete` / `restore` / `increment` / `decrement` sans `where` (ou avec `{}`) : `update() requires a where clause`. C'est volontaire, pour ne jamais toucher toute la table par accident.
- Donnees invalides (mauvais type, colonne inconnue) : voir [Validation](/docs/guides/validation). Quand plusieurs champs sont invalides, c'est le premier dans l'ordre alphabetique qui est signale, toujours le meme.
- `restore` sur un modele sans `softDelete` ; relation inconnue ; identifiant SQL invalide.

Une erreur SQL remontee par le driver est une erreur Lua elle aussi. Utilise `pcall` pour les capturer.

### Conditions (`where`)

- Dans une table `{ colonne = valeur }`, chaque valeur est une **egalite**. Un operateur s'ecrit `OrvexORM.op(operateur, valeur)` : `{ money = OrvexORM.op(">", 100) }`. Une table ordinaire (l'ancienne syntaxe `{ money = { ">", 100 } }`) leve une erreur.
- `OrvexORM.op` est accepte par `find`, `findAll`, `findOrFail`, `first`, `exists`, `count`, `pluck`, `sum` / `avg` / `min` / `max`, `countByRelation` et le query builder (donc les scopes).
- `update` / `updateWhere`, `delete` / `deleteWhere`, `forceDelete`, `restore`, `increment` / `decrement`, `findOrCreate` et `updateOrCreate` n'acceptent que des egalites : un `OrvexORM.op` y leve une erreur.
- Une valeur doit etre une chaine, un booleen ou un nombre fini (pas de table, de `NaN` ni d'infini). Ne passe jamais un argument d'event client sans le convertir : voir [Valeurs venues du client](/docs/guides/query-builder#valeurs-venues-du-client).

### Ordre des arguments

L'API a quelques irregularites historiques, conservees pour la compatibilite :

| Methodes | Ordre |
|---|---|
| `update(data, where)` | **data** puis where (comme `instance:update(data)`) |
| `updateWhere(where, data)` | **where** puis data (alias de `update`, ordre inverse) |
| `count(where?)` | **where** seulement |
| `sum / avg / min / max(column, where?)` | **colonne** puis where |
| `increment / decrement(column, amount, where)` | `amount` **obligatoire** (sur l'instance, `instance:increment(column, amount?)` vaut 1 par defaut) |
| `find(where?, opts?)` / `findAll(where?, opts?)` | `where` optionnel : `findAll()` = toute la table, `find()` = la premiere ligne |
| Selection de colonnes | `opts.select` de `find`/`findAll` prend un **tableau** (`{ "identifier", "money" }`) ou une chaine de noms separes par des virgules (`"identifier, money"`) ; `:select()` du builder prend une **chaine** |

### Async

Chaque methode qui lit ou ecrit attend la base : appelle-la depuis un thread, un event ou une commande ([Async et threads](/docs/getting-started#async-et-threads)). Definir un modele, une relation, un scope ou un hook ne fait aucune requete.

### Les donnees de l'appelant ne sont pas modifiees

`create`, `createMany`, `upsert`, `update` et les hooks `before*` travaillent sur une **copie** de ta table : tu peux reutiliser un modele de donnees sans qu'il recoive `created_at` ou les modifications d'un hook.

---

## CRUD

### `Model.create(data)` → `OrvexInstance`

Insere une nouvelle ligne.

```lua
local player = User.create({ identifier = "license:abc", money = 500 })
```

---

### `Model.find(where?, opts?)` → `OrvexInstance | nil`

Retourne la premiere ligne correspondante, ou `nil`. La requete porte un `LIMIT 1`. `where` accepte les operateurs (`{ money = OrvexORM.op(">", 100) }`) ; sans `where`, retourne la premiere ligne de la table.

| Option | Type | Description |
|---|---|---|
| `include` | `string[]` | Relations a charger en meme temps (eager loading) |
| `select` | `string[]` ou `string` | Colonnes a lire (noms simples, valides et echappes ; une chaine est decoupee sur les virgules) ; la cle primaire est toujours ajoutee |

```lua
local player = User.find({ identifier = "license:abc" })

-- Avec eager loading
local player = User.find({ identifier = "license:abc" }, {
    include = { "profile", "vehicles" }
})
```

---

### `Model.findAll(where?, opts?)` → `OrvexInstance[]`

Retourne toutes les lignes correspondantes (`{}` si aucune). Sans `where`, retourne toute la table. Memes options que `find`.

```lua
local cops = User.findAll({ job = "police" })
```

Avec `opts.include`, les relations sont chargees en **eager loading batche** : une seule requete par relation, quel que soit le nombre de resultats (pas de probleme N+1). `hasOne`, `hasMany` et `belongsTo` utilisent `WHERE fk IN (...)`, `belongsToMany` une seule jointure sur la table pivot pour tous les parents.

```lua
local cops = User.findAll({ job = "police" }, {
    include = { "profile", "vehicles" }
})

for _, cop in ipairs(cops) do
    print(cop.profile.bio)   -- deja charge
    print(#cop.vehicles)     -- deja charge
end
```

---

### `Model.all(opts?)` → `OrvexInstance[]`

Retourne toutes les lignes de la table. Raccourci pour `Model.findAll({}, opts)`.

```lua
local everyone = User.all()

-- Avec eager loading
local everyone = User.all({ include = { "vehicles" } })
```

---

### `Model.upsert(data)` → `boolean`

Insere ou met a jour si la cle primaire (ou une cle unique) existe deja. Declenche `beforeUpsert(data)` puis `afterUpsert(data)`. Avec `timestamps = true`, `created_at` n'est **pas** reecrase sur les lignes existantes : seuls les autres champs sont mis a jour via `ON DUPLICATE KEY UPDATE`.

```lua
User.upsert({ identifier = "license:abc", money = 2000 })
```

---

### `Model.update(data, where)` → `integer`

Met a jour les lignes correspondant a `where` et retourne le nombre de lignes touchees. Declenche `beforeBulkUpdate(data, where)` puis `afterBulkUpdate(data, where, affected)`. Avec `softDelete`, les lignes supprimees en douceur ne sont pas touchees (`AND deleted_at IS NULL`), sauf si `where` contient lui-meme `deleted_at`. `data` ne peut pas contenir `deleted_at`, ni `created_at` / `updated_at` sans `allowManagedColumns` (voir [Validation](/docs/guides/validation#les-colonnes-gerees-par-lorm)).

```lua
local n = User.update({ money = 0 }, { job = "unemployed" })
print(n .. " joueur(s) remis a zero")
```

:::caution
Le parametre `where` est **obligatoire** et doit etre non-vide pour eviter de modifier toute la table.
:::

---

### `Model.delete(where)` → `integer`

Supprime les lignes correspondant a `where` et retourne le nombre de lignes touchees. Si le soft delete est active, marque les lignes comme supprimees (met `deleted_at`) ; une ligne deja supprimee garde sa date de suppression (`AND deleted_at IS NULL`). Declenche `beforeBulkDelete(where)` puis `afterBulkDelete(where, affected)`.

```lua
User.delete({ job = "unemployed" })
```

---

### `Model.createMany(rows)` → `boolean`

Insere plusieurs lignes en une seule requete. Si les lignes n'ont pas toutes les memes cles, un `INSERT` est fait par jeu de cles, tous dans une meme transaction (aucune colonne n'est perdue). Chaque ligne est validee ; `beforeCreate` est declenche pour chaque ligne (sur une copie), puis `afterBulkCreate(rows)` une fois. Aucune instance n'est construite.

```lua
User.createMany({
    { identifier = "license:a", money = 100, job = "police" },
    { identifier = "license:b", money = 200, job = "medic" },
    { identifier = "license:c", money = 300, job = "mechanic" },
})
```

---

### `Model.findOrCreate(where, defaults?)` → `OrvexInstance, boolean`

Cherche un enregistrement, ou le cree s'il n'existe pas (avec `where` + `defaults`). Retourne l'instance et un boolean `created`. `where` n'accepte que des egalites, puisqu'il sert aussi de donnees a la ligne creee. Ce n'est pas atomique : deux appels simultanes peuvent tous les deux creer la ligne si aucune cle unique ne l'empeche. Avec `softDelete`, la recherche ne voit pas les lignes supprimees en douceur : une ligne "supprimee" qui correspond donne une **nouvelle** ligne. Pose un index unique sur les colonnes du `where` pour qu'un doublon leve une erreur au lieu d'etre insere (c'est vrai aussi pour `updateOrCreate`).

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

Met a jour un enregistrement existant (via `instance:update`, donc `beforeUpdate`/`afterUpdate`), ou en cree un nouveau (`beforeCreate`/`afterCreate`). Comme `findOrCreate`, la recherche ignore les lignes supprimees en douceur : un index unique evite les doublons.

```lua
local player, created = User.updateOrCreate(
    { identifier = "license:abc" },   -- condition de recherche
    { money = 1000, job = "police" }  -- donnees a mettre a jour ou creer
)
```

---

### `Model.increment(column, amount, where)` → `integer`

Incremente une colonne numerique, de facon atomique cote MySQL (`money = money + ?`). `amount` est obligatoire et doit etre un nombre fini (une chaine, `NaN` ou l'infini levent une erreur). Avec `softDelete`, les lignes supprimees en douceur ne sont pas touchees (comme `decrement`). Aucun hook n'est declenche.

```lua
User.increment("money", 100, { identifier = "license:abc" })
-- SQL: UPDATE `users` SET `money` = `money` + ? WHERE `identifier` = ?
```

---

### `Model.decrement(column, amount, where)` → `integer`

Decremente une colonne numerique (`amount` obligatoire, aucun hook).

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

### `Model.updateWhere(where, data)` → `integer`

Alias de `update(data, where)` avec les arguments **dans l'ordre inverse** (where d'abord). Memes hooks et meme retour.

```lua
User.updateWhere({ identifier = "license:abc" }, { money = 9999 })
```

---

### `Model.deleteWhere(where)` → `integer`

Alias de `delete(where)`.

```lua
User.deleteWhere({ job = "unemployed" })
```

---

### `Model.forceDelete(where)` → `integer`

Supprime definitivement (ignore le soft delete). Declenche les hooks `beforeBulkDelete` / `afterBulkDelete`.

```lua
User.forceDelete({ identifier = "license:old" })
```

---

### `Model.restore(where)` → `integer`

Restaure des lignes supprimees en douceur (remet `deleted_at` a `NULL`). Necessite `softDelete = true` et un `where` non vide. Aucun hook n'est declenche.

```lua
User.restore({ identifier = "license:abc" })
```

---

### `Model.createWith(data)` → `OrvexInstance`

Cree un enregistrement avec des relations imbriquees (nested writes). Les cles de relation sont automatiquement detectees.

:::danger Jamais de donnees client brutes
**Toute** cle de `data` qui porte le nom d'une relation est traitee comme une ecriture imbriquee : un client qui ajoute `roles = { { name = "admin" } }` a sa table cree des lignes liees. Ne passe jamais une table recue d'un client a `createWith` sans la filtrer : copie seulement les champs attendus.
:::

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

Deroulement :
1. Toutes les lignes imbriquees sont **validees d'abord** : une donnee invalide n'ecrit rien.
2. `INSERT INTO users ...` (via `create`, donc avec ses hooks).
3. Les lignes `hasOne` / `hasMany` recoivent la cle etrangere, passent par les hooks `beforeCreate` de leur modele (sur une copie, une fois par ligne), puis partent dans **une seule transaction**, en `INSERT` multi-lignes (une requete par table) : ici `INSERT INTO profiles ...` et `INSERT INTO vehicles ... VALUES (...), (...)`.
4. Pour `belongsToMany`, chaque ligne liee est creee avec `create` (il faut son id, ses hooks sont donc declenches), puis les lignes pivot sont inserees dans la meme transaction.
5. Une fois la transaction validee, `afterBulkCreate(rows)` est declenche une fois par relation `hasOne` / `hasMany` sur le modele enfant. `afterCreate` n'est **pas** declenche pour ces lignes : aucune instance n'est construite (leur id n'est pas connu).

Si la transaction echoue, les lignes deja creees (le parent et les lignes `belongsToMany`) sont **supprimees**, puis l'erreur est levee : `createWith('users'): nested rows were not written, created rows removed: ...`. Si une de ces suppressions echoue a son tour, le message le dit et liste les lignes restees en base (`these created rows could not be removed: users#12: ...`). Les entrees `belongsTo` sont ignorees.

:::warning Pas entierement atomique
Seules les lignes `hasOne` / `hasMany` et les lignes pivot sont dans la transaction. Le parent et les lignes `belongsToMany` sont crees **avant**, chacun par sa propre requete : pendant ce court intervalle, d'autres requetes peuvent les lire, et en cas d'echec ils sont retires par des `DELETE` de compensation, pas par un rollback. Si tout doit etre atomique, ecris les lignes toi-meme dans `OrvexORM.transaction(function(tx) ... end)`.
:::

---

### `Model.whereHas(relationName, callback?)` → `OrvexBuilder`

Filtre les enregistrements qui ont au moins un enregistrement lie. Utilise `WHERE EXISTS` en SQL. Les lignes liees supprimees en douceur (si le modele lie a `softDelete`) ne comptent pas. Pour `belongsToMany`, la callback filtre la table **liee** (jointe a la table pivot). Un `orWhere` dans la callback reste lie a la ligne parente.

```lua
-- Joueurs qui ont au moins un vehicule
local players = User.whereHas("vehicles"):get()

-- Joueurs qui ont un vehicule avec la plaque "ABC123"
local players = User.whereHas("vehicles", function(b)
    b:where({ plate = "ABC123" })
end):get()
```

**SQL genere (simplifie) :**
```sql
SELECT * FROM `users` WHERE EXISTS (
    SELECT 1 FROM `vehicles` WHERE `vehicles`.`owner_id` = `users`.`identifier`
)
```

---

### `Model.countByRelation(relationName, where?)` → `table`

Compte les enregistrements lies pour chaque enregistrement parent. Utilise une **seule** requete `GROUP BY` pour compter tous les parents d'un coup (au lieu d'un `COUNT` par parent). Les lignes liees supprimees en douceur ne sont pas comptees. Non supporte pour `belongsTo`.

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

Exclut les lignes supprimees en douceur. Attention a l'ordre : `count` prend le `where` en premier, les autres agregations prennent la colonne en premier.

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

Cree la table du modele si elle n'existe pas. Genere automatiquement le SQL `CREATE TABLE IF NOT EXISTS` a partir du schema. Avec `timestamps = true`, ajoute `created_at` / `updated_at` ; avec `softDelete = true`, ajoute `deleted_at`. Si la cle primaire n'est **pas declaree** dans `fields`, une colonne `` `<primaryKey>` INT UNSIGNED NOT NULL AUTO_INCREMENT `` est ajoutee en premier (comme `t:id()`). Une table existante n'est jamais modifiee.

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

CreateThread(function()
    User.sync() -- Cree la table "users" si elle n'existe pas
end)
```

---

### `Model.flushCache()`

Vide les entrees du cache de ce modele (sa table uniquement).

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
| `foreignKey` | `string` | Colonne pivot → cette table **(obligatoire)** |
| `otherKey` | `string` | Colonne pivot → table liee **(obligatoire)** |
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
| `hooks` | `table` | `nil` | Hooks inline `{ beforeCreate = fn, ... }`, un par evenement (voir [Hooks](#hooks-lifecycle)) |
| `scopes` | `table` | `nil` | Scopes inline `{ rich = fn, ... }` |
| `relations` | `function` | `nil` | Callback pour declarer les relations `function(M) ... end` |
| `adapter` | `OrvexAdapter` | defaut | Adaptateur propre au modele |
| `cache` | `OrvexCache` | cache global | Cache propre au modele (voir [Cache](/docs/guides/cache#un-cache-par-modele)) |

| `allowManagedColumns` | `boolean` | `false` | Autorise `created_at` / `updated_at` dans les donnees des ecritures (imports) |

Avec `timestamps` ou `softDelete`, les colonnes `created_at`, `updated_at` et `deleted_at` sont acceptees par la validation meme si tu ne les declares pas dans `fields`. Tes donnees ne peuvent pas les ecrire : `deleted_at` jamais, `created_at` / `updated_at` seulement avec `allowManagedColumns = true` ; les hooks `before*` le peuvent toujours.

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

Quand `softDelete = true`, les suppressions marquent la ligne avec `deleted_at` au lieu de la supprimer. Les ecritures de classe `update` / `updateWhere`, `increment` / `decrement` et `delete` ajoutent `deleted_at IS NULL` : elles ne touchent pas les lignes deja supprimees (sauf si le `where` contient `deleted_at`). `restore` vise toujours les lignes supprimees, `forceDelete` toutes les lignes du `where`.

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

Les hooks permettent d'executer du code avant/apres les ecritures. Les ecritures **sur une instance** declenchent les hooks d'instance ; les ecritures **de classe** (`User.update(data, where)`...) agissent sur un `where`, sans charger les lignes, et declenchent donc les hooks **bulk**, qui recoivent les donnees et la clause au lieu d'une instance.

| Hook | Arguments | Declenche par |
|---|---|---|
| `beforeCreate` | `data` | `create`, `createMany` et `createWith` (une fois par ligne), `findOrCreate`, `updateOrCreate` |
| `afterCreate` | `instance` | `create`, `findOrCreate`, `updateOrCreate` |
| `afterBulkCreate` | `rows` | `createMany`, `createWith` (lignes `hasOne` / `hasMany`, une fois par relation) |
| `beforeUpdate` | `instance, data` | `instance:update`, `updateOrCreate` |
| `afterUpdate` | `instance` | `instance:update`, `updateOrCreate` |
| `beforeDelete` | `instance` | `instance:delete`, `instance:forceDelete` |
| `afterDelete` | `instance` | `instance:delete`, `instance:forceDelete` |
| `beforeBulkUpdate` | `data, where` | `update`, `updateWhere` |
| `afterBulkUpdate` | `data, where, affected` | `update`, `updateWhere` |
| `beforeBulkDelete` | `where` | `delete`, `deleteWhere`, `forceDelete` |
| `afterBulkDelete` | `where, affected` | `delete`, `deleteWhere`, `forceDelete` |
| `beforeUpsert` | `data` | `upsert` |
| `afterUpsert` | `data` | `upsert` |

Les hooks `before*` recoivent une **copie** des donnees et peuvent la modifier (ajouter un champ, changer une valeur) : c'est elle qui est validee puis ecrite. Une colonne ajoutee par un hook doit exister dans le schema (ou etre une colonne geree, voir [Validation](/docs/guides/validation#colonnes-inconnues)). **Aucun hook** n'est declenche par `increment` / `decrement`, `restore`, les methodes `tx:*` des transactions, `OrvexORM.raw` / `rawExec`. Les lignes imbriquees inserees en lot par `createWith` declenchent `beforeCreate` et `afterBulkCreate`, pas `afterCreate`. La liste des evenements est exposee dans `OrvexModelFactory.HOOK_EVENTS`.

Chaque evenement a un raccourci (`User.beforeCreate(fn)`), et `User.hook(event, fn)` fonctionne pour tous. Plusieurs hooks par evenement s'executent dans l'ordre d'enregistrement.

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

-- Ecritures de classe
User.beforeBulkUpdate(function(data, where)
    data.updated_by = "admin"  -- colonne declaree dans le schema
end)

User.afterBulkDelete(function(where, affected)
    print(("%d ligne(s) supprimee(s)"):format(affected))
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
