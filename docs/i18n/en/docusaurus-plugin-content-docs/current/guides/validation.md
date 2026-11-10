---
sidebar_position: 6
---

# Validation

OrvexORM automatically checks that the data you send matches the types you defined in your schema. This prevents storing incorrect data in your database.

## How does it work?

When you define a model, you declare the types for each column:

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
})
```

Every time you use `create`, `update`, or `upsert`, OrvexORM checks two things:

1. every key of your data is a **known column** of the model;
2. every value has the **declared type**.

### Example: this works

```lua
-- OK: identifier is a string, money is a number
User.create({
    identifier = "license:abc",
    money      = 500,
    job        = "police",
})
```

### Example: this fails

```lua
-- ERROR: money should be a number, not a string
User.create({
    identifier = "license:abc",
    money      = "a lot",   -- ❌ string instead of number
    job        = "police",
})
-- Error: Field 'money': expected number, got string
```

## Checked types

| Declared type | Expected Lua type | Valid examples |
|---|---|---|
| `"string"` | `string` | `"hello"`, `"license:abc"` |
| `"number"` | `number` | `500`, `3.14`, `0` |
| `"boolean"` | `boolean` | `true`, `false` |
| `"json"` | `table` | `{ x = 1 }`, `{ "a", "b" }` |
| `"date"` | `string` | `"2024-03-15"` |
| `"datetime"` | `string` | `"2024-03-15 14:30:00"` |
| `"timestamp"` | `string` | `"2024-03-15 14:30:00"` |
| `"auto"` | any | a table is encoded as JSON, anything else is written as is |

The date format is not checked, only the Lua type (`string`) is. MySQL will reject a malformed date.

## Unknown columns

A key that is **not in the model's schema** is rejected, even if the column exists in the MySQL table:

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
})

User.create({ identifier = "license:abc", money = 500, bank = 1000 })
-- Error: Unknown field 'bank'
```

This is a safeguard: a typo (`mony = 500`) or a field coming from the client never silently ends up in SQL. Declare every column you write.

### Columns managed by the ORM

The columns the ORM fills itself are **accepted automatically** when the matching option is on, even if you don't declare them:

| Option | Columns accepted without declaration |
|---|---|
| `timestamps = true` | `created_at`, `updated_at` |
| `softDelete = true` | `deleted_at` |

They are typed `"datetime"` (a `"YYYY-MM-DD HH:MM:SS"` string, in UTC when the ORM fills it). So you can set `created_at` during an import, or change it in a hook:

```lua
local User = ORM.model("users", { identifier = "string" }, { timestamps = true })

User.create({ identifier = "license:abc", created_at = "2024-01-01 00:00:00" })  -- OK

User.beforeCreate(function(data)
    data.updated_at = "2024-01-01 00:00:00"  -- OK too
end)
```

Without the option, these columns are ordinary columns: they must be declared. If you declare them yourself, your type is kept.

:::caution Hooks are validated too
`before*` hooks run **before** validation: a column a hook adds must be declared (or be one of the managed columns above), otherwise the write fails with `Unknown field`.
:::

## Nil values are accepted

If you don't provide a value for a field, OrvexORM won't validate it. This allows for optional columns:

```lua
-- OK: job is not provided, no error
User.create({
    identifier = "license:abc",
    money      = 500,
    -- job is not specified → the database will use its default value
})
```

## When validation triggers

Validation is automatic on these methods:

| Method | Validation |
|---|---|
| `User.create(data)` | Yes |
| `User.createMany(rows)` | Yes (every row) |
| `User.createWith(data)` | Yes (parent and nested rows, before any write) |
| `User.upsert(data)` | Yes |
| `User.update(data, where)` / `User.updateWhere(where, data)` | Yes (on `data` only) |
| `player:update(data)` | Yes |
| `User.find(where)` | No (no data to validate; column names are still checked) |
| `User.delete(where)` | No |
| `increment` / `decrement` | No |
| `tx:insert`, `tx:update`, `tx:upsert` (transactions) | **No**: they do not go through the model |
| `OrvexORM.raw` / `rawExec` | No |

## Handling errors

Validation throws a **Lua error** if a column is unknown or a type doesn't match. The error points at **your** line of code (the file and line of the `create`/`update` call), not inside OrvexORM. When several fields are invalid, the one reported is the first in alphabetical order, always the same from one call to the next. You can catch it with `pcall`:

```lua
local ok, err = pcall(function()
    User.create({
        identifier = 123,          -- should be a string
        money      = "a lot",      -- should be a number
    })
end)

if not ok then
    print("Validation error: " .. err)
    -- "Validation error: server.lua:12: Field 'identifier': expected string, got number"
end
```

:::tip Advice
In general, you don't need to catch validation errors. They're there to signal a bug in your code — if you're sending the wrong type, something is wrong with your logic.
:::
