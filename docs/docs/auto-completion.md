---
sidebar_position: 4
slug: /auto-completion
---

# Auto-completion (IDE)

OrvexORM est livre avec des **annotations LuaLS** (Lua Language Server) : les fichiers source sont annotes, et le fichier de definitions `lib/types/orvexorm.d.lua` decrit l'API publique que LuaLS ne peut pas deviner seul (les methodes des modeles, qui sont assemblees a l'execution). Ton IDE peut donc te proposer l'auto-completion, verifier les types et afficher la doc inline pendant que tu codes.

Verifie avec LuaLS 3.19 : un script qui utilise les modeles, les instances, le query builder, les transactions et le cache ne produit aucun avertissement `undefined-field`.

---

## Configurer VS Code

### 1. Installer l'extension Lua

Installe l'extension **Lua Language Server** (sumneko) :

- Cherche **"Lua"** dans les extensions VS Code
- Installe celle de **sumneko** (la plus populaire)

:::tip
L'extension s'appelle officiellement **"Lua"** par sumneko. Son ID est `sumneko.lua`.
:::

### 2. Configurer `.luarc.json`

Cree un fichier `.luarc.json` a la racine de ta ressource :

```json title="ta-ressource/.luarc.json"
{
    "runtime": {
        "version": "Lua 5.4"
    },
    "workspace": {
        "library": [
            "../orvexorm"
        ],
        "checkThirdParty": false
    },
    "diagnostics": {
        "globals": [
            "MySQL", "Citizen", "CreateThread", "Wait", "promise", "json", "exports",
            "source", "AddEventHandler", "RegisterNetEvent", "RegisterCommand",
            "TriggerClientEvent", "TriggerEvent", "GetPlayerIdentifierByType"
        ]
    },
    "completion": {
        "callSnippet": "Replace",
        "keywordSnippet": "Replace"
    }
}
```

:::caution Adapter le chemin
Le chemin `"../orvexorm"` depend de l'emplacement de ta ressource par rapport a OrvexORM dans le dossier `resources/`. Si ta structure est :

```
resources/
├── orvexorm/
└── ma-ressource/
```

Alors `"../orvexorm"` est correct. Adapte selon ta structure.

`OrvexORM`, `OrvexAdapter` et `OrvexCache` n'ont pas besoin d'etre declares dans `globals` : LuaLS les trouve dans la librairie.
:::

### 3. Profiter de l'auto-completion

Apres avoir configure le fichier, tu auras acces a :

**Auto-completion sur `OrvexORM`** — toutes les methodes apparaissent automatiquement :

```lua
OrvexORM.model()        -- Creer un modele
OrvexORM.transaction()  -- Creer une transaction
OrvexORM.enableCache()  -- Activer le cache
OrvexORM.migrate()      -- Lancer les migrations
OrvexORM.introspect()   -- Introspecter une table
OrvexORM.fromTable()    -- Generer un modele depuis une table
OrvexORM.raw()          -- Requete SQL brute
-- etc.
```

**Auto-completion sur les modeles** — `User.`, `Vehicle.`, etc. (declarees dans `lib/types/orvexorm.d.lua`) :

```lua
User.create()          -- Creer           → OrvexInstance
User.find()            -- Trouver un seul → OrvexInstance|nil
User.findAll()         -- Trouver plusieurs → OrvexInstance[]
User.update()          -- Modifier (data, where) → integer (lignes touchees)
User.delete()          -- Supprimer       → integer
User.query()           -- Query Builder   → OrvexBuilder
User.count()           -- Compter         → integer
User.whereHas()        -- Filtrer par relation → OrvexBuilder
User.sync()            -- Creer la table
User.hook()            -- Ajouter un hook
User.beforeCreate()    -- Hook raccourci (les 13 evenements sont declares)
-- etc. : toutes les methodes de la reference Model
```

Les scopes que tu declares (`User.rich()`) n'apparaissent pas dans la liste, car leurs noms ne sont connus qu'a l'execution, mais leur appel est type et retourne un `OrvexBuilder` : la suite de la chaine (`:where()`, `:get()`) est completee normalement.

**Auto-completion sur les instances** — `player:`, `vehicle:`, etc. :

