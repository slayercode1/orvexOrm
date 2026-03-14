---
sidebar_position: 7
---

# Transactions

Une **transaction** permet d'executer plusieurs requetes de maniere **atomique** : soit tout reussit, soit rien n'est applique. C'est indispensable quand tu dois garantir la coherence de tes donnees.

## Pourquoi utiliser des transactions ?

Imagine ce scenario : un joueur transfere 1000$ a un autre joueur. Il faut :

1. Retirer 1000$ au joueur A
2. Ajouter 1000$ au joueur B

Si l'etape 1 reussit mais l'etape 2 echoue (crash, erreur...), le joueur A perd son argent mais le joueur B ne recoit rien. L'argent disparait !

Avec une **transaction**, si l'etape 2 echoue, l'etape 1 est automatiquement annulee. L'argent est protege.

## Comment ca marche

### Syntaxe callback (recommandee)

La facon la plus simple : passe une fonction. Le commit est automatique, et en cas d'erreur rien n'est applique.

```lua
local success = ORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:abc", money = 500 })
    tx:update("users", { money = 1000 }, { identifier = "license:def" })
    tx:delete("logs", { identifier = "license:old" })
end)
-- Auto-commit a la fin de la fonction !

if success then
    print("Transaction reussie !")
else
    print("Transaction echouee, tout a ete annule")
end
```

### Syntaxe builder (manuelle)

Tu peux aussi construire la transaction manuellement si tu preferes :

```lua
local tx = ORM.transaction()

-- Ajoute des operations (rien n'est execute pour l'instant)
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("users", { money = 1000 }, { identifier = "license:def" })
tx:delete("logs", { identifier = "license:old" })

-- Tout est execute d'un coup, de maniere atomique
local success = tx:commit()
```

:::tip Quelle syntaxe choisir ?
La **syntaxe callback** est recommandee : elle garantit que tu n'oublieras jamais le `commit()`. La syntaxe builder est utile si tu dois construire ta transaction dynamiquement (boucles, conditions...).
:::

## Les methodes disponibles

Tu peux ajouter n'importe quelle operation a une transaction :

### `tx:insert(table, data)`

```lua
tx:insert("users", { identifier = "license:abc", money = 500, job = "police" })
```

### `tx:update(table, data, where)`

```lua
tx:update("users", { money = 0 }, { identifier = "license:abc" })
```

### `tx:delete(table, where)`

```lua
tx:delete("users", { identifier = "license:abc" })
```

### `tx:upsert(table, data)`

```lua
tx:upsert("users", { identifier = "license:abc", money = 2000 })
```

### `tx:addRaw(sql, params)`

Pour les requetes SQL personnalisees :

```lua
tx:addRaw("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
```

### `tx:commit()` → `boolean`

Execute toutes les requetes d'un coup. Retourne `true` si tout a reussi.

### `tx:getQueries()` → `table`

Retourne la liste des requetes (utile pour le debug).

## Exemples concrets

### Transfert d'argent

```lua
local function transferMoney(fromId, toId, amount)
    local tx = ORM.transaction()

    -- Retirer l'argent au joueur A
    tx:addRaw(
        "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
        { amount, fromId, amount }
    )

    -- Ajouter l'argent au joueur B
    tx:addRaw(
        "UPDATE users SET money = money + ? WHERE identifier = ?",
        { amount, toId }
    )

    local success = tx:commit()

    if success then
        print(("Transfert de %d$ de %s vers %s reussi"):format(amount, fromId, toId))
    else
        print("Transfert echoue — aucune modification appliquee")
    end

    return success
end
```

### Achat d'un vehicule

```lua
local function buyVehicle(playerId, vehicleModel, price)
    local tx = ORM.transaction()

    -- Debiter le joueur
    tx:addRaw(
        "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
        { price, playerId, price }
    )

    -- Creer le vehicule
    tx:insert("vehicles", {
        owner = playerId,
        model = vehicleModel,
        plate = GeneratePlate(),
        fuel  = 100,
    })

    return tx:commit()
end
```

### Suppression d'un joueur et de ses donnees

```lua
local function deletePlayer(identifier)
    local tx = ORM.transaction()

    tx:delete("vehicles", { owner = identifier })
    tx:delete("inventories", { owner = identifier })
    tx:delete("user_roles", { user_id = identifier })
    tx:delete("users", { identifier = identifier })

    return tx:commit()
end
```

:::tip Quand utiliser une transaction ?
Utilise une transaction quand tu modifies **plusieurs tables** ou **plusieurs lignes** qui doivent rester coherentes entre elles. Si une seule operation echoue, toutes les autres sont annulees.
:::
