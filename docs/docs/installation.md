---
sidebar_position: 2
slug: /installation
---

# Installation

## Prerequis

- Un serveur **FiveM** fonctionnel
- **oxmysql** ou **mysql-async** installe et configure (l'un des deux suffit)
- Une base de donnees **MySQL** ou **MariaDB**

:::info Compatibilite
OrvexORM detecte automatiquement quelle librairie MySQL est installee sur ton serveur. Tu n'as rien a configurer — ca marche avec les deux.
:::

---

## Methode 1 : CLI (recommandee)

Installe OrvexORM en une seule commande depuis la racine de ton serveur FiveM :

```bash
npx orvexorm install
```

C'est tout. Le CLI detecte automatiquement ton dossier `resources/` et y installe OrvexORM sous forme **compilee** (bytecode `.luac`). Le code source n'est pas inclus.

:::tip Commandes disponibles
```bash
npx orvexorm install              # Installe OrvexORM (compile .luac)
npx orvexorm update               # Met a jour OrvexORM
npx orvexorm init ma-ressource    # Cree une ressource pre-configuree
npx orvexorm help                 # Aide
```
:::

---

## Methode 2 : Telecharger manuellement

Telecharge la derniere release et place le dossier dans `resources/` :

```
ton-serveur/
└── resources/
    └── orvexorm/
        ├── core/*.luac
        ├── database/*.luac
        ├── utils/*.luac
        ├── lib/
        └── fxmanifest.lua
```

:::info Distribution compilee
La release contient des fichiers `.luac` (bytecode Lua 5.4). C'est le format recommande — leger, rapide, et le code source n'est pas lisible.
:::

---

## Demarrer la ressource

```cfg title="server.cfg"
# Avec oxmysql :
ensure oxmysql
ensure orvexorm

# OU avec mysql-async :
ensure mysql-async
ensure orvexorm
```

:::caution Important
Ta librairie MySQL (`oxmysql` ou `mysql-async`) doit **toujours** etre demarree avant `orvexorm`.
:::

## Utiliser dans ta ressource

Tu peux aussi generer une ressource pre-configuree avec le CLI :

```bash
npx orvexorm init ma-ressource
```

Ou configurer manuellement :

**Option A : Import direct (recommandee)**

```lua title="ta-ressource/fxmanifest.lua"
fx_version 'cerulean'
game 'common'

dependency 'orvexorm'

server_scripts {
    '@orvexorm/lib/import.lua',   -- Charge OrvexORM
    'server.lua',
}
```

```lua title="ta-ressource/server.lua"
-- OrvexORM est disponible globalement
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

**Option B : Via exports**

```lua title="ta-ressource/server.lua"
local ORM = exports.orvexorm:lib()

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })
```

---

## Configuration de la base de donnees

Si ce n'est pas deja fait, configure la connexion dans ton `server.cfg` :

```cfg title="server.cfg"
set mysql_connection_string "mysql://user:password@localhost/nom_de_ta_base?charset=utf8mb4"
```

Remplace :
- `user` par ton nom d'utilisateur MySQL
- `password` par ton mot de passe
- `nom_de_ta_base` par le nom de ta base de donnees

---

## Creer tes tables

Tu as **3 options** :

### Option A : `sync()` — Creation automatique

La plus simple. Definis ton modele et appelle `.sync()` :

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

User.sync() -- Cree la table si elle n'existe pas
```

### Option B : Migrations

Pour un projet serieux, utilise les **migrations** :

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
})

OrvexORM.migrate()
```

Voir le guide complet : [Migrations](/docs/guides/migrations)

### Option C : Introspection — Table existante

Si ta table existe deja, OrvexORM peut la detecter automatiquement :

```lua
-- Genere le modele depuis la table MySQL existante
local User = OrvexORM.fromTable("users")

-- Ou recupere juste les champs
local fields, pk = OrvexORM.introspect("users")
```

### Option D : SQL a la main

```sql
CREATE TABLE IF NOT EXISTS `users` (
    `identifier` VARCHAR(60) NOT NULL,
    `money` INT NOT NULL DEFAULT 0,
    `job` VARCHAR(50) NOT NULL DEFAULT 'unemployed',
    PRIMARY KEY (`identifier`)
);
```

:::tip Astuce
Tu peux utiliser **HeidiSQL**, **phpMyAdmin**, ou **DBeaver** pour creer tes tables visuellement.
:::

---

## Verifier l'installation

Ajoute ce code dans ta ressource pour verifier que tout fonctionne :

```lua
Citizen.CreateThread(function()
    local ORM = OrvexORM or exports.orvexorm:lib()
    ORM.debug(true)  -- Active les logs SQL

    local User = ORM.model("users", {
        identifier = "string",
        money      = "number",
    }, { primaryKey = "identifier" })

    User.sync()
    print("^2[OrvexORM] Installation OK !^0")
end)
```

Tu devrais voir dans la console :
```
[OrvexORM] v1.0.0 loaded — ready to use
[OrvexORM] Installation OK !
```

Passe a la page [Premier pas](/docs/getting-started).
