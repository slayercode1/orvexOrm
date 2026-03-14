---
sidebar_position: 5
---

# Agregations

Les **agregations** te permettent de faire des calculs sur tes donnees : compter, additionner, faire une moyenne, etc.

## Les methodes rapides

OrvexORM propose des raccourcis simples qui fonctionnent directement sur le modele.

### `count` — Compter

```lua
-- Compter tous les joueurs
local total = User.count()
print(total)  -- 150

-- Compter les policiers
local cops = User.count({ job = "police" })
print(cops)  -- 12
```

**SQL genere :**
```sql
SELECT COUNT(*) as cnt FROM users
SELECT COUNT(*) as cnt FROM users WHERE job = ?
```

### `sum` — Additionner

```lua
-- Argent total de tous les joueurs
local totalMoney = User.sum("money")
print(totalMoney)  -- 1500000

-- Argent total des policiers
local copMoney = User.sum("money", { job = "police" })
print(copMoney)  -- 250000
```

### `avg` — Moyenne

```lua
-- Argent moyen par joueur
local average = User.avg("money")
print(average)  -- 10000

-- Argent moyen des medecins
local medicAvg = User.avg("money", { job = "medic" })
```

### `min` — Minimum

```lua
-- Le joueur le plus pauvre
local poorest = User.min("money")
print(poorest)  -- 0
```

### `max` — Maximum

```lua
-- Le joueur le plus riche
local richest = User.max("money")
print(richest)  -- 999999
```

---

## Via le Query Builder

Pour plus de controle, tu peux utiliser les agregations dans le Query Builder :

```lua
-- Compter les joueurs riches non bannis
local count = User.query()
    :where("money", ">", 10000)
    :where({ status = { "!=", "banned" } })
    :count()

-- Somme de l'argent des travailleurs d'urgence
local total = User.query()
    :where({ job = { "IN", { "police", "medic", "firefighter" } } })
    :sum("money")

-- Moyenne d'argent par job (avec groupBy)
local stats = User.query()
    :select("job, AVG(money) as avg_money, COUNT(*) as nb")
    :groupBy("job")
    :having("COUNT(*) > ?", 2)
    :orderBy("avg_money", "DESC")
    :get()

for _, stat in ipairs(stats) do
    print(stat.job .. " : " .. stat.avg_money .. "$ en moyenne (" .. stat.nb .. " joueurs)")
end
-- police : 15000$ en moyenne (12 joueurs)
-- medic : 12000$ en moyenne (8 joueurs)
```

---

## Recapitulatif

| Methode | Raccourci | Via Builder | Retourne |
|---|---|---|---|
| Compter | `User.count(where?)` | `:count()` | `integer` |
| Additionner | `User.sum("col", where?)` | `:sum("col")` | `number` |
| Moyenne | `User.avg("col", where?)` | `:avg("col")` | `number` |
| Minimum | `User.min("col", where?)` | `:min("col")` | `any` |
| Maximum | `User.max("col", where?)` | `:max("col")` | `any` |
