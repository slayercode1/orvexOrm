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

Every time you use `create`, `update`, or `upsert`, OrvexORM verifies that the values match the declared types.

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
| `User.upsert(data)` | Yes |
| `User.update(data, where)` | Yes (on `data` only) |
| `player:update(data)` | Yes |
| `User.find(where)` | No (no data to validate) |
| `User.delete(where)` | No |

## Handling errors

Validation throws a **Lua error** if the types don't match. You can catch it with `pcall`:

```lua
local ok, err = pcall(function()
    User.create({
        identifier = 123,          -- should be a string
        money      = "a lot",      -- should be a number
    })
end)

if not ok then
    print("Validation error: " .. err)
    -- "Validation error: Field 'identifier': expected string, got number"
end
```

:::tip Advice
In general, you don't need to catch validation errors. They're there to signal a bug in your code — if you're sending the wrong type, something is wrong with your logic.
:::
