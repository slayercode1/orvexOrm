---
sidebar_position: 11
---

# OrvexORM Studio

OrvexORM Studio est une **interface web** qui te permet de visualiser et gerer ta base de donnees directement depuis ton navigateur. C'est comme Prisma Studio, mais pour FiveM.

## Lancement

Aucune installation requise. Le studio est 100% Lua, integre directement dans la ressource orvexorm.

### Depuis la console txAdmin

Tape simplement dans la console :

```
orvexstudio
```

Le studio :
1. Lit automatiquement le `mysql_connection_string` de ton `server.cfg`
2. Genere un **token secret** de securite
3. Lance le serveur web
4. Affiche l'URL securisee dans la console

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

Le studio est protege par un **token aleatoire** genere a chaque lancement. Seules les personnes qui voient la console txAdmin ont acces a l'URL.

- Le token est dans l'URL : `http://localhost:30120/orvexorm/?token=...`
- Apres la premiere connexion, un cookie est place (valide 24h)
- Sans le token, toute requete retourne `403 Access Denied`

:::caution
OrvexORM Studio est un **outil de developpement**. Ne l'expose jamais sur un serveur accessible publiquement. Il donne un acces complet a ta base de donnees.
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
- **Modifier une ligne** : clique sur une ligne pour ouvrir l'editeur
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
