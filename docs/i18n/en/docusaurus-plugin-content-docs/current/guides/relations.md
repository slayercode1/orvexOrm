---
sidebar_position: 4
---

# Relations

**Relations** let you link tables together. For example, a player can have multiple vehicles, a vehicle belongs to a player, etc.

## The 4 types of relations

Before coding, let's understand the 4 types with real-life examples:

| Type | Example | Explanation |
|---|---|---|
| **hasOne** | A player has **one** profile | 1 to 1 |
| **hasMany** | A player has **many** vehicles | 1 to N |
| **belongsTo** | A vehicle belongs to **one** player | N to 1 (the inverse of hasMany) |
| **belongsToMany** | A player has **many** roles, and a role has **many** players | N to N |

---

## Setup

For the examples, we'll use these models and tables:

```lua
local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

local Profile = ORM.model("profiles", {
    id      = "number",
    user_id = "string",
    bio     = "string",
    avatar  = "string",
}, { primaryKey = "id" })

local Vehicle = ORM.model("vehicles", {
    id       = "number",
    owner_id = "string",
    plate    = "string",
    model    = "string",
}, { primaryKey = "id" })

local Role = ORM.model("roles", {
    id   = "number",
    name = "string",
}, { primaryKey = "id" })
```

:::info What is a foreignKey?
A **foreignKey** (foreign key) is a column that creates the link between two tables.

For example, in the `vehicles` table, the `owner_id` column contains the player's identifier. It's the foreignKey that links a vehicle to its owner.
:::

:::info Rules shared by every relation
- Declaring a relation (`User.hasMany(...)`) runs no query: you can do it at the top level of the script. Loading it (`:get()`, `include`, `whereHas`) waits for the database: in a thread, an event or a command.
- If the linking key is `nil` (for example a vehicle without `owner_id`), no query runs: `nil` for `hasOne` / `belongsTo`, `{}` for `hasMany` / `belongsToMany`.
- If the related model has `softDelete = true`, its soft-deleted rows are excluded everywhere: `:get()`, `include`, `whereHas` and `countByRelation`.
:::

---

## hasOne (One to One)

**A player has a single profile.**

The foreignKey (`user_id`) is located in the **related table** (profiles).

```lua
-- Define the relation
User.hasOne("profile", Profile, { foreignKey = "user_id" })
```

```lua
-- Use the relation
local player = User.find({ identifier = "license:abc" })
local profile = player:get("profile")

if profile then
    print(profile.bio)     -- "Hey I'm new here!"
    print(profile.avatar)  -- "avatar.png"
end
```

**SQL generated behind the scenes:**
```sql
SELECT * FROM profiles WHERE user_id = 'license:abc'
```

**Visual schema:**
```
users                      profiles
┌──────────────┐           ┌──────────────┐
│ identifier ◄─┼───────────┼─ user_id     │
│ money        │           │ bio          │
│ job          │           │ avatar       │
└──────────────┘           └──────────────┘
```

---

## hasMany (One to Many)

**A player has multiple vehicles.**

The foreignKey (`owner_id`) is located in the **related table** (vehicles).

```lua
-- Define the relation
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
```

```lua
-- Use the relation
local player = User.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")

print(#vehicles .. " vehicles found")

for _, v in ipairs(vehicles) do
    print(v.plate .. " — " .. v.model)
end
-- ABC123 — sultan
-- XYZ789 — adder
```

**Generated SQL:**
```sql
SELECT * FROM vehicles WHERE owner_id = 'license:abc'
```

**Visual schema:**
```
users                      vehicles
┌──────────────┐           ┌──────────────┐
│ identifier ◄─┼───┬───────┼─ owner_id    │
│ money        │   │       │ plate        │
│ job          │   │       │ model        │
└──────────────┘   │       └──────────────┘
                   │       ┌──────────────┐
                   └───────┼─ owner_id    │
                           │ plate        │
                           │ model        │
                           └──────────────┘
```

---

## belongsTo (Many to One)

**A vehicle belongs to a player.** This is the inverse of hasMany.

The foreignKey (`owner_id`) is located in **this table** (vehicles).

```lua
-- Define the relation
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
```

