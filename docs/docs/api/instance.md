---
sidebar_position: 3
---

# Instance

Une **instance** est un objet qui represente une ligne de ta base de donnees. Tu en obtiens une quand tu utilises `create()`, `find()`, ou `query():get()`.

```lua
local player = User.find({ identifier = "license:abc" })
-- "player" est une OrvexInstance
```

Tu peux acceder aux colonnes comme des proprietes normales :

```lua
print(player.identifier)  -- "license:abc"
print(player.money)        -- 500
print(player.job)          -- "police"
```

Une instance ne contient que les colonnes de la ligne (plus les relations chargees et les `_count_*`) : `pairs(player)` ne parcourt que tes donnees. Les methodes et le contexte du modele sont partages par toutes les instances via une metatable unique.

:::caution Colonnes nommees comme une methode
Une colonne qui porte le nom d'une methode d'instance (`update`, `delete`, `get`, `refresh`, `restore`, `increment`, `toTable`...) ne masque plus la methode : `player:update()` appelle toujours la methode. Lis la valeur de la colonne avec `player:getAttribute("update")` ; `toTable()` l'inclut.
:::

Les methodes d'ecriture retournent le **nombre de lignes touchees** (`0` si la ligne n'existe plus), comme les methodes de classe. Voir les [conventions](/docs/api/model#conventions).

---

## Methodes

### `instance:update(data)` → `integer`

Met a jour cette ligne dans la base de donnees et retourne le nombre de lignes touchees. L'objet local est aussi mis a jour. Les donnees sont validees, et `updated_at` est mis a jour si `timestamps = true`. Declenche `beforeUpdate(instance, data)` puis `afterUpdate(instance)`. Si `data` change la cle primaire, l'instance suit : les ecritures suivantes ciblent la nouvelle valeur.

```lua
player:update({ money = 1000, job = "medic" })
print(player.money)  -- 1000 (mis a jour localement aussi)
```

**SQL genere :**
```sql
UPDATE `users` SET `job` = ?, `money` = ? WHERE `identifier` = ?
```

---

### `instance:delete()` → `integer`

Supprime cette ligne de la base de donnees (ou remplit `deleted_at` si le modele a `softDelete`). Declenche `beforeDelete` / `afterDelete`.

```lua
player:delete()
```

**SQL genere :**
```sql
DELETE FROM `users` WHERE `identifier` = ?
```

---

### `instance:get(relationName)` → `OrvexInstance | OrvexInstance[] | nil`

Recupere les donnees liees par une relation.

Une requete est faite a chaque appel (utilise `include` pour charger d'avance). Si la cle de liaison de l'instance vaut `nil`, aucune requete n'est faite : `nil` pour `hasOne`/`belongsTo`, `{}` pour les relations multiples. Les lignes liees supprimees en douceur sont exclues.

Le type de retour depend de la relation :

| Type de relation | Retour |
|---|---|
| `hasOne` | `OrvexInstance` ou `nil` |
| `hasMany` | `OrvexInstance[]` (liste) |
| `belongsTo` | `OrvexInstance` ou `nil` |
| `belongsToMany` | `OrvexInstance[]` (liste) |

```lua
-- hasOne → une instance
local profile = player:get("profile")

-- hasMany → une liste
local vehicles = player:get("vehicles")

-- belongsTo → une instance
local owner = car:get("owner")

-- belongsToMany → une liste
local roles = player:get("roles")
```

:::caution
Le nom passe a `:get()` doit correspondre exactement au nom utilise lors de la definition de la relation (`hasOne("profile", ...)` → `:get("profile")`).
:::

---

### `instance:attach(relationName, relatedInstance)` → `boolean`

Ajoute un lien dans la table pivot d'une relation `belongsToMany` et invalide le cache de la table pivot. Retourne `true`.

```lua
local adminRole = Role.find({ name = "admin" })
player:attach("roles", adminRole)
```

**SQL genere :**
```sql
INSERT INTO user_roles (role_id, user_id) VALUES (?, ?)
```

:::caution
`attach` ne fonctionne **que** sur les relations `belongsToMany`. Si tu l'utilises sur une autre relation, une erreur sera levee.
:::

---

### `instance:detach(relationName, relatedInstance)` → `boolean`

Retire un lien de la table pivot d'une relation `belongsToMany`.

```lua
player:detach("roles", adminRole)
```

**SQL genere :**
```sql
DELETE FROM user_roles WHERE role_id = ? AND user_id = ?
```

---

### `instance:increment(column, amount?)` → `integer`

Incremente une colonne numerique cote MySQL (`money = money + ?`). `amount` est optionnel (defaut: 1), alors qu'il est obligatoire sur `Model.increment`. Aucun hook n'est declenche, la validation et `updated_at` ne s'appliquent pas.

```lua
player:increment("money", 100)
print(player.money)  -- mis a jour localement aussi

player:increment("kills")  -- +1 par defaut
```

**SQL genere :**
```sql
UPDATE `users` SET `money` = `money` + ? WHERE `identifier` = ?
```

---

### `instance:decrement(column, amount?)` → `integer`

Decremente une colonne numerique.

```lua
player:decrement("money", 50)
```

---

### `instance:forceDelete()` → `integer`

Supprime definitivement, meme si le soft delete est active. Declenche `beforeDelete` / `afterDelete`.

```lua
player:forceDelete()
```

---

### `instance:restore()` → `integer`

Restaure une ligne supprimee en douceur. Necessite `softDelete = true`. Aucun hook n'est declenche.

```lua
player:restore()
print(player.deleted_at)  -- nil
```

---

### `instance:toTable()` → `table`

Retourne une copie "plate" de l'instance : une simple table Lua avec toutes les colonnes (y compris celles nommees comme une methode), sans metatable. Les relations chargees en eager loading sont converties recursivement.

Cas d'usage principal : envoyer les donnees au client via `TriggerClientEvent` ou les serialiser avec `json.encode`.

```lua
local player = User.find({ identifier = "license:abc" }, {
    include = { "vehicles" }
})

-- Envoyer au client (une instance ne passe pas telle quelle)
TriggerClientEvent("myresource:playerData", src, player:toTable())

-- Ou serialiser en JSON
local jsonStr = json.encode(player:toTable())
```

:::tip Pourquoi toTable ?
Une instance a une metatable, qui ne survit pas au passage reseau (msgpack) : les methodes seraient perdues, et une colonne nommee comme une methode serait absente. `toTable()` te donne une table propre, prete a etre envoyee.
:::

---

### `instance:refresh()` → `boolean`

Recharge les colonnes de l'instance depuis la base de donnees. Retourne `false` si la ligne n'existe plus, `true` sinon. Les champs JSON sont re-decodes.

```lua
local player = User.find({ identifier = "license:abc" })

-- Quelqu'un d'autre modifie la ligne...
User.update({ money = 9999 }, { identifier = "license:abc" })

-- Recharger les donnees fraiches
if player:refresh() then
    print(player.money)  -- 9999
else
    print("La ligne n'existe plus")
end
```

---

### `instance:getAttribute(name)` → `any`

Lit une colonne, y compris une colonne nommee comme une methode d'instance (que `player[name]` resoudrait vers la methode).

```lua
local Setting = ORM.model("settings", { id = "number", update = "string" })
local s = Setting.find({ id = 1 })
print(s:getAttribute("update"))  -- valeur de la colonne `update`
s:update({ update = "daily" })   -- appelle bien la methode
```
