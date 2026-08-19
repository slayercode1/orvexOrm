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

---

## Methodes

### `instance:update(data)` → `boolean`

Met a jour cette ligne dans la base de donnees. L'objet local est aussi mis a jour.

```lua
player:update({ money = 1000, job = "medic" })
print(player.money)  -- 1000 (mis a jour localement aussi)
```

**SQL genere :**
```sql
UPDATE users SET job = ?, money = ? WHERE identifier = ?
```

---

### `instance:delete()` → `boolean`

Supprime cette ligne de la base de donnees.

```lua
player:delete()
```

**SQL genere :**
```sql
DELETE FROM users WHERE identifier = ?
```

---

### `instance:get(relationName)` → `OrvexInstance | OrvexInstance[] | nil`

Recupere les donnees liees par une relation.

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

Ajoute un lien dans la table pivot d'une relation `belongsToMany`.

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

### `instance:increment(column, amount?)` → `boolean`

Incremente une colonne numerique. `amount` est optionnel (defaut: 1).

```lua
player:increment("money", 100)
print(player.money)  -- mis a jour localement aussi

player:increment("kills")  -- +1 par defaut
```

**SQL genere :**
```sql
UPDATE users SET money = money + 100 WHERE identifier = ?
```

---

### `instance:decrement(column, amount?)` → `boolean`

Decremente une colonne numerique.

```lua
player:decrement("money", 50)
```

---

### `instance:forceDelete()` → `boolean`

Supprime definitivement, meme si le soft delete est active.

```lua
player:forceDelete()
```

---

### `instance:restore()` → `boolean`

Restaure une ligne supprimee en douceur. Necessite `softDelete = true`.

```lua
player:restore()
print(player.deleted_at)  -- nil
```

---

### `instance:toTable()` → `table`

Retourne une copie "plate" de l'instance : une simple table Lua sans les champs internes (`_tableName`, `_adapter`, etc.) ni metatable. Les relations chargees en eager loading sont converties recursivement.

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
Une instance contient des champs internes et une metatable qui ne survivent pas au passage reseau ni a `json.encode`. `toTable()` te donne une table propre, prete a etre envoyee.
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