```lua
-- Use the relation
local car = Vehicle.find({ plate = "ABC123" })
local owner = car:get("owner")

print(owner.identifier)  -- "license:abc"
print(owner.money)        -- 500
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE identifier = 'license:abc'
```

:::tip hasMany and belongsTo go together
If `User` **hasMany** `Vehicle`, then `Vehicle` **belongsTo** `User`. It's the same relation viewed from both sides.
:::

---

## belongsToMany (Many to Many)

**A player can have multiple roles, and a role can be assigned to multiple players.**

This type of relation requires a **pivot table** (also called a junction table) that creates the link between the two tables.

### The pivot table

```sql
CREATE TABLE `user_roles` (
    `user_id` VARCHAR(60) NOT NULL,
    `role_id` INT NOT NULL,
    PRIMARY KEY (`user_id`, `role_id`)
);
```

This table only contains two columns that link `users` and `roles`.

### Defining the relation

```lua
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",    -- name of the pivot table
    foreignKey = "user_id",       -- pivot column → users
    otherKey   = "role_id",       -- pivot column → roles
})
```

`pivot`, `foreignKey` and `otherKey` are required: without one of them, the definition raises an error. A relation's keys (and those passed to `attach` / `detach`) must be strings, booleans or finite numbers; any other value raises an error instead of changing the query's condition.

### Reading a player's roles

```lua
local player = User.find({ identifier = "license:abc" })
local roles = player:get("roles")

for _, role in ipairs(roles) do
    print(role.name)  -- "admin", "moderator"
end
```

**Generated SQL:**
```sql
SELECT roles.* FROM roles
INNER JOIN user_roles ON user_roles.role_id = roles.id
WHERE user_roles.user_id = 'license:abc'
```

### Assigning a role (attach)

```lua
local admin = Role.find({ name = "admin" })
player:attach("roles", admin)
```

**Generated SQL:**
```sql
INSERT INTO user_roles (role_id, user_id) VALUES (?, ?)
```

### Removing a role (detach)

```lua
player:detach("roles", admin)
```

**Generated SQL:**
```sql
DELETE FROM user_roles WHERE role_id = ? AND user_id = ?
```

**Visual schema:**
```
users               user_roles          roles
┌──────────────┐    ┌────────────┐    ┌──────────────┐
│ identifier ◄─┼────┼─ user_id   │    │ id ◄─────────┤
│ money        │    │ role_id ───┼────┼──────────────┤
│ job          │    └────────────┘    │ name         │
└──────────────┘                      └──────────────┘
```

---

## Defining relations from both sides

In general, you want to define the relation in **both directions**:

```lua
-- A player has many vehicles
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })

-- A vehicle belongs to a player
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
```

This lets you navigate in both directions:

```lua
-- Player → Vehicles
local player = User.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")

-- Vehicle → Player
local car = Vehicle.find({ plate = "ABC123" })
local owner = car:get("owner")
```

---

## Eager Loading (loading ahead)

Instead of calling `:get("relation")` each time, you can load relations automatically with `include`:

```lua
local player = User.find({ identifier = "license:abc" }, {
    include = { "profile", "vehicles" }
})

-- Relations are already loaded
print(player.profile.bio)
print(#player.vehicles)
```

### Eager loading on several results

`findAll` (and its shortcut `all`) also accepts `include`. Loading is **batched**: a single `WHERE fk IN (...)` query per relation, no matter how many results there are. This is what avoids the well-known **N+1** problem (1 query per player).

```lua
local cops = User.findAll({ job = "police" }, {
    include = { "profile", "vehicles" }
})

for _, cop in ipairs(cops) do
    print(cop.profile.bio)   -- already loaded, no query
    print(#cop.vehicles)     -- already loaded, no query
end
```

**Generated SQL (3 queries in total, however many officers there are):**
```sql
SELECT * FROM users WHERE job = ?
SELECT * FROM profiles WHERE user_id IN (?, ?, ?)
SELECT * FROM vehicles WHERE owner_id IN (?, ?, ?)
```

:::info belongsToMany
Batched loading works for all 4 relation types. For `belongsToMany`, a single join on the pivot table loads the related rows of every parent:

```sql
SELECT roles.*, user_roles.user_id FROM roles
INNER JOIN user_roles ON user_roles.role_id = roles.id
WHERE user_roles.user_id IN (?, ?, ?)
```
:::

