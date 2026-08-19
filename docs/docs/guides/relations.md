---
sidebar_position: 4
---

# Relations

Les **relations** permettent de lier des tables entre elles. Par exemple, un joueur peut avoir plusieurs vehicules, un vehicule appartient a un joueur, etc.

## Les 4 types de relations

Avant de coder, comprenons les 4 types avec des exemples de la vraie vie :

| Type | Exemple | Explication |
|---|---|---|
| **hasOne** | Un joueur a **un** profil | 1 → 1 |
| **hasMany** | Un joueur a **plusieurs** vehicules | 1 → N |
| **belongsTo** | Un vehicule appartient a **un** joueur | N → 1 (l'inverse de hasMany) |
| **belongsToMany** | Un joueur a **plusieurs** roles, et un role a **plusieurs** joueurs | N → N |

---

## Preparation

Pour les exemples, on va utiliser ces modeles et ces tables :

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

:::info C'est quoi une foreignKey ?
Une **foreignKey** (cle etrangere), c'est une colonne qui fait le lien entre deux tables.

Par exemple, dans la table `vehicles`, la colonne `owner_id` contient l'identifiant du joueur. C'est la foreignKey qui lie un vehicule a son proprietaire.
:::

---

## hasOne (Un a Un)

**Un joueur a un seul profil.**

La foreignKey (`user_id`) se trouve dans la **table liee** (profiles).

```lua
-- Definir la relation
User.hasOne("profile", Profile, { foreignKey = "user_id" })
```

```lua
-- Utiliser la relation
local player = User.find({ identifier = "license:abc" })
local profile = player:get("profile")

if profile then
    print(profile.bio)     -- "Salut je suis nouveau !"
    print(profile.avatar)  -- "avatar.png"
end
```

**SQL genere en arriere-plan :**
```sql
SELECT * FROM profiles WHERE user_id = 'license:abc'
```

**Schema visuel :**
```
users                      profiles
┌──────────────┐           ┌──────────────┐
│ identifier ◄─┼───────────┼─ user_id     │
│ money        │           │ bio          │
│ job          │           │ avatar       │
└──────────────┘           └──────────────┘
```

---

## hasMany (Un a Plusieurs)

**Un joueur a plusieurs vehicules.**

La foreignKey (`owner_id`) se trouve dans la **table liee** (vehicles).

```lua
-- Definir la relation
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
```

```lua
-- Utiliser la relation
local player = User.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")

print(#vehicles .. " vehicules trouves")

for _, v in ipairs(vehicles) do
    print(v.plate .. " — " .. v.model)
end
-- ABC123 — sultan
-- XYZ789 — adder
```

**SQL genere :**
```sql
SELECT * FROM vehicles WHERE owner_id = 'license:abc'
```

**Schema visuel :**
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

## belongsTo (Plusieurs a Un)

**Un vehicule appartient a un joueur.** C'est l'inverse de hasMany.

La foreignKey (`owner_id`) se trouve dans **cette table** (vehicles).

```lua
-- Definir la relation
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
```

```lua
-- Utiliser la relation
local car = Vehicle.find({ plate = "ABC123" })
local owner = car:get("owner")

print(owner.identifier)  -- "license:abc"
print(owner.money)        -- 500
```

**SQL genere :**
```sql
SELECT * FROM users WHERE identifier = 'license:abc'
```

:::tip hasMany et belongsTo vont ensemble
Si `User` **hasMany** `Vehicle`, alors `Vehicle` **belongsTo** `User`. C'est la meme relation vue des deux cotes.
:::

---

## belongsToMany (Plusieurs a Plusieurs)

**Un joueur peut avoir plusieurs roles, et un role peut etre attribue a plusieurs joueurs.**

Ce type de relation necessite une **table pivot** (aussi appelee table de jonction) qui fait le lien entre les deux tables.

### La table pivot

```sql
CREATE TABLE `user_roles` (
    `user_id` VARCHAR(60) NOT NULL,
    `role_id` INT NOT NULL,
    PRIMARY KEY (`user_id`, `role_id`)
);
```

Cette table ne contient que deux colonnes qui font le lien entre `users` et `roles`.

### Definir la relation

```lua
User.belongsToMany("roles", Role, {
    pivot      = "user_roles",    -- nom de la table pivot
    foreignKey = "user_id",       -- colonne pivot → users
    otherKey   = "role_id",       -- colonne pivot → roles
})
```

### Lire les roles d'un joueur

```lua
local player = User.find({ identifier = "license:abc" })
local roles = player:get("roles")

for _, role in ipairs(roles) do
    print(role.name)  -- "admin", "moderator"
end
```

**SQL genere :**
```sql
SELECT roles.* FROM roles
INNER JOIN user_roles ON user_roles.role_id = roles.id
WHERE user_roles.user_id = 'license:abc'
```

### Attribuer un role (attach)

```lua
local admin = Role.find({ name = "admin" })
player:attach("roles", admin)
```

**SQL genere :**
```sql
INSERT INTO user_roles (role_id, user_id) VALUES (?, ?)
```

### Retirer un role (detach)

```lua
player:detach("roles", admin)
```

**SQL genere :**
```sql
DELETE FROM user_roles WHERE role_id = ? AND user_id = ?
```

**Schema visuel :**
```
users               user_roles          roles
┌──────────────┐    ┌────────────┐    ┌──────────────┐
│ identifier ◄─┼────┼─ user_id   │    │ id ◄─────────┤
│ money        │    │ role_id ───┼────┼──────────────┤
│ job          │    └────────────┘    │ name         │
└──────────────┘                      └──────────────┘
```

---

## Definir les relations des deux cotes

En general, tu veux definir la relation dans les **deux sens** :

```lua
-- Un joueur a plusieurs vehicules
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })

-- Un vehicule appartient a un joueur
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
```

Ca te permet de naviguer dans les deux directions :

```lua
-- Joueur → Vehicules
local player = User.find({ identifier = "license:abc" })
local vehicles = player:get("vehicles")

-- Vehicule → Joueur
local car = Vehicle.find({ plate = "ABC123" })
local owner = car:get("owner")
```

---

## Eager Loading (Chargement avance)

Au lieu d'appeler `:get("relation")` a chaque fois, tu peux charger les relations automatiquement avec `include` :

```lua
local player = User.find({ identifier = "license:abc" }, {
    include = { "profile", "vehicles" }
})

-- Les relations sont deja chargees
print(player.profile.bio)
print(#player.vehicles)
```

### Eager loading sur plusieurs resultats

`findAll` (et son raccourci `all`) accepte aussi `include`. Le chargement est **batche** : une seule requete `WHERE fk IN (...)` par relation, quel que soit le nombre de resultats. C'est ce qui evite le fameux probleme **N+1** (1 requete par joueur).

```lua
local cops = User.findAll({ job = "police" }, {
    include = { "profile", "vehicles" }
})

for _, cop in ipairs(cops) do
    print(cop.profile.bio)   -- deja charge, aucune requete
    print(#cop.vehicles)     -- deja charge, aucune requete
end
```

**SQL genere (3 requetes au total, peu importe le nombre de policiers) :**
```sql
SELECT * FROM users WHERE job = ?
SELECT * FROM profiles WHERE user_id IN (?, ?, ?)
SELECT * FROM vehicles WHERE owner_id IN (?, ?, ?)
```

:::info belongsToMany
Le chargement batche fonctionne pour `hasOne`, `hasMany` et `belongsTo`. Les relations `belongsToMany` retombent sur un chargement par instance (une requete par resultat).
:::

---

## whereHas — Filtrer par relation

Recupere les enregistrements qui ont au moins un enregistrement lie.

```lua
-- Joueurs qui ont au moins un vehicule
local players = User.whereHas("vehicles"):get()
```

Tu peux aussi ajouter des conditions sur la relation :

```lua
-- Joueurs qui ont un vehicule de luxe
local players = User.whereHas("vehicles", function(b)
    b:where({ model = "adder" })
end):get()
```

**SQL genere :**
```sql
SELECT * FROM users WHERE EXISTS (
    SELECT 1 FROM vehicles WHERE vehicles.owner_id = users.identifier
    AND model = ?
)
```

---

## countByRelation — Compter les relations

Compte combien d'enregistrements lies chaque parent possede. Les comptes sont recuperes en **une seule** requete `GROUP BY` (au lieu d'un `COUNT` par parent).