```lua
player:update()        -- Modifier cette instance → integer
player:delete()        -- Supprimer
player:increment()     -- Incrementer un champ
player:decrement()     -- Decrementer un champ
player:get()           -- Charger une relation
player:attach()        -- Attacher (many-to-many)
player:detach()        -- Detacher
player:restore()       -- Restaurer (soft delete)
player:toTable()       -- Copie plate
player:getAttribute()  -- Lire une colonne nommee comme une methode
-- etc.
```

Les colonnes (`player.money`) sont typees `any` : LuaLS ne connait pas ton schema.

**Transactions** — les deux formes de `OrvexORM.transaction` sont declarees (`---@overload`) :

```lua
local tx = OrvexORM.transaction()                 -- OrvexTransaction : tx:insert(), tx:commit()...
local ok = OrvexORM.transaction(function(tx) end) -- boolean
```

**Documentation inline** — survole n'importe quelle methode pour voir sa description, ses parametres, et ses types :

```lua
---@param tableName string      Le nom de la table MySQL
---@param fields table          Les champs et leurs types
---@param opts? OrvexModelOpts  Options (primaryKey, softDelete, timestamps, hooks, scopes, relations, adapter, cache)
---@return OrvexModel
```

---

## Types disponibles

OrvexORM definit les types suivants pour LuaLS :

| Type | Description |
|---|---|
| `OrvexORM` | Le module principal |
| `OrvexModel` | Un modele (User, Vehicle, etc.) |
| `OrvexInstance` | Une instance (un joueur trouve, un vehicule, etc.) |
| `OrvexBuilder` | Le Query Builder |
| `OrvexTransaction` | Une transaction |
| `OrvexSchemaBuilder` | Le schema builder pour les migrations |
| `OrvexTableBuilder` | Le builder de colonnes dans les migrations |
| `OrvexCache` | Le systeme de cache |
| `OrvexAdapter` | L'adaptateur de base de donnees |
| `OrvexFieldType` | `"string"` \| `"number"` \| `"boolean"` \| `"json"` \| `"auto"` \| `"date"` \| `"datetime"` \| `"timestamp"` |
| `OrvexModelOpts` | Options du modele (primaryKey, softDelete, timestamps, hooks, scopes, relations, adapter, cache) |
| `OrvexHookMap` | Les hooks inline de `opts.hooks`, un champ type par evenement |
| `OrvexFindOpts` | Options de `find` / `findAll` / `all` (`select`, `include`) |
| `OrvexWhere` | Une clause where : `{ colonne = valeur }` ou `{ colonne = { operateur, valeur } }` |
| `OrvexPaginateResult` | Retour de `:paginate()` (`data`, `total`, `page`, `perPage`, `lastPage`) |
| `OrvexRelationCount` | Une entree de `countByRelation` (`instance`, `count`) |
| `OrvexCacheOpts` | Options de `OrvexCache.new` (`ttl`, `enabled`, `maxEntries`, `sweepInterval`) |
| `OrvexCacheStats` | Retour de `OrvexORM.cacheStats()` |
| `OrvexDriver` | Le contrat d'un driver (`execute`, `scalar`, `transaction?`) pour `OrvexAdapter.new` |
| `OrvexMigration` | Definition d'une migration (name, up, down) |
| `OrvexRelationDef` | Definition d'une relation |

---

## Autres IDE

### IntelliJ / Rider

Installe le plugin **EmmyLua** et configure le workspace de la meme maniere.

### Neovim

Si tu utilises `nvim-lspconfig` avec `lua_ls` :

```lua
require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            runtime = { version = "Lua 5.4" },
            workspace = {
                library = { "/chemin/vers/resources/orvexorm" },
                checkThirdParty = false,
            },
            diagnostics = {
                globals = { "MySQL", "Citizen", "CreateThread", "Wait", "promise", "json", "exports", "source" },
            },
        },
    },
})
```

---

## Distribution source

OrvexORM est distribue sous forme de fichiers source `.lua` annotes, avec le fichier de definitions `lib/types/orvexorm.d.lua` (un fichier `---@meta`, jamais charge par FiveM). Il suffit d'ajouter le dossier OrvexORM dans `workspace.library` de ton `.luarc.json`.
