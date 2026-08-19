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

## Eager Loading

Instead of calling `:get("relation")` each time, you can load relations automatically with `include`:

```lua
local player = User.find({ identifier = "license:abc" }, {
    include = { "profile", "vehicles" }
})

-- Relations are already loaded
print(player.profile.bio)
print(#player.vehicles)
```

`findAll` (and `all`) also accept `include`. Relations are loaded in **batch**: a single `WHERE fk IN (...)` query per relation, no matter how many rows are returned (no N+1 problem).

```lua
local cops = User.findAll({ job = "police" }, {
    include = { "vehicles" }
})
-- 2 queries total: 1 for the users, 1 for all their vehicles

for _, cop in ipairs(cops) do
    print(cop.identifier .. " has " .. #cop.vehicles .. " vehicle(s)")
end
```

**Generated SQL:**
```sql
SELECT * FROM users WHERE job = ?
SELECT * FROM vehicles WHERE owner_id IN (?, ?, ?)
```

:::info
Batched loading works for `hasOne`, `hasMany`, and `belongsTo`. For `belongsToMany`, relations are loaded per instance.
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

---

## countByRelation — Count relations

Counts how many related records each parent has. A single `GROUP BY` query is used, no matter how many parents there are.

```lua
local results = User.countByRelation("vehicles")

for _, entry in ipairs(results) do
    print(entry.instance.identifier .. " has " .. entry.count .. " vehicle(s)")
    -- Also available on the instance:
    print(entry.instance._count_vehicles)
end
```

---

## Nested Writes

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

The foreignKey is automatically filled in. This is equivalent to:

```lua
local player = User.create({ identifier = "license:abc", money = 500, job = "police" })
Profile.create({ user_id = "license:abc", bio = "New player", avatar = "default.png" })
Vehicle.create({ owner_id = "license:abc", plate = "ABC123", model = "sultan" })
Vehicle.create({ owner_id = "license:abc", plate = "XYZ789", model = "adder" })
```

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
| Eager Loading | `Model.find/findAll(where, { include = {...} })` | Loads relations automatically (batched on `findAll`) |
| Filter by relation | `Model.whereHas("relation")` | WHERE EXISTS |
| Count relations | `Model.countByRelation("relation")` | Counts the links |
| Nested Writes | `Model.createWith(data)` | Creates parent + children |