```lua
local results = User.countByRelation("vehicles")

for _, entry in ipairs(results) do
    print(entry.instance.identifier .. " a " .. entry.count .. " vehicule(s)")
    -- Aussi disponible sur l'instance :
    print(entry.instance._count_vehicles)
end
```

---

## Nested Writes — Ecriture imbriquee

Cree un enregistrement avec ses relations en un seul appel.

```lua
local player = User.createWith({
    identifier = "license:abc",
    money      = 500,
    job        = "police",
    -- Cree automatiquement le profil lie
    profile = { bio = "Nouveau joueur", avatar = "default.png" },
    -- Cree automatiquement les vehicules lies
    vehicles = {
        { plate = "ABC123", model = "sultan" },
        { plate = "XYZ789", model = "adder" },
    },
})
```

La foreignKey est automatiquement remplie. C'est equivalent a :

```lua
local player = User.create({ identifier = "license:abc", money = 500, job = "police" })
Profile.create({ user_id = "license:abc", bio = "Nouveau joueur", avatar = "default.png" })
Vehicle.create({ owner_id = "license:abc", plate = "ABC123", model = "sultan" })
Vehicle.create({ owner_id = "license:abc", plate = "XYZ789", model = "adder" })
```

---

## Recapitulatif

| Relation | Methode | ForeignKey sur... | Retourne |
|---|---|---|---|
| hasOne | `Model.hasOne(name, Related, opts)` | Table liee | Instance ou nil |
| hasMany | `Model.hasMany(name, Related, opts)` | Table liee | Liste d'instances |
| belongsTo | `Model.belongsTo(name, Related, opts)` | Cette table | Instance ou nil |
| belongsToMany | `Model.belongsToMany(name, Related, opts)` | Table pivot | Liste d'instances |

| Action pivot | Methode | Description |
|---|---|---|
| Attribuer | `instance:attach("name", related)` | Insere dans la table pivot |
| Retirer | `instance:detach("name", related)` | Supprime de la table pivot |

| Fonctionnalite avancee | Methode | Description |
|---|---|---|
| Eager Loading | `Model.find(where, { include = {...} })` | Charge les relations automatiquement |
| Eager Loading (liste) | `Model.findAll(where, { include = {...} })` | Chargement batche, 1 requete par relation |
| Filtrer par relation | `Model.whereHas("relation")` | WHERE EXISTS |
| Compter les relations | `Model.countByRelation("relation")` | Compte les liens |
| Ecriture imbriquee | `Model.createWith(data)` | Cree parent + enfants |
