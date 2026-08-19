---
sidebar_position: 11
---

# OrvexORM Studio

OrvexORM Studio est une **interface web** qui te permet de visualiser et gerer ta base de donnees directement depuis ton navigateur. C'est comme Prisma Studio, mais pour FiveM.

## Lancement

Aucune installation requise. Le studio est 100% Lua, integre directement dans la ressource orvexorm. Il fonctionne avec **oxmysql** et **mysql-async** : les requetes sont routees via l'adaptateur de l'ORM, quelle que soit la librairie installee.

### Depuis la console txAdmin

Tape simplement dans la console :

```
orvexstudio
```

Le studio :
1. Genere un **token secret** avec la source aleatoire du systeme, ou utilise le convar `orvex_studio_token` s'il contient au moins 32 caracteres
2. Active les routes web integrees a la ressource
3. Affiche l'URL d'acces dans la console

```
══════════════════════════════════════════════════
  OrvexORM Studio
══════════════════════════════════════════════════

  URL : http://localhost:30120/orvexorm/?token=a1b2c3d4e5f6...

  Share this URL only with trusted people.
  Type 'orvexstudio stop' to stop.

══════════════════════════════════════════════════
```

Pour arreter :
```
orvexstudio stop
```

### Acces a distance

Si tu es sur un serveur dedie, remplace `localhost` par l'IP de ton serveur :
```
http://123.45.67.89:30120/orvexorm/?token=a1b2c3d4...
```

Le port `30120` est le port HTTP de FiveM (le meme que ton serveur).

## Securite

Le studio est protege par un **token aleatoire** genere a chaque lancement. Si la source aleatoire du systeme n'est pas disponible, le demarrage echoue au lieu de creer un token previsible. Tu peux fournir un token stable avec `set orvex_studio_token "..."` ; il doit contenir au moins 32 caracteres.

- Le token initial est dans l'URL, puis il est retire de la barre d'adresse et envoye dans l'en-tete `X-Studio-Token`
- Aucun cookie d'authentification n'est cree
- Le token expire apres **30 minutes** ; relance `orvexstudio` pour obtenir une nouvelle session
- Sans le token, toute requete retourne `403 Access Denied`
- **Protection anti-bruteforce** : une IP est verrouillee pendant **5 minutes** apres **5 tokens invalides**
- Les requetes sont limitees a **120 par minute et par adresse** et les corps a **1 Mio**

:::caution
OrvexORM Studio est un **outil de developpement**. L'endpoint est expose sur le port public `30120` (le port HTTP de FiveM) : tant que le studio tourne, n'importe qui connaissant le token a un acces complet a ta base de donnees. Le token est regenere a chaque demarrage, mais prends l'habitude d'arreter le studio (`orvexstudio stop`) des que tu as fini.
:::

## Fonctionnalites

### Voir toutes les tables

Le panneau gauche affiche toutes les tables de ta base de donnees avec le nombre de lignes. Clique sur une table pour voir son contenu.

### Parcourir les donnees

- **Pagination** : navigue page par page (10, 25, 50 ou 100 lignes par page)
- **Tri** : clique sur un en-tete de colonne pour trier (ASC/DESC)
- **Filtres** : filtre les donnees par colonne avec les operateurs `=`, `!=`, `>`, `<`, `LIKE`, `IS NULL`, etc.

### Modifier les donnees

- **Ajouter une ligne** : clique sur "Add Row", remplis le formulaire, et valide
- **Modifier une ligne** : utilise le bouton d'edition de la ligne pour ouvrir l'editeur
- **Supprimer une ligne** : clique sur le bouton de suppression (avec confirmation)

Les champs du formulaire s'adaptent automatiquement au type de la colonne :

| Type MySQL | Champ |
|---|---|
| VARCHAR, TEXT | Champ texte |
| INT, BIGINT, FLOAT | Champ nombre |
| TINYINT(1) | Case a cocher |
| JSON | Zone de texte |
| DATE | Selecteur de date |
| DATETIME | Selecteur date + heure |
| ENUM | Liste deroulante |

### Voir le schema

L'onglet "Schema" affiche la structure de la table (colonnes, types, cles, valeurs par defaut).

## Raccourcis clavier

| Raccourci | Action |
|---|---|
| `Escape` | Fermer la modale |
