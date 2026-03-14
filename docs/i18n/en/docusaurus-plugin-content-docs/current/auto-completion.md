---
sidebar_position: 4
slug: /auto-completion
---

# Auto-completion (IDE)

OrvexORM includes complete **LuaLS annotations** throughout the source code. This means your IDE can provide auto-completion, type-checking, and inline documentation while you code.

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
        "globals": ["MySQL", "Citizen", "promise", "json", "OrvexORM"]
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

**Auto-completion on models** — `User.`, `Vehicle.`, etc.:

```lua
User.create()          -- Create
User.find()            -- Find one
User.findAll()         -- Find many
User.update()          -- Update
User.delete()          -- Delete
User.query()           -- Query Builder
User.count()           -- Count
User.sync()            -- Create table
User.hook()            -- Add a hook
User.beforeCreate()    -- Shorthand hook
-- etc.
```

**Auto-completion on instances** — `player:`, `vehicle:`, etc.:

```lua
player:update()        -- Update this instance
player:delete()        -- Delete
player:increment()     -- Increment a field
player:decrement()     -- Decrement a field
player:get()           -- Load a relation
player:attach()        -- Attach (many-to-many)
player:detach()        -- Detach
player:restore()       -- Restore (soft delete)
-- etc.
```

**Inline documentation** — hover over any method to see its description, parameters, and types:

```lua
---@param tableName string      The MySQL table name
---@param fields table          The fields and their types
---@param opts? OrvexModelOpts  Options (primaryKey, softDelete, timestamps...)
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
| `OrvexFieldType` | `"string"` \| `"number"` \| `"boolean"` \| `"json"` \| `"auto"` |
| `OrvexModelOpts` | Model options (primaryKey, softDelete, timestamps) |
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
                globals = { "MySQL", "Citizen", "promise", "json", "OrvexORM" },
            },
        },
    },
})
```

---

## If you use the source code

If you installed OrvexORM with `--source` or have the source code directly, auto-completion works natively because LuaLS reads the annotations in `.lua` files.

:::info Compiled version (.luac)
`.luac` files (bytecode) don't contain annotations. For auto-completion with the compiled version, you need to add the OrvexORM **source code** folder to `workspace.library` in your `.luarc.json`, even if you use the compiled version in production.
:::