---

## whereHas — Filter by relation

Retrieves records that have at least one related record.

```lua
-- Players who have at least one vehicle
local players = User.whereHas("vehicles"):get()
```

You can also add conditions on the relation:

```lua
-- Players who have a luxury vehicle
local players = User.whereHas("vehicles", function(b)
    b:where({ model = "adder" })
end):get()
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE EXISTS (
    SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.identifier
    AND model = ?
)
```

The linking condition is a constraint: an `orWhere` inside the callback stays grouped with it (`link AND (cond1 OR cond2)`) and cannot match other players' vehicles. For `belongsToMany`, the callback filters the **related** table (joined to the pivot table): qualify ambiguous columns (`b:where("roles.name", "admin")`).

---

## countByRelation — Count relations

Counts how many related records each parent has. The counts are fetched in **a single** `GROUP BY` query (instead of one `COUNT` per parent). Soft-deleted related rows are not counted.

```lua
local results = User.countByRelation("vehicles")

for _, entry in ipairs(results) do
    print(entry.instance.identifier .. " has " .. entry.count .. " vehicle(s)")
    -- Also available on the instance:
    print(entry.instance._count_vehicles)
end
```

---

## Nested Writes — Writing nested records

Creates a record with its relations in a single call.

```lua
local player = User.createWith({
    identifier = "license:abc",
    money      = 500,
    job        = "police",
    -- Automatically creates the related profile
    profile = { bio = "New player", avatar = "default.png" },
    -- Automatically creates the related vehicles
    vehicles = {
        { plate = "ABC123", model = "sultan" },
        { plate = "XYZ789", model = "adder" },
    },
})
```

The foreignKey is automatically filled in. The result is the same as:

```lua
local player = User.create({ identifier = "license:abc", money = 500, job = "police" })
Profile.create({ user_id = "license:abc", bio = "New player", avatar = "default.png" })
Vehicle.create({ owner_id = "license:abc", plate = "ABC123", model = "sultan" })
Vehicle.create({ owner_id = "license:abc", plate = "XYZ789", model = "adder" })
```

but better:

- every row (parent and children) is **validated before** the first write;
- children are inserted with **one multi-row query per table**, in **a single transaction**;
- if that transaction fails, the rows already created (the parent, and the related rows of a `belongsToMany`) are **deleted**, then an error is raised.

The parent and the related rows of a `belongsToMany` (created with `create`) fire all their hooks. The `hasOne` / `hasMany` children inserted in batch fire `beforeCreate` (once per row, foreign key already set) then `afterBulkCreate` (once per relation, after the transaction), but not `afterCreate`. `belongsTo` keys in the data are ignored.

The parent and the `belongsToMany` rows are written **before** the transaction: this is not a fully atomic write (see [`Model.createWith`](/docs/api/model#modelcreatewithdata--orvexinstance)).

:::danger Filter client data
Any key named like a relation is a nested write. Never pass a table received from a client to `createWith` as is: a `roles` field added by the client would create related rows. Build `data` from the fields you expect only.
:::

---

## Summary

| Relation | Method | ForeignKey on... | Returns |
|---|---|---|---|
| hasOne | `Model.hasOne(name, Related, opts)` | Related table | Instance or nil |
| hasMany | `Model.hasMany(name, Related, opts)` | Related table | List of instances |
| belongsTo | `Model.belongsTo(name, Related, opts)` | This table | Instance or nil |
| belongsToMany | `Model.belongsToMany(name, Related, opts)` | Pivot table | List of instances |

| Pivot action | Method | Description |
|---|---|---|
| Assign | `instance:attach("name", related)` | Inserts into the pivot table |
| Remove | `instance:detach("name", related)` | Deletes from the pivot table |

| Advanced feature | Method | Description |
|---|---|---|
| Eager Loading | `Model.find(where, { include = {...} })` | Loads relations automatically |
| Eager Loading (list) | `Model.findAll(where, { include = {...} })` | Batched loading, 1 query per relation |
| Filter by relation | `Model.whereHas("relation")` | WHERE EXISTS |
| Count relations | `Model.countByRelation("relation")` | Counts the links |
| Nested write | `Model.createWith(data)` | Creates parent + children |
