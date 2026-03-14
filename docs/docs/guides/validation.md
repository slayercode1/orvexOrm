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

A chaque fois que tu utilises `create`, `update` ou `upsert`, OrvexORM verifie que les valeurs correspondent aux types declares.

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
| `User.upsert(data)` | Oui |
| `User.update(data, where)` | Oui (sur `data` seulement) |
| `player:update(data)` | Oui |
| `User.find(where)` | Non (pas de donnees a valider) |
| `User.delete(where)` | Non |

## Gerer les erreurs

La validation lance une **erreur Lua** si les types ne correspondent pas. Tu peux la capturer avec `pcall` :

```lua
local ok, err = pcall(function()
    User.create({
        identifier = 123,          -- devrait etre un string
        money      = "beaucoup",   -- devrait etre un number
    })
end)

if not ok then
    print("Erreur de validation : " .. err)
    -- "Erreur de validation : Field 'identifier': expected string, got number"
end
```

:::tip Conseil
En general, tu n'as pas besoin de capturer les erreurs de validation. Elles sont la pour te signaler un bug dans ton code — si tu envoies le mauvais type, c'est que quelque chose ne va pas dans ta logique.
:::
