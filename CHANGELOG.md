# Changelog

Toutes les evolutions notables d'OrvexORM. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et le projet respecte le [versionnage semantique](https://semver.org/lang/fr/).

## [1.3.0] - Non publiee

Version de corrections issue d'un audit complet (securite, exactitude du SQL, drivers, cache, Studio,
documentation). La plupart des corrections sont invisibles pour un code correct ; les changements
de comportement a verifier avant de mettre a jour sont regroupes dans
[Changements cassants](#changements-cassants).

### Changements cassants

- **Import entre ressources.** `server_script '@orvexorm/lib/import.lua'` charge maintenant l'ORM
  **dans la ressource qui l'inclut** au lieu de passer par `exports.orvexorm:lib()`. Chaque ressource
  a donc sa propre instance : son cache, son `OrvexORM.debug()`, son `enableCache()` et son
  adaptateur. Les globales `Orvex*` (dont `OrvexAdapter`, `OrvexCache`, `OrvexMySQLDriver`) existent
  aussi dans la ressource. Si `orvexorm` n'est pas demarre, l'import leve une erreur claire au lieu
  de retomber sur l'export.
- **`migrate()` et `rollback()` levent une erreur** a la premiere migration en echec, au lieu de
  continuer. La migration en echec n'est pas enregistree ; les suivantes ne sont pas lancees. Un
  driver qui retourne `nil` pour une requete DDL est considere en echec.
- **`t:id()` dans `schema:table()`** ajoute la colonne avec `AUTO_INCREMENT PRIMARY KEY`.
- **Studio : loopback uniquement par defaut.** Seules `127.0.0.1` et `::1` sont acceptees ; le
  convar `orvex_studio_allow` elargit la liste. Le token en parametre d'URL n'est accepte que pour le
  chargement de la page : `/api/*` exige l'en-tete `X-Studio-Token` (`?token=` y renvoie `403`). Un
  Studio arrete, ou une adresse non autorisee, recoit un `404` texte, sans log (avant, un Studio arrete repondait `503` en JSON).
  La CSP n'autorise plus `'unsafe-inline'` : un `studio.html` personnalise doit utiliser
  `{{NONCE}}` et aucun gestionnaire inline.
- **Detection du driver.** Sans oxmysql ni mysql-async demarre, le premier appel leve
  `No MySQL library found` (avant, le mode export oxmysql etait choisi a tort et la premiere
  requete echouait). Sous mysql-async, `transaction()` demande mysql-async 3.3+ et leve une erreur
  sur une version plus ancienne (avant, un faux succes non atomique). Sous mysql-async,
  `scalar("SELECT ...")` retourne des lignes au lieu d'un nombre de lignes touchees.
- **Le cache est limite a 1000 entrees** par defaut (eviction LRU), y compris le cache global.
- **Les cles de cache** commencent par un en-tete de longueurs et de types. Du code qui construit ses
  cles a la main pour `invalidatePrefix` ne correspond plus (rien dans OrvexORM ne le fait).
- **Colonnes nommees comme une methode d'instance** (`update`, `get`, `delete`, `refresh`...) : elles
  ne masquent plus la methode. Lis-les avec `instance:getAttribute(nom)` ; `toTable()` les inclut.
- **API internes supprimees** (non documentees) : `Schema:typeOf`, `Schema:hasField`,
  `Schema.fieldNames`, `Errors.definition`.
- **`whereIn` / `whereNotIn` n'acceptent plus une chaine comme sous-requete.** Une chaine etait
  inseree telle quelle dans le SQL : `whereIn("id", payload.ids)` devenait une injection SQL des
  qu'un client envoyait une chaine au lieu d'un tableau. Ces methodes levent maintenant une erreur
  pour tout autre type qu'un tableau. Pour une sous-requete, utilise
  `whereInSub(col, subSQL, params?)` / `whereNotInSub(col, subSQL, params?)`.
- **Hooks des lignes imbriquees de `createWith`.** Les enfants `hasOne` / `hasMany` sont inseres en
  lot (`INSERT` multi-lignes) au lieu d'un `create()` par ligne. Ils declenchent toujours
  `beforeCreate` (une fois par ligne, cle etrangere remplie, sur une copie), mais **plus
  `afterCreate`** : aucune instance n'est construite. A la place, `afterBulkCreate(rows)` est
  declenche une fois par relation apres la transaction. Les lignes `belongsToMany` passent toujours
  par `create()` et declenchent tous leurs hooks.
- **`attach()` / `detach()` levent une erreur** si la cle du parent ou de la ligne liee est `nil`
  (avant, la condition disparaissait : `detach` supprimait les liens de **tous** les parents).
- **Le comptage de `count()` / `paginate()` avec `having()` sans `groupBy()`** passe par une table
  derivee (avant, `paginate()` ignorait `having`).
- **Operateurs en table : `ORM.op(operateur, valeur)`.** La forme `{ colonne = { operateur, valeur } }`
  est supprimee partout (`where` / `orWhere` en table, `find`, `findAll`, `findOrFail`, `first`,
  `exists`, `count`, `pluck`, agregations, `countByRelation`, scopes) : ecris
  `{ money = ORM.op(">", 1000) }` (alias `OrvexBuilder.op`). Une table ordinaire comme valeur leve une
  erreur. Seule une valeur creee par `ORM.op` cote serveur est lue comme un operateur : un argument
  d'event client de la forme `{ "LIKE", "%" }` ne peut plus transformer une egalite en `LIKE '%'`.
- **Egalites uniquement** dans le `where` de `update` / `updateWhere`, `delete` / `deleteWhere`,
  `forceDelete`, `restore`, `increment` / `decrement` (classe), `findOrCreate`, `updateOrCreate` et
  `tx:update` / `tx:delete` : un `ORM.op` y leve une erreur.
- **Valeurs liees verifiees.** Les valeurs de `where` / `orWhere`, les elements de `IN` / `BETWEEN`,
  `whereBetween`, les curseurs `after` / `before`, les cles de relation et de pivot (`attach` /
  `detach`) doivent etre une chaine, un booleen ou un nombre fini : une table, `NaN` ou l'infini levent
  une erreur. Un tableau `IN` avec un trou `nil` leve une erreur. Le montant de `increment` /
  `decrement` doit etre un nombre fini.
- **Jointures sur un modele** : avec la selection par defaut, une requete de modele avec jointure
  selectionne `table.*` (la table du modele) au lieu de `*`. Les colonnes des tables jointes doivent
  etre listees avec `:select()`.
- **`whereColumn`** n'accepte que les operateurs de comparaison (`=`, `!=`, `<>`, `>`, `<`, `>=`, `<=`).
- **`chunk` / `chunkById` respectent `limit()`** (nombre total de lignes parcourues) ; `chunk` part de
  `offset()`, `chunkById` refuse `offset()`. `paginate` leve une erreur quand la page ferait deborder
  l'`OFFSET`.
- **Identifiants** : un nom avec un segment vide (`a..b`, `.a`, `a.`) est refuse (`Invalid SQL identifier`).
- **Types de champs** : un type inconnu (`"int"`, `"text"`...) leve une erreur des `ORM.model()` au
  lieu de desactiver la verification du champ. Types acceptes : `string`, `number`, `boolean`, `json`,
  `auto`, `date`, `datetime`, `timestamp`.
- **`belongsToMany` exige `foreignKey` et `otherKey`** (en plus de `pivot`) : sans l'un d'eux, la
  definition leve une erreur (avant, la cle manquante produisait un SQL invalide).
- **Soft delete et ecritures de classe.** Sur un modele `softDelete`, `update` / `updateWhere`,
  `increment` / `decrement` et `delete` (le soft delete lui-meme) ajoutent `deleted_at IS NULL` : une
  ligne deja supprimee n'est plus modifiee, et garde sa date de suppression. Un `where` qui contient
  `deleted_at` vise les lignes supprimees volontairement, sans filtre ajoute. `restore` vise toujours
  les lignes supprimees ; `forceDelete` est inchange.
- **Colonnes gerees refusees dans les donnees.** `create`, `createMany`, `createWith`, `upsert`,
  `update` / `updateWhere` et `instance:update` levent une erreur si les donnees contiennent
  `deleted_at` (utilise `delete()` / `restore()`), ou `created_at` / `updated_at` sur un modele
  `timestamps`, sauf avec la nouvelle option de modele `allowManagedColumns = true` (imports). Les
  hooks `before*` peuvent toujours les fixer, et l'ORM les remplit toujours. `instance:update` garde
  maintenant un `updated_at` fixe (par un hook ou avec `allowManagedColumns`), comme `Model.update`,
  au lieu de l'ecraser.
- **Ecritures et `refresh()` d'une instance** : elles exigent la valeur de la cle primaire (une instance
  lue par un `:select()` sans la cle leve une erreur claire au lieu d'envoyer un `UPDATE ... WHERE` invalide).
- **Migrations par ressource.** `orvex_migrations` gagne une colonne `resource` (ajoutee
  automatiquement). `rollback()` n'annule que le dernier lot **de la ressource qui l'appelle**, et
  seulement les migrations qu'elle liste. Les noms de migration sont uniques sur toute la base : un
  nom deja enregistre par une autre ressource leve une erreur avant toute execution (avant, la
  migration etait ignoree en silence). Prefixe tes noms avec le nom de ta ressource. Les valeurs
  `DEFAULT` d'une colonne n'acceptent que des chaines, booleens et nombres finis.
- **Studio : token verifie.** Un `orvex_studio_token` trop court ou trop peu aleatoire (moins de 32
  caracteres, moins de 10 caracteres differents ou moins d'environ 128 bits) fait refuser le demarrage
  (avant, toute chaine de 32 caracteres etait acceptee). Genere-le avec `openssl rand -hex 32`. Sans
  `/dev/urandom` (Windows), le token doit etre configure.
- **Studio : valeurs scalaires.** Les ecritures n'acceptent que des chaines, nombres, booleens ou
  `null` pour les colonnes et la cle primaire ; un objet ou un tableau JSON recoit un `422`.
- **Drivers personnalises sans `:transaction()`** : les transactions sont refusees (erreur) au lieu de
  s'executer requete par requete sans atomicite. Pour garder l'ancien comportement :
  `OrvexAdapter.new(driver, { allowNonAtomicTransactions = true })`.
- **mysql-async** : une lecture pour laquelle mysql-async retourne `nil` (requete en echec) leve une
  erreur au lieu de retourner une liste vide.

### Ajouts

- `lib/types/orvexorm.d.lua` : definitions LuaLS (`---@meta`) de toutes les methodes des modeles,
  des hooks, des options de `find`, du resultat de `paginate`, des options et statistiques du cache
  et du contrat d'un driver. `OrvexORM.transaction` est declare avec ses deux formes (`---@overload`).
- Hooks des ecritures de classe : `beforeBulkUpdate(data, where)`, `afterBulkUpdate(data, where, affected)`,
  `beforeBulkDelete(where)`, `afterBulkDelete(where, affected)`, `beforeUpsert(data)`,
  `afterUpsert(data)`, `afterBulkCreate(rows)`. La liste est exposee dans `OrvexModelFactory.HOOK_EVENTS`.
- `Builder:chunkById(size, callback, column?)` : parcours par lots en pagination keyset.
- `Builder:whereColumn(a, op?, b)` et `Builder:clone()` documentes.
- `instance:getAttribute(name)`.
- `ORM.op(operateur, valeur)` / `OrvexBuilder.op` : conditions avec operateur dans une table.
- `OrvexAdapter.new(driver, opts?)` et son option `allowNonAtomicTransactions`.
- Option de modele `allowManagedColumns` (voir [Changements cassants](#changements-cassants)).
- `OrvexORM.op` et `OrvexOpMarker` declares dans `lib/types/orvexorm.d.lua`.
- `OrvexMigration.migrate(migrations, adapter, resource?)` / `rollback(...)` : nom de ressource
  explicite (defaut : `GetCurrentResourceName()`).
- Cache : option `maxRows` de `OrvexCache.new` (defaut 5000, y compris pour le cache global) : un
  resultat plus grand n'est pas mis en cache.
- Cache : options `maxEntries` et `sweepInterval` de `OrvexCache.new`, 4e argument `tables` de
  `cache:set`, `cache:purgeExpired()`, champ `maxEntries` de `stats()` / `OrvexORM.cacheStats()`.
- Studio : convar `orvex_studio_allow` (adresses, plages IPv4 CIDR, `*`), conseil de tunnel SSH
  dans la banniere, nonce CSP par chargement.
- CI : workflow `test.yml` (luacheck + toutes les suites `tests/test_*.lua`), lance aussi avant
  chaque release ; `.luacheckrc`.
- `CHANGELOG.md`.

### Changements

- **Valeurs de retour** : `update`, `updateWhere`, `delete`, `deleteWhere`, `forceDelete`, `restore`,
  `increment`, `decrement` (classe et instance) retournent le **nombre de lignes touchees**
  (`0` = rien n'a change) au lieu de `true`. Un nombre restant vrai en Lua, `if User.update(...) then`
  continue de fonctionner.
- **Erreurs** : les erreurs d'utilisation (where manquant, validation, `findOrFail`, `restore` sans
  soft delete...) pointent vers la ligne de l'appelant. Quand plusieurs champs sont invalides, c'est
  toujours le premier dans l'ordre alphabetique qui est signale.
- **Validation** : `created_at` / `updated_at` (avec `timestamps`) et `deleted_at` (avec
  `softDelete`) sont acceptes sans etre declares dans `fields`.
- `create`, `createMany`, `upsert`, `update` et les hooks `before*` travaillent sur une copie : la
  table de l'appelant n'est plus modifiee.
- `find()` / `findAll()` acceptent un `where` absent ; `find` ajoute `LIMIT 1`.
- Tous les identifiants SQL generes sont entoures de backticks : les colonnes `group`, `key`,
  `order`... fonctionnent.
- `Model.sync()` ajoute une cle primaire `INT UNSIGNED NOT NULL AUTO_INCREMENT` quand elle n'est pas
  declaree dans `fields`.
- `SchemaBuilder` execute ses requetes dans l'ordre d'appel ; plusieurs `table()` s'additionnent ;
  `t:index`, `t:unique` et `t:foreignKey` fonctionnent dans `table()`.
- `createWith` valide toutes les lignes d'abord, insere les enfants en `INSERT` multi-lignes dans une
  seule transaction, et supprime les lignes deja creees en cas d'echec avant de lever l'erreur.
- L'eager loading `belongsToMany` charge tous les parents en une seule requete.
- `findOpts.select` accepte aussi une chaine de noms separes par des virgules (`"name, money"`) ;
  une valeur qui n'est ni une chaine ni un tableau leve une erreur (avant, une chaine etait ignoree
  en silence et seule la cle primaire etait lue).
- Si une suppression de compensation de `createWith` echoue, l'erreur levee le dit et liste les
  lignes restees en base.
- `:select()` et `:groupBy()` gardent tels quels `NULL`, `TRUE`, `FALSE`, `DEFAULT`,
  `CURRENT_TIMESTAMP`, `CURRENT_DATE`, `CURRENT_TIME`, `CURRENT_USER`, `LOCALTIME` et
  `LOCALTIMESTAMP` au lieu de les entourer de backticks comme des colonnes.
- La version de la documentation est lue dans `fxmanifest.lua`. La release verifie que la version
  de `fxmanifest.lua` (et une section du `CHANGELOG.md`) correspond au tag au lieu de la reecrire.
- Tests : `tests/test_standalone.lua` est decoupe en suites par module (`test_query`, `test_utils`,
  `test_builder_sql`, `test_model_crud`, `test_model_query`, `test_model_hooks_scopes`,
  `test_relations`, `test_transaction`, `test_model_cache`, `test_migration_schema`,
  `test_orm_helpers`) qui partagent `tests/support/fivem_mock.lua` et `tests/support/harness.lua`.
- CI : `bun run check:i18n` tourne avant chaque deploiement de la documentation, et un workflow
  `docs-check.yml` (i18n, typecheck, build) tourne sur les pull requests qui touchent `docs/`.
- Driver oxmysql global : utilise les formes `.await`, donc une erreur SQL leve une erreur Lua au
  lieu de bloquer le thread. Un appel hors thread leve un message explicite
  (`database calls yield and must run inside Citizen.CreateThread...`).
- mysql-async est detecte via `exports['mysql-async']` (avant, seulement via un global `MySQL` que
  le manifest ne chargeait pas). oxmysql gagne si les deux sont demarres.
- `exports.orvexorm:lib()` affiche un avertissement au premier appel (les exports perdent les
  metatables).
- `ORM.version` est lu dans le `fxmanifest.lua` d'orvexorm.
- Studio : la limite de requetes passe avant les autres controles, et les refus (limite, verrouillage)
  sont journalises une fois par fenetre au lieu d'une fois par requete.
- `createMany` avec des lignes aux jeux de cles differents fait un `INSERT` par jeu de cles, dans une
  seule transaction.
- Une colonne `json` au contenu invalide est lue comme la chaine brute, avec un avertissement qui nomme
  le champ (avant, chaque lecture de la ligne levait une erreur).
- Cache : l'invalidation reconnait les noms qualifies ou entre backticks (`` `users` ``, `db.users`) ;
  une lecture avec une liste de tables separees par des virgules (`FROM a, b`) est invalidee par toute
  ecriture ; les parametres flottants sont gardes sans perte dans la cle.
- mysql-async : les requetes `WITH`, `DESC` et `(SELECT ...)` entre parentheses passent par `fetchAll`
  (lectures).
- Migrations : l'ecriture et la suppression des lignes de `orvex_migrations` sont verifiees (une
  migration appliquee mais non enregistree leve une erreur).
- Logger : les caracteres de controle et les codes couleur FiveM `^0`-`^9` des donnees journalisees
  sont echappes.
- Studio : sous l'URL (qui contient le token), la console avertit qu'elle peut etre recopiee dans
  txAdmin ou des fichiers de log, et qu'il faut arreter le Studio apres usage.
- Transactions non atomiques (`allowNonAtomicTransactions`) : quand une requete echoue apres
  d'autres deja appliquees, `adapter:transaction()` le signale (2e valeur de retour) et la
  transaction invalide quand meme le cache des tables touchees (avant, le cache pouvait servir des
  lignes perimees).
- `createMany` avec plusieurs jeux de cles invalide le cache via sa transaction, une fois validee.
- Studio : la console rappelle que la liste d'autorisation et le verrouillage utilisent l'adresse TCP
  (derriere un reverse proxy sur la meme machine, tous les clients sont `127.0.0.1`). Sans
  `/dev/urandom`, le nonce CSP utilise `math.random` et un avertissement s'affiche.
- CI : une release n'est publiee que pour un tag pointant sur un commit de `main` ; le deploiement de
  la documentation ne part que de `main`, et seul le job de deploiement a les droits Pages.

### Corrections

- **Securite**
  - Studio : XSS stockee dans la fenetre d'edition (une valeur de ligne pouvait executer du script).
  - `Builder:limit()` / `offset()` validaient mal leurs valeurs (concatenees au SQL).
  - `after()` / `before()` acceptaient une direction arbitraire dans `ORDER BY`.
  - `findOpts.select` concatenait des noms de colonnes non valides.
  - Migrations : les valeurs `DEFAULT` et `ENUM` n'echappaient pas les backslashes ; une valeur
    finissant par `\'` sortait du litteral SQL.
  - Studio : encodeur JSON invalide sur les caracteres de controle et `NaN`.
  - Une table envoyee par un client a la place d'une valeur (`{ "LIKE", "%" }`, `{ ">", 0 }`) etait lue
    comme un operateur : `User.find({ identifier = payload })` pouvait renvoyer n'importe quelle ligne.
    Une table liee en parametre pouvait aussi etre developpee par le driver.
  - Une requete de modele avec jointure pouvait recevoir l'`id` de la table jointe : les ecritures de
    l'instance visaient une autre ligne.
  - Studio : les ecritures acceptaient des objets et tableaux JSON comme valeurs.
  - Studio : quand les tables de verrouillage atteignaient 2048 adresses, elles etaient videes d'un
    coup (levant les verrouillages en cours) ; les entrees expirees puis les plus anciennes sont
    maintenant evincees en premier.
  - Logger : une valeur journalisee pouvait injecter des sequences de controle ou des couleurs dans la
    console.
  - Migrations : un `DEFAULT` table (avec `__tostring`), `NaN` ou infini etait insere tel quel dans le DDL.
  - CI : les sujets de commit etaient developpes par le shell dans les notes de release.
- **SQL et requetes**
  - `orWhere` n'etait pas groupe : il contournait le filtre du soft delete et la correlation de
    `whereHas`.
  - `where(field, op, value)` ignorait `IN` / `NOT IN` / `BETWEEN` / `IS` ; une valeur `nil`
    devenait une condition fausse (elle leve maintenant une erreur).
  - Une relation avec une cle `nil` faisait une requete sans `WHERE` et renvoyait une ligne au hasard.
  - `Model.find` avec un operateur, sur un modele sans soft delete, liait une table Lua en parametre.
  - `whereHas` / `countByRelation` comptaient les lignes liees supprimees en douceur ; `whereHas` sur
    `belongsToMany` appliquait la callback a la table pivot.
  - `count()` et `paginate()` donnaient un total faux avec `distinct`, `groupBy` ou `limit`/`offset`.
    Avec la selection `*` et une jointure, la table derivee du comptage selectionne `table.*` ou
    les colonnes du `groupBy` (sinon MySQL refuse les noms de colonnes en double).
  - `offset()` sans `limit()`, et `pluck()` sur une colonne qualifiee, generaient un SQL invalide.
  - `restore()` etait duplique et generait un SQL invalide avec un `where` vide.
  - `instance:update()` de la cle primaire laissait l'ancienne valeur dans le `WHERE` suivant.
  - `createMany` avec des lignes aux cles differentes perdait les colonnes absentes de la premiere ligne.
  - `whereColumn` avec `IN`, `BETWEEN` ou `IS` generait un SQL invalide.
  - Un tableau `IN` avec un trou `nil` decalait tous les parametres suivants.
  - `chunk` / `chunkById` ignoraient `limit()` ; `paginate` avec une page enorme donnait un `OFFSET`
    negatif.
  - Un identifiant avec un segment vide (`a..b`) generait des backticks vides.
  - Un type de champ inconnu desactivait la validation du champ en silence.
- **Transactions et drivers**
  - Les ecritures faites par `OrvexORM.transaction`, `raw` et `rawExec` n'invalidaient pas le cache.
  - La transaction mysql-async envoyait `BEGIN` / `COMMIT` sur des connexions differentes du pool :
    elle n'etait pas atomique et son echec ne pouvait pas etre detecte.
  - Un driver sans `:transaction()` executait les transactions sans atomicite, sans avertissement.
  - mysql-async : `WITH`, `DESC` et `(SELECT ...)` etaient envoyes comme des ecritures ; une lecture en
    echec etait prise pour un resultat vide (et mise en cache).
- **Studio**
  - Les ecritures (ajout, modification, suppression) ne fonctionnaient pas sur un vrai FXServer : le
    corps etait lu dans `req.body`, qui n'existe pas. Il est maintenant lu via `req.setDataHandler`,
    apres la verification du token, et limite a 1 Mio.
- **Migrations**
  - `SchemaBuilder:table()` ecrasait les appels precedents et ignorait index et cles etrangeres.
  - `Model.sync()` generait un DDL invalide quand la cle primaire n'etait pas declaree.
  - Une migration en echec etait enregistree comme appliquee.
  - `rollback()` annulait le dernier lot de n'importe quelle ressource ; une migration d'une ressource
    portant le meme nom qu'une migration d'une autre ressource etait ignoree en silence.
  - L'echec de l'ecriture d'une ligne de suivi passait inapercu.
- **Cache**
  - Collisions de cles : une requete pouvait recevoir les lignes en cache d'une autre
    (`{"x:y","z"}` et `{"x","y:z"}`, ou `1` et `"1"`).
  - `invalidateTable` parcourait tout le cache a chaque ecriture et vidait aussi les tables au nom
    proche (`users` vidait `users_logs`).
  - Le cache n'avait pas de taille maximale et ne purgeait pas les entrees expirees.
  - Une ecriture sur `` `users` `` ou `db.users` n'invalidait pas les lectures de `users` ; une lecture
    `FROM a, b` n'etait pas invalidee par une ecriture sur `b`.
  - Deux flottants proches (au-dela de 14 chiffres significatifs) partageaient une entree.
  - Un resultat de taille illimitee pouvait occuper le cache.
- **JSON** : une colonne `json` invalide en base rendait sa ligne illisible.
- **Hooks** : les ecritures de classe (`update`, `delete`, `upsert`, `createMany`) ne declenchaient
  aucun hook.
- **Performance** : `find` sans `LIMIT 1`, eager loading `belongsToMany` en N+1, `createWith` en une
  requete par enfant, instances qui copiaient 9 champs internes par ligne, `chunk` en cout
  quadratique (utilise `chunkById`).
- **Documentation**
  - Le README indiquait `@orvexorm/import.lua` au lieu de `@orvexorm/lib/import.lua`.
  - Les exemples de transfert d'argent et d'achat de vehicule pouvaient creer de l'argent : ils
    utilisent maintenant une requete conditionnelle unique ou un `SELECT ... FOR UPDATE`, avec
    verification du resultat.
  - La detection du driver, le rejet des colonnes inconnues, les options de `ORM.model`, le contrat
    d'un driver pour `setAdapter`, l'ordre des arguments et le fonctionnement asynchrone (section
    *Async et threads*) sont documentes.
  - La page Auto-completion ne promet plus de completions inexistantes.

### Limites connues

- Sous mysql-async, une erreur SQL hors transaction peut ne jamais rappeler le callback : le thread
  attend indefiniment (limite de l'API mysql-async). Prefere oxmysql.
- Selon le driver, l'echec d'une transaction peut lever une erreur au lieu de retourner `false`
  (l'export `transactionSync` d'oxmysql).
- MySQL ne peut pas annuler le DDL : les requetes d'une migration executees avant l'echec restent
  appliquees.
- Le cache est propre a chaque ressource : une ecriture d'une autre ressource ne l'invalide pas.
- `createWith` n'est pas entierement atomique : le parent et les lignes `belongsToMany` sont crees
  avant la transaction des enfants et retires par des `DELETE` de compensation en cas d'echec.
- Deux ressources qui lancent `migrate()` au meme instant peuvent partager un numero de lot (sans
  consequence : `rollback()` ne touche que les lignes de la ressource appelante).
- Studio : la liste d'autorisation et le verrouillage utilisent l'adresse TCP du pair ; derriere un
  reverse proxy sur la meme machine, tous les clients sont `127.0.0.1`. Sans `/dev/urandom`
  (Windows), le nonce CSP est plus faible (le token, lui, doit etre configure).
- Studio : l'URL affichee dans la console contient le token ; la console peut etre recopiee dans
  txAdmin ou des fichiers de log.
- Un modele avec son propre cache (`opts.cache`) qui joint une autre table range le resultat dans son
  cache : une ecriture faite via le modele de la table jointe ne le purge pas (voir
  [Un cache par modele](docs/docs/guides/cache.md#un-cache-par-modele)).
- `findOrCreate` / `updateOrCreate` ne voient pas les lignes supprimees en douceur : une ligne
  supprimee qui correspond donne une nouvelle ligne. Pose un index unique sur les colonnes du `where`.
- `createWith` traite toute cle portant le nom d'une relation comme une ecriture imbriquee : ne lui
  passe jamais une table venue d'un client sans la filtrer.
- Les transactions non atomiques (`allowNonAtomicTransactions`) gardent en base les requetes passees
  avant l'echec (seul le cache est invalide).
- CI : luacheck est installe via `luarocks install` sans verification d'empreinte (la version est
  epinglee, pas son contenu).

## [1.2.1]

- Mutualisation de l'execution et de la gestion des erreurs SQL du Studio.
- Centralisation des conventions de cles et de tables pour les relations.
- Suppression de traitements dupliques lors du comptage des relations.

## [1.2.0]

- Les lectures via l'API globale oxmysql utilisent `MySQL.query` (et non `MySQL.prepare`, qui
  pouvait aplatir le resultat) ; sous mysql-async, `create()` recupere le vrai `insertId`.
- Eager loading batche : `findAll(where, { include = {...} })` charge chaque relation en une requete.
- `countByRelation` en une seule requete `GROUP BY`.
- `instance:toTable()`, `instance:refresh()`, `Model.all()`, `Builder:whereRaw()`,
  `OrvexORM.cacheStats()`.
- Cache : les lignes en cache ne sont plus modifiees par le decodage JSON ; compteurs hits/misses.
- `upsert` avec `timestamps = true` ne reecrit plus `created_at`.
- Studio : anti-bruteforce par IP, compatible mysql-async.
