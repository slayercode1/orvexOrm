---
sidebar_position: 10
---

# Migrations & creation de tables

OrvexORM peut **creer tes tables automatiquement** a partir de tes modeles, ou te permettre d'ecrire des **migrations** pour gerer l'evolution de ta base de donnees au fil du temps.

## Creation rapide avec `sync()`

La methode la plus simple : tu definis ton modele et tu appelles `.sync()`. La table est creee automatiquement si elle n'existe pas.

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- Cree la table "users" si elle n'existe pas
User.sync()
```

:::tip Quand utiliser sync() ?
`sync()` est parfait pour le **developpement** et les **premiers tests**. Il cree la table si elle n'existe pas, mais ne la modifie pas si elle existe deja. Pour des modifications de structure, utilise les **migrations**.
:::

### Correspondance des types

Quand tu utilises `sync()`, OrvexORM convertit tes types de schema en types MySQL :

| Type OrvexORM | Type MySQL |
|---|---|
| `"string"` | `VARCHAR(255)` |
| `"number"` | `INT` |
| `"boolean"` | `TINYINT(1)` |
| `"json"` | `JSON` |
| `"date"` | `DATE` |
| `"datetime"` | `DATETIME` |
| `"timestamp"` | `TIMESTAMP` |
| `"auto"` | `TEXT` |

La **cle primaire** est automatiquement configuree comme `NOT NULL`. Si c'est un champ `"number"`, il est aussi `AUTO_INCREMENT`.

## Migrations

Les migrations te permettent de versionner les changements de ta base de donnees. Chaque migration a un nom unique, une fonction `up` (appliquer) et une fonction `down` (annuler).

### Definir des migrations

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
                t:json("position")
                t:timestamp("created_at")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
    {
        name = "002_create_vehicles",
        up = function(schema)
            schema:create("vehicles", function(t)
                t:id()
                t:string("owner", 60)
                t:string("plate", 10)
                t:string("model")
                t:integer("fuel")
                t:json("mods")
            end)
        end,
        down = function(schema)
            schema:drop("vehicles")
        end,
    },
})
```

### Appliquer les migrations

```lua
local count = OrvexORM.migrate()
print(count .. " migration(s) appliquee(s)")
```

OrvexORM garde une trace des migrations deja appliquees dans une table `orvex_migrations`. Les migrations deja executees ne sont jamais rejouees.

### Annuler les migrations

```lua
local count = OrvexORM.rollback()
print(count .. " migration(s) annulee(s)")
```

`rollback()` annule le **dernier lot** de migrations (le dernier `migrate()`).

## Le Schema Builder

Dans les migrations, tu as acces a un **Schema Builder** pour definir tes tables de maniere lisible.

### Creer une table

```lua
schema:create("players", function(t)
    t:id()                        -- INT UNSIGNED NOT NULL AUTO_INCREMENT (PK)
    t:string("name", 100)         -- VARCHAR(100)
    t:integer("money")            -- INT
    t:bigInteger("experience")    -- BIGINT
    t:float("rating")             -- FLOAT
    t:double("coordinates")       -- DOUBLE
    t:boolean("vip")              -- TINYINT(1)
    t:text("bio")                 -- TEXT
    t:json("inventory")           -- JSON
    t:date("birth_date")          -- DATE
    t:datetime("last_login")      -- DATETIME
    t:timestamp("created_at")     -- TIMESTAMP
end)
```

### Types de colonnes disponibles

| Methode | Type MySQL | Description |
|---|---|---|
| `t:id(name?)` | `INT UNSIGNED AUTO_INCREMENT` | Cle primaire auto-increment (defaut: `"id"`) |
| `t:primaryString(name, length?)` | `VARCHAR(n) NOT NULL` | Cle primaire texte (defaut: 60 caracteres) |
| `t:string(name, length?)` | `VARCHAR(n)` | Texte (defaut: 255 caracteres) |
| `t:integer(name)` | `INT` | Nombre entier |
| `t:bigInteger(name)` | `BIGINT` | Grand nombre entier |
| `t:float(name)` | `FLOAT` | Nombre decimal (simple precision) |
| `t:double(name)` | `DOUBLE` | Nombre decimal (double precision) |
| `t:boolean(name)` | `TINYINT(1)` | Vrai/faux |
| `t:text(name)` | `TEXT` | Texte long |
| `t:json(name)` | `JSON` | Donnees JSON |
| `t:date(name)` | `DATE` | Date seule |
| `t:datetime(name)` | `DATETIME` | Date et heure |
| `t:timestamp(name)` | `TIMESTAMP` | Horodatage (auto `CURRENT_TIMESTAMP`) |

### Supprimer une table

```lua
schema:drop("old_table")

-- Ou en mode "safe" (ne fait rien si la table n'existe pas)
schema:dropIfExists("maybe_table")
```

### Modifier une table existante

```lua
schema:table("users", function(t)
    -- Ajouter des colonnes
    t:string("email", 255)
    t:boolean("verified")

    -- Supprimer une colonne
    t:dropColumn("old_column")

    -- Renommer une colonne
    t:renameColumn("name", "full_name")
end)
```

### SQL brut

Si tu as besoin d'une operation speciale, tu peux ajouter du SQL brut :

```lua
schema:raw("ALTER TABLE users ADD INDEX idx_job (job)")
```

## Exemples complets

### Serveur FiveM typique

```lua
OrvexORM.migrations({
    {
        name = "001_create_users",
        up = function(schema)
            schema:create("users", function(t)
                t:primaryString("identifier", 60)
                t:integer("money")
                t:string("job")
                t:json("position")
                t:json("inventory")
                t:timestamp("created_at")
            end)
        end,
        down = function(schema)
            schema:drop("users")
        end,
    },
    {
        name = "002_create_vehicles",
        up = function(schema)
            schema:create("vehicles", function(t)
                t:id()
                t:string("owner", 60)
                t:string("plate", 10)
                t:string("model")
                t:integer("fuel")
                t:json("mods")
            end)
        end,
        down = function(schema)
            schema:drop("vehicles")
        end,
    },
    {
        name = "003_create_roles",
        up = function(schema)
            schema:create("roles", function(t)
                t:id()
                t:string("name", 50)
            end)
            schema:create("user_roles", function(t)
                t:id()
                t:string("user_id", 60)
                t:integer("role_id")
            end)
        end,
        down = function(schema)
            schema:drop("user_roles")
            schema:drop("roles")
        end,
    },
})

-- Au demarrage du serveur
OrvexORM.migrate()
```

### Ajouter une colonne plus tard

```lua
OrvexORM.migrations({
    -- ... migrations precedentes ...
    {
        name = "004_add_email_to_users",
        up = function(schema)
            schema:table("users", function(t)
                t:string("email", 255)
            end)
        end,
        down = function(schema)
            schema:table("users", function(t)
                t:dropColumn("email")
            end)
        end,
    },
})

OrvexORM.migrate() -- Seule la migration 004 est executee
```

## Comment ca marche en interne

1. OrvexORM cree une table `orvex_migrations` pour suivre les migrations appliquees
2. Quand tu appelles `OrvexORM.migrate()`, il compare tes migrations avec celles deja appliquees
3. Les nouvelles migrations sont executees dans l'ordre
4. Chaque lot de migrations recoit un numero de "batch" (utile pour le rollback)
5. `OrvexORM.rollback()` annule uniquement le dernier batch

:::caution En production
Les migrations modifient la structure de ta base de donnees. Fais toujours un **backup** avant d'appliquer des migrations en production. Et teste tes migrations sur un serveur de developpement d'abord !
:::
