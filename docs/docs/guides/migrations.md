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

-- Cree la table "users" si elle n'existe pas (dans un thread : sync() attend la base)
CreateThread(function()
    User.sync()
end)
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

Si la cle primaire n'est **pas declaree** dans `fields` (par exemple le `id` par defaut, que tu n'as pas liste), `sync()` l'ajoute en premiere colonne : `` `id` INT UNSIGNED NOT NULL AUTO_INCREMENT ``, la meme colonne que `t:id()`. Une cle primaire declaree est gardee telle quelle.

```lua
local Log = OrvexORM.model("logs", { message = "string" })  -- primaryKey = "id", non declaree
-- sync() cree : `id` INT UNSIGNED NOT NULL AUTO_INCREMENT, `message` VARCHAR(255), PRIMARY KEY (`id`)
```

Avec `timestamps = true`, `sync()` ajoute aussi `created_at` et `updated_at` ; avec `softDelete = true`, `deleted_at`.

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
CreateThread(function()
    local count = OrvexORM.migrate()
    print(count .. " migration(s) appliquee(s)")
end)
```

OrvexORM garde une trace des migrations deja appliquees dans une table `orvex_migrations`. Les migrations deja executees ne sont jamais rejouees.

### Quand une migration echoue

`migrate()` s'arrete a la **premiere** migration en echec et **leve une erreur** :

```
[OrvexORM] Migration of migration '003_create_roles' failed (2 migration(s) applied before it): <erreur MySQL>
```

- la migration en echec n'est **pas** enregistree dans `orvex_migrations` : elle sera retentee au prochain `migrate()` ;
- les migrations suivantes ne sont **pas** lancees ;
- les migrations precedentes du meme appel restent appliquees et enregistrees.

Une requete pour laquelle le driver retourne `nil` (oxmysql le fait sur une erreur SQL, sans lever d'erreur) compte comme un echec. Une erreur levee dans ta fonction `up` aussi.

Pour decider quoi faire au demarrage, capture l'erreur :

```lua
CreateThread(function()
    local ok, result = pcall(OrvexORM.migrate)
    if not ok then
        print("^1[Migrations] " .. tostring(result) .. "^0")
        return  -- ne demarre pas la suite du script
    end
    print(result .. " migration(s) appliquee(s)")
end)
```

:::caution MySQL ne peut pas annuler le DDL
`CREATE TABLE`, `ALTER TABLE` et `DROP TABLE` sont valides immediatement par MySQL, meme dans une transaction. Si une migration contient plusieurs requetes et que la troisieme echoue, les deux premieres **restent appliquees**. Corrige la base a la main (ou ecris un `up` idempotent, par exemple avec `dropIfExists`) avant de relancer. Ecrire une seule modification par migration limite le probleme.
:::

### Annuler les migrations

```lua
CreateThread(function()
    local count = OrvexORM.rollback()
    print(count .. " migration(s) annulee(s)")
end)
```

`rollback()` annule le **dernier lot** de migrations (le dernier `migrate()`), de la plus recente a la plus ancienne. Si un `down` echoue, sa migration **reste enregistree**, les suivantes ne sont pas annulees, et une erreur est levee, comme pour `migrate()`.

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

    -- Index et cles etrangeres (ADD INDEX / ADD CONSTRAINT)
    t:index("email")                         -- idx_email
    t:unique({ "email", "verified" })        -- uq_email_verified
    t:foreignKey("job_id", "jobs", "id", { onDelete = "SET NULL" })  -- fk_users_job_id
end)
```

Dans un meme appel a `table()`, les instructions `ALTER TABLE` sont generees dans cet ordre : ajouts de colonnes, suppressions, renommages, **puis** index, **puis** cles etrangeres. Un index ou une cle etrangere peut donc viser une colonne ajoutee ou renommee dans le meme appel. `t:id()` dans `table()` ajoute la colonne avec `AUTO_INCREMENT PRIMARY KEY`.

### Index et cles etrangeres

| Methode | Effet | Nom par defaut |
|---|---|---|
| `t:index(columns, name?)` | Index simple (`columns` : un nom ou un tableau) | `idx_<colonnes>` |
| `t:unique(columns, name?)` | Index unique | `uq_<colonnes>` |
| `t:foreignKey(column, refTable, refColumn, opts?)` | Cle etrangere ; `opts.onDelete` / `opts.onUpdate` parmi `CASCADE` (defaut), `RESTRICT`, `SET NULL`, `NO ACTION`, `SET DEFAULT` | `fk_<table>_<colonne>` |
| `t:enum(name, values)` | Colonne `ENUM(...)` | — |
| `t:timestamps()` | `created_at` et `updated_at` (`DATETIME`, remplis par MySQL) | — |
| `t:softDeletes()` | `deleted_at` (`DATETIME NULL`) | — |

Ils fonctionnent dans `schema:create()` comme dans `schema:table()`.

### Ordre d'execution

Chaque appel au schema builder (`create`, `table`, `drop`, `dropIfExists`, `raw`) ajoute ses requetes **dans l'ordre ou tu l'appelles**, et plusieurs appels a `table()` dans la meme migration s'additionnent :

```lua
up = function(schema)
    schema:create("jobs", function(t) t:id() t:string("label") end)
    schema:table("users", function(t) t:integer("job_id") end)
    schema:table("users", function(t)
        t:foreignKey("job_id", "jobs", "id")  -- jobs existe deja : creee juste avant
    end)
    schema:raw("INSERT INTO jobs (label) VALUES ('unemployed')")
end
```

`t:renameColumn` genere `RENAME COLUMN`, qui demande MySQL 8.0+ ou MariaDB 10.5+.

`schema:toSQL()` retourne une copie de la liste des requetes, utile pour verifier une migration sans l'executer.

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
CreateThread(function()
    OrvexORM.migrate()
end)
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

CreateThread(function()
    OrvexORM.migrate() -- Seule la migration 004 est executee
end)
```

## Comment ca marche en interne

1. OrvexORM cree une table `orvex_migrations` pour suivre les migrations appliquees
2. Quand tu appelles `OrvexORM.migrate()`, il compare tes migrations avec celles deja appliquees
3. Les nouvelles migrations sont executees dans l'ordre ; chaque requete de leur `up` est envoyee dans l'ordre d'appel
4. Une migration n'est enregistree qu'apres le succes de toutes ses requetes ; au premier echec, `migrate()` leve une erreur
5. Chaque lot de migrations recoit un numero de "batch" (utile pour le rollback)
6. `OrvexORM.rollback()` annule uniquement le dernier batch

:::caution En production
Les migrations modifient la structure de ta base de donnees. Fais toujours un **backup** avant d'appliquer des migrations en production. Et teste tes migrations sur un serveur de developpement d'abord !
:::
