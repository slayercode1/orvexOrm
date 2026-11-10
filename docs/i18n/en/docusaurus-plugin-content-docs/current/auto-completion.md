---
sidebar_position: 4
slug: /auto-completion
---

# Auto-completion (IDE)

OrvexORM ships with **LuaLS annotations** (Lua Language Server): the source files are annotated, and the definitions file `lib/types/orvexorm.d.lua` describes the public API LuaLS cannot work out by itself (model methods, which are assembled at runtime). Your IDE can therefore provide auto-completion, type-checking and inline documentation while you code.

Checked with LuaLS 3.19: a script that uses models, instances, the query builder, transactions and the cache produces no `undefined-field` warning.

---

## Configure VS Code

### 1. Install the Lua extension

Install the **Lua Language Server** (sumneko) extension:

- Search for **"Lua"** in VS Code extensions
- Install the one by **sumneko** (the most popular)

:::tip
The extension is officially called **"Lua"** by sumneko. Its ID is `sumneko.lua`.
:::

### 2. Configure `.luarc.json`

Create a `.luarc.json` file at the root of your resource:

```json title="your-resource/.luarc.json"
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

:::caution Adjust the path
The path `"../orvexorm"` depends on where your resource is relative to OrvexORM inside the `resources/` folder. If your structure is:

```
resources/
├── orvexorm/
└── my-resource/
```

Then `"../orvexorm"` is correct. Adjust according to your structure.

`OrvexORM`, `OrvexAdapter` and `OrvexCache` do not need to be listed in `globals`: LuaLS finds them in the library.
:::

### 3. Enjoy auto-completion

After configuring the file, you'll have access to:

**Auto-completion on `OrvexORM`** — all methods appear automatically:

```lua
OrvexORM.model()        -- Create a model
OrvexORM.transaction()  -- Create a transaction
OrvexORM.enableCache()  -- Enable cache
OrvexORM.migrate()      -- Run migrations
OrvexORM.introspect()   -- Introspect a table
OrvexORM.fromTable()    -- Generate a model from a table
OrvexORM.raw()          -- Raw SQL query
-- etc.
```

**Auto-completion on models** — `User.`, `Vehicle.`, etc. (declared in `lib/types/orvexorm.d.lua`):

```lua
User.create()          -- Create         → OrvexInstance
User.find()            -- Find one       → OrvexInstance|nil
User.findAll()         -- Find many      → OrvexInstance[]
User.update()          -- Update (data, where) → integer (affected rows)
User.delete()          -- Delete         → integer
User.query()           -- Query Builder  → OrvexBuilder
User.count()           -- Count          → integer
User.whereHas()        -- Filter by relation → OrvexBuilder
User.sync()            -- Create table
User.hook()            -- Add a hook
User.beforeCreate()    -- Shorthand hook (all 13 events are declared)
-- etc.: every method of the Model reference
```

The scopes you declare (`User.rich()`) are not listed, since their names are only known at runtime, but calling them is typed and returns an `OrvexBuilder`: the rest of the chain (`:where()`, `:get()`) is completed normally.

**Auto-completion on instances** — `player:`, `vehicle:`, etc.:

```lua
player:update()        -- Update this instance → integer
player:delete()        -- Delete
player:increment()     -- Increment a field
player:decrement()     -- Decrement a field
player:get()           -- Load a relation
player:attach()        -- Attach (many-to-many)
player:detach()        -- Detach
player:restore()       -- Restore (soft delete)
player:toTable()       -- Plain copy
player:getAttribute()  -- Read a column named like a method
-- etc.
```

Columns (`player.money`) are typed `any`: LuaLS does not know your schema.

**Transactions** — both forms of `OrvexORM.transaction` are declared (`---@overload`):

```lua
local tx = OrvexORM.transaction()                 -- OrvexTransaction: tx:insert(), tx:commit()...
local ok = OrvexORM.transaction(function(tx) end) -- boolean
```

**Inline documentation** — hover over any method to see its description, parameters, and types:

```lua
---@param tableName string      The MySQL table name
---@param fields table          The fields and their types
---@param opts? OrvexModelOpts  Options (primaryKey, softDelete, timestamps, hooks, scopes, relations, adapter, cache)
---@return OrvexModel
```

---

## Available types

OrvexORM defines the following types for LuaLS:

| Type | Description |
|---|---|
| `OrvexORM` | The main module |
| `OrvexModel` | A model (User, Vehicle, etc.) |
| `OrvexInstance` | An instance (a found player, a vehicle, etc.) |
| `OrvexBuilder` | The Query Builder |
| `OrvexTransaction` | A transaction |
| `OrvexSchemaBuilder` | The schema builder for migrations |
| `OrvexTableBuilder` | The column builder in migrations |
| `OrvexCache` | The cache system |
| `OrvexAdapter` | The database adapter |
| `OrvexFieldType` | `"string"` \| `"number"` \| `"boolean"` \| `"json"` \| `"auto"` \| `"date"` \| `"datetime"` \| `"timestamp"` |
| `OrvexModelOpts` | Model options (primaryKey, softDelete, timestamps, hooks, scopes, relations, adapter, cache) |
| `OrvexHookMap` | The inline hooks of `opts.hooks`, one typed field per event |
| `OrvexFindOpts` | Options of `find` / `findAll` / `all` (`select`, `include`) |
| `OrvexWhere` | A where clause: `{ column = value }` or `{ column = OrvexORM.op(operator, value) }` |
| `OrvexOpMarker` | An operator condition, created by `OrvexORM.op(operator, value)` |
| `OrvexPaginateResult` | Result of `:paginate()` (`data`, `total`, `page`, `perPage`, `lastPage`) |
| `OrvexRelationCount` | An entry of `countByRelation` (`instance`, `count`) |
| `OrvexCacheOpts` | Options of `OrvexCache.new` (`ttl`, `enabled`, `maxEntries`, `maxRows`, `sweepInterval`) |
| `OrvexCacheStats` | Result of `OrvexORM.cacheStats()` |
| `OrvexDriver` | The driver contract (`execute`, `scalar`, `transaction?`) for `OrvexAdapter.new` |
| `OrvexAdapterOptions` | Options of `OrvexAdapter.new(driver, opts?)` (`allowNonAtomicTransactions`) |
| `OrvexMigration` | Migration definition (name, up, down) |
| `OrvexRelationDef` | Relation definition |

---

## Other IDEs

### IntelliJ / Rider

Install the **EmmyLua** plugin and configure the workspace the same way.

### Neovim

If you use `nvim-lspconfig` with `lua_ls`:

```lua
require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            runtime = { version = "Lua 5.4" },
            workspace = {
                library = { "/path/to/resources/orvexorm" },
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

## Source distribution

OrvexORM is distributed as annotated source `.lua` files, with the definitions file `lib/types/orvexorm.d.lua` (a `---@meta` file, never loaded by FiveM). Just add the OrvexORM folder to `workspace.library` in your `.luarc.json`.
