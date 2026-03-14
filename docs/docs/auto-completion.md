---
sidebar_position: 4
slug: /auto-completion
---

# Auto-completion (IDE)

OrvexORM inclut des **annotations LuaLS** completes dans tout le code source. Ca veut dire que ton IDE peut te proposer de l'auto-completion, du type-checking, et de la doc inline pendant que tu codes.

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
        "globals": ["MySQL", "Citizen", "promise", "json", "OrvexORM"]
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

**Auto-completion sur les modeles** — `User.`, `Vehicle.`, etc. :

```lua
User.create()          -- Creer
User.find()            -- Trouver un seul
User.findAll()         -- Trouver plusieurs
User.update()          -- Modifier
User.delete()          -- Supprimer
User.query()           -- Query Builder
User.count()           -- Compter
User.sync()            -- Creer la table
User.hook()            -- Ajouter un hook
User.beforeCreate()    -- Hook raccourci
-- etc.
```

**Auto-completion sur les instances** — `player:`, `vehicle:`, etc. :

```lua
player:update()        -- Modifier cette instance
player:delete()        -- Supprimer
player:increment()     -- Incrementer un champ
player:decrement()     -- Decrementer un champ
player:get()           -- Charger une relation
player:attach()        -- Attacher (many-to-many)
player:detach()        -- Detacher
player:restore()       -- Restaurer (soft delete)
-- etc.
```

**Documentation inline** — survole n'importe quelle methode pour voir sa description, ses parametres, et ses types :

```lua
---@param tableName string      Le nom de la table MySQL
---@param fields table          Les champs et leurs types
---@param opts? OrvexModelOpts  Options (primaryKey, softDelete, timestamps...)
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
| `OrvexFieldType` | `"string"` \| `"number"` \| `"boolean"` \| `"json"` \| `"auto"` |
| `OrvexModelOpts` | Options du modele (primaryKey, softDelete, timestamps) |
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
                globals = { "MySQL", "Citizen", "promise", "json", "OrvexORM" },
            },
        },
    },
})
```

---

## Si tu utilises le code source

Si tu as installe OrvexORM avec `--source` ou que tu as le code source directement, l'auto-completion fonctionne nativement car LuaLS lit les annotations dans les fichiers `.lua`.

:::info Version compilee (.luac)
Les fichiers `.luac` (bytecode) ne contiennent pas les annotations. Pour l'auto-completion avec la version compilee, tu dois ajouter le dossier du **code source** d'OrvexORM dans `workspace.library` de ton `.luarc.json`, meme si tu utilises la version compilee en production.
:::
