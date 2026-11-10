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

  Allowed addresses : 127.0.0.1, ::1 (convar orvex_studio_allow)

  Share this URL only with trusted people.
  Traffic is plain HTTP: from a remote machine, use an SSH tunnel
  (ssh -L 30120:127.0.0.1:30120 user@server) instead of widening the allowlist.
  Stop the Studio as soon as you are done.
  Type 'orvexstudio stop' to stop.
  This Studio session expires after 30 minutes.

══════════════════════════════════════════════════
```

Pour arreter :
```
orvexstudio stop
```

### Acces a distance : tunnel SSH (recommande)

Par defaut, le Studio ne repond **qu'aux connexions locales** (`127.0.0.1` et `::1`). Si ton serveur est distant, ne l'ouvre pas au reseau : cree un tunnel SSH depuis ton PC, qui fait passer ta connexion pour une connexion locale.

```bash
# Sur ton PC
ssh -L 30120:127.0.0.1:30120 user@ton-serveur
```

Laisse ce terminal ouvert, puis ouvre dans ton navigateur l'URL affichee dans la console, telle quelle :

```
http://localhost:30120/orvexorm/?token=a1b2c3d4...
```

Le port `30120` est le port HTTP de FiveM (le meme que ton serveur). Si ton serveur utilise un autre port, adapte les deux cotes du tunnel (`-L 30120:127.0.0.1:<port>`).

### Autoriser d'autres adresses : `orvex_studio_allow`

Le convar `orvex_studio_allow` liste les adresses autorisees. Il est lu **au lancement de `orvexstudio`** : modifie-le avant de lancer le Studio (ou fais `orvexstudio stop` puis `orvexstudio`).

```cfg title="server.cfg (ou console)"
# Defaut : loopback uniquement
set orvex_studio_allow "127.0.0.1, ::1"

# Ajouter un poste du reseau local et une plage IPv4
set orvex_studio_allow "127.0.0.1, ::1, 192.168.1.20, 10.0.0.0/24"

# N'importe quelle adresse (deconseille)
set orvex_studio_allow "*"
```

| Entree | Exemple | Effet |
|---|---|---|
| Adresse IPv4 ou IPv6 exacte | `192.168.1.20`, `::1` | Autorise cette adresse |
| Plage IPv4 CIDR | `10.0.0.0/24` | Autorise toute la plage |
| `*` | `*` | Autorise toutes les adresses |

Les entrees sont separees par des virgules ou des espaces. Une entree invalide est ignoree (un message s'affiche dans la console) ; si aucune entree n'est valide, **personne** n'est autorise. Une valeur vide revient au defaut.

:::danger Le trafic est en HTTP clair
Le Studio n'a pas de HTTPS : en elargissant la liste, le token et le contenu de ta base passent **en clair** sur le reseau. Prefere toujours le tunnel SSH.
:::

:::caution Derriere un proxy (txAdmin, reverse proxy)
Derriere un proxy, l'adresse vue par le Studio est celle **du proxy**, pour tous les clients. La liste d'autorisation, la limite de requetes et le verrouillage anti-bruteforce s'appliquent alors au proxy entier. N'autorise jamais l'adresse d'un proxy expose sur internet.
:::

## Securite

Le studio est protege par un **token aleatoire** genere a chaque lancement. Si la source aleatoire du systeme n'est pas disponible, le demarrage echoue au lieu de creer un token previsible. Tu peux fournir un token stable avec `set orvex_studio_token "..."` ; il doit contenir au moins 32 caracteres.

- **Filtrage reseau** : une requete venant d'une adresse hors de `orvex_studio_allow` recoit un simple `404 Not Found`, sans log
- Studio arrete : toute requete recoit le meme `404 Not Found` (pas de log, rien ne trahit sa presence)
- Le token dans l'URL (`?token=`) n'est accepte **que pour le premier chargement de la page**. La page le retire de la barre d'adresse, le garde en memoire et l'envoie ensuite dans l'en-tete `X-Studio-Token`. Les routes `/api/*` refusent le token en parametre d'URL (`403`)
- Recharger la page apres le retrait du token donne un `403` : rouvre l'URL affichee dans la console
- Aucun cookie d'authentification n'est cree
- Le token expire apres **30 minutes** ; relance `orvexstudio` pour obtenir une nouvelle session
- Sans token valide, la requete retourne `403`
- **Protection anti-bruteforce** : une IP est verrouillee pendant **5 minutes** apres **5 tokens invalides**
- Les requetes sont limitees a **120 par minute et par adresse** (verifie avant le token) et les corps a **1 Mio**
- Les refus pour limite de requetes ou verrouillage sont journalises **une fois** par fenetre ou par verrouillage, pas a chaque requete
- La page est servie avec une politique CSP stricte (scripts et styles limites a un nonce par chargement) et les donnees des lignes sont toujours inserees comme du texte : une valeur stockee par un joueur ne peut pas executer de script dans ton navigateur

:::caution
OrvexORM Studio est un **outil de developpement**. Tant qu'il tourne, quiconque a le token **et** une adresse autorisee a un acces complet a ta base de donnees. Le token est regenere a chaque demarrage, mais prends l'habitude d'arreter le studio (`orvexstudio stop`) des que tu as fini.
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

## Personnaliser `studio.html`

La page est servie avec une politique CSP sans `'unsafe-inline'`. Si tu modifies `studio.html` :

- n'ajoute pas d'attributs `onclick` / `style` inline : ils seraient bloques ;
- garde le placeholder `{{NONCE}}` sur les balises `<script>` et `<style>` (`<script nonce="{{NONCE}}">`), remplace a chaque chargement par un nonce aleatoire ;
- n'insere jamais une valeur de ligne avec `innerHTML` : utilise `textContent` ou `.value`.
