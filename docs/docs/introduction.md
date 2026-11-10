---
sidebar_position: 1
slug: /introduction
---

# Introduction

## C'est quoi OrvexORM ?

Quand tu fais un serveur FiveM, tu dois souvent sauvegarder des choses dans une base de donnees : l'argent d'un joueur, ses vehicules, son job, etc.

Normalement, pour faire ca, tu dois ecrire du **SQL** a la main. Ca ressemble a ca :

```lua
-- Sans ORM : tu ecris le SQL toi-meme 😩
MySQL.prepare("SELECT * FROM users WHERE identifier = ?", { identifier }, function(result)
    -- ...
end)

MySQL.prepare("UPDATE users SET money = ? WHERE identifier = ?", { 1000, identifier }, function()
    -- ...
end)
```

C'est long, repetitif, et facile de faire des erreurs.

**OrvexORM** te permet de faire la meme chose, mais de maniere beaucoup plus simple :

```lua
-- Avec OrvexORM : c'est propre et lisible 😎
local player = User.find({ identifier = "license:abc" })
player:update({ money = 1000 })
```

**C'est tout.** Pas besoin d'ecrire du SQL. OrvexORM le genere automatiquement pour toi.

---

## Pourquoi utiliser OrvexORM ?

| Sans ORM | Avec OrvexORM |
|---|---|
| Tu ecris du SQL a la main | Le SQL est genere automatiquement |
| Risque de fautes dans les requetes | Impossible de se tromper |
| Code long et difficile a lire | Code court et clair |
| Pas de validation des donnees | Les types sont verifies automatiquement |
| Difficile a maintenir | Facile a faire evoluer |

---

## Comment ca marche en 30 secondes ?

**Etape 1** : Tu definis un "modele" (une representation de ta table SQL) :

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
})
```

**Etape 2** : Tu utilises ce modele pour interagir avec la base de donnees (dans un event, une commande ou un `CreateThread` : chaque appel attend la reponse de MySQL) :

```lua
-- Creer un joueur
User.create({ identifier = "license:abc", money = 500, job = "unemployed" })

-- Chercher un joueur
local player = User.find({ identifier = "license:abc" })

-- Modifier son argent
player:update({ money = 1000 })

-- Supprimer le joueur
player:delete()
```

C'est aussi simple que ca. Pas de SQL, pas de callbacks compliques.

---

## Pre-requis

Pour utiliser OrvexORM, tu as besoin de :

- Un serveur **FiveM** qui fonctionne
- **[oxmysql](https://github.com/overextended/oxmysql)** ou **[mysql-async](https://github.com/brouznouf/fivem-mysql-async)** installe et configure
- Une base de donnees **MySQL** ou **MariaDB** connectee a ton serveur

OrvexORM utilise oxmysql s'il est demarre, sinon mysql-async (3.3+ pour les transactions), sans configuration. Passe a la page [Installation](/docs/installation).
