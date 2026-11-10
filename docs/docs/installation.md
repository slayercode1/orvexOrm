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
OrvexORM choisit le driver MySQL tout seul, au premier appel. Le detail est dans [Driver MySQL](#driver-mysql).
:::

---

## Methode 1 : GitHub Release (recommandee)

1. Telecharge la derniere release sur [GitHub Releases](https://github.com/slayercode1/orvexOrm/releases)
2. Extrait le dossier `orvexorm` dans ton dossier `resources/`
3. C'est tout !

```
ton-serveur/
└── resources/
    └── orvexorm/
        ├── core/*.lua
        ├── database/*.lua
        ├── utils/*.lua
        ├── lib/*.lua
        └── fxmanifest.lua
```

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
Ta librairie MySQL (`oxmysql` ou `mysql-async`) doit **toujours** etre demarree avant `orvexorm` : la detection a lieu au premier appel, et si aucune des deux ne tourne, l'appel echoue avec `No MySQL library found. Ensure oxmysql or mysql-async is started before orvexorm.`
:::

## Driver MySQL

Au premier appel, OrvexORM essaie, dans cet ordre (le premier trouve gagne) :

| Ordre | Condition | Mode | Fonctions utilisees |
|---|---|---|---|
| 1 | Global `MySQL` d'oxmysql (`@oxmysql/lib/MySQL.lua` charge **dans orvexorm**) | `oxmysql_global` | `MySQL.query.await`, `MySQL.insert.await`, `MySQL.update.await`, `MySQL.transaction.await` |
| 2 | Global `MySQL.Async` (`@mysql-async/lib/MySQL.lua` charge **dans orvexorm**) | `mysql-async` | `MySQL.Async.fetchAll`, `execute`, `insert`, `transaction` |
| 3 | Ressource `oxmysql` demarree | `oxmysql_export` | `exports.oxmysql:executeSync`, `insertSync`, `updateSync`, `transactionSync` |
| 4 | Ressource `mysql-async` demarree | `mysql-async` | `exports['mysql-async']:mysql_fetch_all`, `mysql_execute`, `mysql_insert`, `mysql_transaction` |

Avec le `fxmanifest.lua` livre, orvexorm ne charge aucun des deux fichiers `MySQL.lua` : ce sont donc les **exports** (lignes 3 et 4) qui servent. Si oxmysql et mysql-async sont demarres tous les deux, **oxmysql est choisi**. Les modes 1 et 2 ne s'activent que si tu ajoutes toi-meme `@oxmysql/lib/MySQL.lua` ou `@mysql-async/lib/MySQL.lua` aux `server_scripts` d'orvexorm.

Bon a savoir :

- Les lectures passent par `MySQL.query` / `executeSync` (protocole texte), pas par `MySQL.prepare`, qui aplatit les resultats d'une seule ligne et interprete une table de parametres comme un lot.
- En mode `oxmysql_global`, une erreur SQL leve une erreur Lua (la forme `.await` est utilisee). Avant, le thread pouvait rester bloque.
- **mysql-async 3.3 ou plus** est necessaire pour les transactions : OrvexORM utilise sa transaction native (`MySQL.Async.transaction`), seule facon atomique sous mysql-async. Sur une version plus ancienne, `commit()` leve `atomic transactions need mysql-async >= 3.3` sans rien envoyer.
- Sous mysql-async, les requetes qui commencent par `SELECT`, `SHOW`, `DESCRIBE` / `DESC`, `EXPLAIN` ou `WITH` (y compris un `(SELECT ...) UNION (SELECT ...)` entre parentheses) passent par `fetchAll` et retournent des lignes. Une lecture pour laquelle mysql-async ne retourne rien (`nil`, la requete a echoue) leve une erreur au lieu d'etre prise pour un resultat vide (et mise en cache comme tel).
- Sous mysql-async, une erreur SQL hors transaction peut ne jamais rappeler le callback (limite de mysql-async) : le thread attend alors indefiniment. Prefere oxmysql.
- Tous les appels **attendent** la base : voir [Async et threads](/docs/getting-started#async-et-threads).

## Utiliser dans ta ressource

Configure ta ressource pour utiliser OrvexORM :

```lua title="ta-ressource/fxmanifest.lua"
fx_version 'cerulean'
game 'common'

dependency 'orvexorm'
server_script '@orvexorm/lib/import.lua'   -- Charge OrvexORM, avant tes scripts

server_script 'server.lua'
```

```lua title="ta-ressource/server.lua"
-- OrvexORM est une table globale de ta ressource
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })
```

### Comment marche l'import

Chaque ressource FiveM a son propre etat Lua. `lib/import.lua` lit la liste des `server_script` du `fxmanifest.lua` d'orvexorm et execute ces fichiers **dans ta ressource**. Consequences :

- `OrvexORM` est une vraie table Lua chez toi : les instances (`player:update()`), les query builders (`User.query():where()`) et les transactions (`tx:insert()`) gardent leurs methodes. Toutes les fonctionnalites (migrations, schema builder, introspection, `OrvexAdapter`, `OrvexCache`) sont disponibles.
- **Chaque ressource a sa propre instance de l'ORM** : son cache, son `OrvexORM.debug()`, son `enableCache()` et son adaptateur. Activer le cache dans la ressource A ne l'active pas dans la ressource B, et une ecriture faite par B n'invalide pas le cache de A. Si plusieurs ressources ecrivent dans les memes tables, garde le cache desactive ou un TTL court.
- Importer deux fois ne recharge rien. Inclus cote client (`shared_script`), le fichier ne fait rien : l'ORM est serveur uniquement.
- Si la ressource `orvexorm` est absente, l'import echoue avec un message qui demande d'ajouter `dependency 'orvexorm'`.

:::danger N'utilise plus `exports.orvexorm:lib()`
L'export existe encore pour la compatibilite, mais les exports FiveM passent par msgpack, qui **supprime les metatables** : les lignes renvoyees par `find`/`findAll`, les builders de `User.query()` et le `tx` des transactions arrivent **sans leurs methodes** (`player:update` vaut `nil`). Le premier appel affiche un avertissement dans la console. Remplace-le par `server_script '@orvexorm/lib/import.lua'`.
:::

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

Tu as **4 options** :

### Option A : `sync()` — Creation automatique

La plus simple. Definis ton modele et appelle `.sync()` :

```lua
local User = OrvexORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

CreateThread(function()
    User.sync() -- Cree la table si elle n'existe pas
end)
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

CreateThread(function()
    OrvexORM.migrate()
end)
```

Voir le guide complet : [Migrations](/docs/guides/migrations)

### Option C : Introspection — Table existante

Si ta table existe deja, OrvexORM peut la detecter automatiquement :

```lua
CreateThread(function()
    -- Genere le modele depuis la table MySQL existante (lance un DESCRIBE)
    local User = OrvexORM.fromTable("users")

    -- Ou recupere juste les champs
    local fields, pk = OrvexORM.introspect("users")
end)
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
    local ORM = OrvexORM  -- charge par @orvexorm/lib/import.lua
    ORM.debug(true)  -- Active les logs SQL

    local User = ORM.model("users", {
        identifier = "string",
        money      = "number",
    }, { primaryKey = "identifier" })

    User.sync()
    print("^2[OrvexORM] Installation OK !^0")
end)
```

Tu devrais voir dans la console (la premiere ligne vient de la ressource `orvexorm` elle-meme, au demarrage) :
```
[OrvexORM] v1.3.0 loaded — ready to use
[OrvexORM] Installation OK !
```

Passe a la page [Premier pas](/docs/getting-started).
