---
sidebar_position: 7
---

# Transactions

Une **transaction** execute plusieurs requetes de maniere **atomique** : soit elles reussissent toutes, soit aucune n'est appliquee. C'est indispensable quand plusieurs ecritures doivent rester coherentes entre elles.

## Comment ca marche

Une transaction OrvexORM est une **liste de requetes** : tu les ajoutes avec les methodes `tx:*`, puis elles partent ensemble au driver (`transactionSync` d'oxmysql, `MySQL.Async.transaction` de mysql-async) au moment du `commit()`. Si l'une d'elles **echoue** (erreur SQL), MySQL annule toutes les autres.

Deux consequences importantes :

1. **Rien n'est execute avant le commit.** Tu ne peux donc pas lire une valeur ni verifier le resultat d'une requete au milieu d'une transaction.
2. **Une requete qui ne touche aucune ligne n'est pas un echec.** Un `UPDATE ... WHERE money >= ?` qui ne trouve rien reussit (0 ligne modifiee) : les requetes suivantes s'executent quand meme et `commit()` retourne `true`. Voir [Transfert d'argent](#transfert-dargent) pour la bonne facon de faire.

### Syntaxe callback (recommandee)

Passe une fonction : le commit est automatique a la fin.

```lua
local success = OrvexORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:abc", money = 500 })
    tx:update("users", { money = 1000 }, { identifier = "license:def" })
    tx:delete("logs", { identifier = "license:old" })
end)
-- Auto-commit a la fin de la fonction !

if success then
    print("Transaction reussie !")
else
    print("Transaction echouee, rien n'a ete applique")
end
```

Si la fonction **leve une erreur**, rien n'est envoye : la transaction n'est pas commitee et l'erreur remonte a l'appelant.

### Syntaxe builder (manuelle)

```lua
local tx = OrvexORM.transaction()

-- Ajoute des operations (rien n'est execute pour l'instant)
tx:insert("users", { identifier = "license:abc", money = 500 })
tx:update("users", { money = 1000 }, { identifier = "license:def" })
tx:delete("logs", { identifier = "license:old" })

-- Tout est execute d'un coup, de maniere atomique
local success = tx:commit()
```

:::tip Quelle syntaxe choisir ?
La **syntaxe callback** est recommandee : tu n'oublies jamais le `commit()`. La syntaxe builder est utile pour construire la transaction dynamiquement (boucles, conditions...).
:::

## Ce qui fait partie de la transaction (et ce qui n'en fait pas partie)

:::danger Seules les methodes `tx:*` sont transactionnelles
Dans la callback, un appel de modele (`User.create`, `User.update`, `player:update`, `player:delete`...) est **execute tout de suite, hors transaction**. Il n'est pas annule si la transaction echoue.

```lua
OrvexORM.transaction(function(tx)
    tx:delete("vehicles", { owner = id })      -- dans la transaction
    User.update({ money = 0 }, { identifier = id })  -- PAS dans la transaction : deja execute
end)
```
:::

Les methodes `tx:insert`, `tx:update`, `tx:upsert` et `tx:delete` generent le SQL directement a partir de la table et des donnees. Elles **ne passent pas** par le modele, donc :

| Fonctionnalite du modele | Avec `tx:*` |
|---|---|
| Validation des types et refus des colonnes inconnues | Non |
| Encodage JSON des colonnes `json` / `auto` | Non : encode toi-meme avec `json.encode` |
| `created_at` / `updated_at` (timestamps) | Non : renseigne-les toi-meme |
| Soft delete (`tx:delete` fait un vrai `DELETE`) | Non |
| Hooks (`beforeCreate`, `afterUpdate`...) | Non |
| Invalidation du cache | Oui, apres un commit reussi (cache global) |

Le cache partage par les modeles (`OrvexORM.enableCache`) est invalide pour chaque table ecrite, **une fois le commit reussi** (et vide entierement pour un `addRaw` dont la table ne peut pas etre determinee). Un modele cree avec son propre `opts.cache` n'est pas couvert : appelle `Model.flushCache()` apres la transaction.

## Les methodes disponibles

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

Pour les requetes SQL personnalisees (toujours avec des `?`, jamais de concatenation) :

```lua
tx:addRaw("UPDATE users SET money = money + ? WHERE job = ?", { 100, "police" })
```

### `tx:commit()` → `boolean`

Execute toutes les requetes d'un coup. Retourne `true` si le driver a tout applique, `false` sinon. Une transaction vide retourne `true` sans rien envoyer.

:::caution Un echec peut aussi lever une erreur
Selon le driver, un echec peut remonter comme une **erreur Lua** plutot que `false` (l'export `transactionSync` d'oxmysql leve l'erreur SQL ; mysql-async < 3.3 leve `atomic transactions need mysql-async >= 3.3`). Si tu dois toujours obtenir un booleen, entoure l'appel d'un `pcall` :

```lua
local ok, result = pcall(OrvexORM.transaction, function(tx) ... end)
local success = ok and result == true
```
:::

### `tx:getQueries()` → `table`

Retourne la liste des requetes en attente (`{ query = "...", values = {...} }`), utile pour le debug.

### Adaptateur personnalise

`OrvexORM.transaction(fn, adapter)` et `OrvexORM.transaction(adapter)` utilisent l'adaptateur donne au lieu de celui par defaut. Si son driver n'implemente pas `transaction`, l'adaptateur execute les requetes **une par une, sans atomicite** : voir [setAdapter](/docs/api/orm#ormsetadapteradapter).

## Exemples concrets

### Transfert d'argent

Le piege classique : un debit conditionnel (`AND money >= ?`) suivi d'un credit. Si le joueur A n'a pas assez d'argent, le debit touche 0 ligne **sans erreur**, le credit s'execute quand meme et de l'argent apparait de nulle part. Une transaction ne peut pas l'empecher, puisqu'elle ne lit pas le nombre de lignes touchees entre deux requetes.

La solution sure : **une seule requete conditionnelle** qui debite et credite en meme temps, puis la verification de son resultat. Une requete unique est atomique par nature (InnoDB) : soit les deux lignes changent, soit aucune.

```lua
--- Retourne true si le transfert a eu lieu.
local function transferMoney(fromId, toId, amount)
    if fromId == toId or type(amount) ~= "number" or amount <= 0 then
        return false
    end

    local affected = OrvexORM.rawExec([[
        UPDATE users AS sender
        JOIN users AS receiver ON receiver.identifier = ?
        SET sender.money = sender.money - ?,
            receiver.money = receiver.money + ?
        WHERE sender.identifier = ? AND sender.money >= ?
    ]], { toId, amount, amount, fromId, amount })

    -- 2 lignes modifiees (debiteur + crediteur) : transfert fait.
    -- 0 : solde insuffisant ou joueur introuvable, rien n'a change.
    return affected == 2
end
```

`OrvexORM.rawExec` retourne ce que le driver renvoie pour un `UPDATE` : le nombre de lignes modifiees (oxmysql et mysql-async). Il invalide aussi le cache partage : ici tout le cache, car OrvexORM ne sait pas lire la table d'un `UPDATE ... JOIN` (une requete simple n'invalide que sa table).

### Achat d'un vehicule

Ici il faut deux requetes (un `INSERT` et un `UPDATE`) : impossible de tout faire en une. On rend donc **chaque requete conditionnelle a la meme verification**, et on **verrouille** la ligne du joueur avec `FOR UPDATE` pour qu'aucun autre achat ne modifie son solde entre les deux :

```lua
--- Retourne true si le vehicule a ete achete.
local function buyVehicle(playerId, vehicleModel, price)
    local plate = GeneratePlate()  -- ta fonction, plaques uniques

    local committed = OrvexORM.transaction(function(tx)
        -- 1. Cree le vehicule seulement si le joueur peut payer, et verrouille sa ligne
        tx:addRaw([[
            INSERT INTO vehicles (owner, model, plate, fuel)
            SELECT identifier, ?, ?, 100 FROM users
            WHERE identifier = ? AND money >= ?
            FOR UPDATE
        ]], { vehicleModel, plate, playerId, price })

        -- 2. Debite avec la meme condition (la ligne est verrouillee depuis l'etape 1)
        tx:addRaw(
            "UPDATE users SET money = money - ? WHERE identifier = ? AND money >= ?",
            { price, playerId, price }
        )
    end)

    -- Solde insuffisant : les deux requetes ont touche 0 ligne, rien n'a change.
    -- On verifie donc que le vehicule existe bien.
    return committed and Vehicle.exists({ plate = plate })
end
```

Si le solde est insuffisant, aucune des deux requetes ne trouve de ligne : rien n'est cree ni debite, et `Vehicle.exists` retourne `false`. Si deux achats arrivent en meme temps, le second attend le verrou du premier puis voit le nouveau solde. Si MySQL detecte un interblocage, la transaction echoue en entier.

:::tip Alternative sans verrou
Quand l'ordre le permet, debite d'abord avec une requete conditionnelle **hors transaction**, verifie le nombre de lignes touchees, puis cree le vehicule ; en cas d'echec de la creation, rembourse. C'est plus simple a lire, mais ce n'est pas atomique : prefere la version ci-dessus.
:::

### Suppression d'un joueur et de ses donnees

Ici chaque requete est inconditionnelle : la transaction suffit.

```lua
local function deletePlayer(identifier)
    local tx = OrvexORM.transaction()

    tx:delete("vehicles", { owner = identifier })
    tx:delete("inventories", { owner = identifier })
    tx:delete("user_roles", { user_id = identifier })
    tx:delete("users", { identifier = identifier })

    return tx:commit()
end
```

:::tip Quand utiliser une transaction ?
Utilise une transaction quand plusieurs ecritures doivent reussir ou echouer **ensemble** et qu'aucune ne depend du resultat d'une autre. Quand une ecriture depend d'une condition (solde suffisant, stock disponible...), mets la condition **dans chaque requete** et verifie le resultat, comme dans les exemples ci-dessus.
:::

:::info Async
`commit()` attend la reponse de la base : appelle-le depuis un thread, un event ou une commande. Voir [Async et threads](/docs/getting-started#async-et-threads).
:::
