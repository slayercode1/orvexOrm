---
sidebar_position: 6
---

# Validation

OrvexORM verifie automatiquement que les donnees que tu envoies correspondent aux types que tu as definis dans ton schema. Ca evite de stocker des donnees incorrectes dans ta base de donnees.

## Comment ca marche ?

Quand tu definis un modele, tu declares les types de chaque colonne :

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
})
```

A chaque fois que tu utilises `create`, `update` ou `upsert`, OrvexORM verifie deux choses :

1. chaque cle de tes donnees est une **colonne connue** du modele ;
2. chaque valeur a le **type declare**.

### Exemple : ca marche

```lua
-- OK : identifier est un string, money est un number
User.create({
    identifier = "license:abc",
    money      = 500,
    job        = "police",
})
```

### Exemple : ca plante

```lua
-- ERREUR : money devrait etre un number, pas un string
User.create({
    identifier = "license:abc",
    money      = "beaucoup",   -- ❌ string au lieu de number
    job        = "police",
})
-- Error: Field 'money': expected number, got string
```

## Les types verifies

| Type declare | Type Lua attendu | Exemples valides |
|---|---|---|
| `"string"` | `string` | `"hello"`, `"license:abc"` |
| `"number"` | `number` | `500`, `3.14`, `0` |
| `"boolean"` | `boolean` | `true`, `false` |
| `"json"` | `table` | `{ x = 1 }`, `{ "a", "b" }` |
| `"date"` | `string` | `"2024-03-15"` |
| `"datetime"` | `string` | `"2024-03-15 14:30:00"` |
| `"timestamp"` | `string` | `"2024-03-15 14:30:00"` |
| `"auto"` | n'importe lequel | une table est encodee en JSON, le reste est ecrit tel quel |

Le format des dates n'est pas verifie : seul le type Lua (`string`) l'est. MySQL rejettera une date mal formee.

## Colonnes inconnues

Une cle qui n'est **pas dans le schema** du modele est refusee, meme si la colonne existe dans la table MySQL :

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
})

User.create({ identifier = "license:abc", money = 500, bank = 1000 })
-- Error: Unknown field 'bank'
```

C'est une protection : une faute de frappe (`mony = 500`) ou un champ venu du client ne finit pas silencieusement en SQL. Declare toutes les colonnes que tu ecris.

### Les colonnes gerees par l'ORM

Les colonnes que l'ORM remplit lui-meme sont **acceptees automatiquement** quand l'option correspondante est active, meme si tu ne les declares pas :

| Option | Colonnes acceptees sans declaration |
|---|---|
| `timestamps = true` | `created_at`, `updated_at` |
| `softDelete = true` | `deleted_at` |

Elles sont typees `"datetime"` (une chaine `"AAAA-MM-JJ HH:MM:SS"`, en UTC quand c'est l'ORM qui les remplit). Tu peux donc fixer `created_at` lors d'un import, ou le modifier dans un hook :

```lua
local User = ORM.model("users", { identifier = "string" }, { timestamps = true })

User.create({ identifier = "license:abc", created_at = "2024-01-01 00:00:00" })  -- OK

User.beforeCreate(function(data)
    data.updated_at = "2024-01-01 00:00:00"  -- OK aussi
end)
```

Sans l'option, ces colonnes sont des colonnes comme les autres : elles doivent etre declarees. Si tu les declares toi-meme, ton type est conserve.

:::caution Les hooks sont valides aussi
Les hooks `before*` s'executent **avant** la validation : une colonne qu'un hook ajoute doit etre declaree (ou etre une colonne geree ci-dessus), sinon l'ecriture echoue avec `Unknown field`.
:::

## Les valeurs nil sont acceptees

Si tu ne fournis pas une valeur pour un champ, OrvexORM ne la valide pas. Ca permet d'avoir des colonnes optionnelles :

```lua
-- OK : job n'est pas fourni, pas d'erreur
User.create({
    identifier = "license:abc",
    money      = 500,
    -- job n'est pas precise → la base de donnees utilisera sa valeur par defaut
})
```

## Quand la validation se declenche

La validation est automatique sur ces methodes :

| Methode | Validation |
|---|---|
| `User.create(data)` | Oui |
| `User.createMany(rows)` | Oui (chaque ligne) |
| `User.createWith(data)` | Oui (parent et lignes imbriquees, avant toute ecriture) |
| `User.upsert(data)` | Oui |
| `User.update(data, where)` / `User.updateWhere(where, data)` | Oui (sur `data` seulement) |
| `player:update(data)` | Oui |
| `User.find(where)` | Non (pas de donnees a valider ; les noms de colonnes sont quand meme verifies) |
| `User.delete(where)` | Non |
| `increment` / `decrement` | Non |
| `tx:insert`, `tx:update`, `tx:upsert` (transactions) | **Non** : elles ne passent pas par le modele |
| `OrvexORM.raw` / `rawExec` | Non |

## Gerer les erreurs

La validation lance une **erreur Lua** si une colonne est inconnue ou si un type ne correspond pas. L'erreur pointe vers **ta** ligne de code (le fichier et la ligne de l'appel a `create`/`update`), pas vers l'interieur d'OrvexORM. Quand plusieurs champs sont invalides, c'est le premier dans l'ordre alphabetique qui est signale, toujours le meme d'un appel a l'autre. Tu peux la capturer avec `pcall` :

```lua
local ok, err = pcall(function()
    User.create({
        identifier = 123,          -- devrait etre un string
        money      = "beaucoup",   -- devrait etre un number
    })
end)

if not ok then
    print("Erreur de validation : " .. err)
    -- "Erreur de validation : server.lua:12: Field 'identifier': expected string, got number"
end
```

:::tip Conseil
En general, tu n'as pas besoin de capturer les erreurs de validation. Elles sont la pour te signaler un bug dans ton code — si tu envoies le mauvais type, c'est que quelque chose ne va pas dans ta logique.
:::
