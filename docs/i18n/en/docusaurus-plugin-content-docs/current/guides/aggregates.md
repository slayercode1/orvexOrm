---
sidebar_position: 5
---

# Aggregations

**Aggregations** let you perform calculations on your data: count, sum, average, etc.

## Quick methods

OrvexORM provides simple shortcuts that work directly on the model.

:::caution Argument order
`count(where?)` takes the filter first, whereas `sum`, `avg`, `min` and `max` take **the column first**: `User.sum("money", { job = "police" })`. Soft-deleted rows (`softDelete`) are excluded.
:::

### `count` — Count

```lua
-- Count all players
local total = User.count()
print(total)  -- 150

-- Count police officers
local cops = User.count({ job = "police" })
print(cops)  -- 12
```

**Generated SQL:**
```sql
SELECT COUNT(*) as cnt FROM users
SELECT COUNT(*) as cnt FROM users WHERE job = ?
```

### `sum` — Sum

```lua
-- Total money of all players
local totalMoney = User.sum("money")
print(totalMoney)  -- 1500000

-- Total money of police officers
local copMoney = User.sum("money", { job = "police" })
print(copMoney)  -- 250000
```

### `avg` — Average

```lua
-- Average money per player
local average = User.avg("money")
print(average)  -- 10000

-- Average money of medics
local medicAvg = User.avg("money", { job = "medic" })
```

### `min` — Minimum

```lua
-- The poorest player
local poorest = User.min("money")
print(poorest)  -- 0
```

### `max` — Maximum

```lua
-- The richest player
local richest = User.max("money")
print(richest)  -- 999999
```

---

## Via the Query Builder

For more control, you can use aggregations in the Query Builder:

```lua
-- Count rich players who aren't banned
local count = User.query()
    :where("money", ">", 10000)
    :where({ status = { "!=", "banned" } })
    :count()

-- Sum of money for emergency workers
local total = User.query()
    :where({ job = { "IN", { "police", "medic", "firefighter" } } })
    :sum("money")

-- Average money per job (with groupBy)
local stats = User.query()
    :select("job, AVG(money) as avg_money, COUNT(*) as nb")
    :groupBy("job")
    :having("COUNT(*) > ?", 2)
    :orderBy("avg_money", "DESC")
    :get()

for _, stat in ipairs(stats) do
    print(stat.job .. " : " .. stat.avg_money .. "$ on average (" .. stat.nb .. " players)")
end
-- police : 15000$ on average (12 players)
-- medic : 12000$ on average (8 players)
```

---

## Summary

| Method | Shortcut | Via Builder | Returns |
|---|---|---|---|
| Count | `User.count(where?)` | `:count()` | `integer` |
| Sum | `User.sum("col", where?)` | `:sum("col")` | `number` |
| Average | `User.avg("col", where?)` | `:avg("col")` | `number` |
| Minimum | `User.min("col", where?)` | `:min("col")` | `any` |
| Maximum | `User.max("col", where?)` | `:max("col")` | `any` |
