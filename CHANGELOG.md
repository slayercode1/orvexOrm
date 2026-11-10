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

### Corrections

- **Securite**
  - Studio : XSS stockee dans la fenetre d'edition (une valeur de ligne pouvait executer du script).
  - `Builder:limit()` / `offset()` validaient mal leurs valeurs (concatenees au SQL).
  - `after()` / `before()` acceptaient une direction arbitraire dans `ORDER BY`.
  - `findOpts.select` concatenait des noms de colonnes non valides.
  - Migrations : les valeurs `DEFAULT` et `ENUM` n'echappaient pas les backslashes ; une valeur
    finissant par `\'` sortait du litteral SQL.
  - Studio : encodeur JSON invalide sur les caracteres de controle et `NaN`.
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
- **Transactions et drivers**
  - Les ecritures faites par `OrvexORM.transaction`, `raw` et `rawExec` n'invalidaient pas le cache.
  - La transaction mysql-async envoyait `BEGIN` / `COMMIT` sur des connexions differentes du pool :
    elle n'etait pas atomique et son echec ne pouvait pas etre detecte.
- **Migrations**
  - `SchemaBuilder:table()` ecrasait les appels precedents et ignorait index et cles etrangeres.
  - `Model.sync()` generait un DDL invalide quand la cle primaire n'etait pas declaree.
  - Une migration en echec etait enregistree comme appliquee.
- **Cache**
  - Collisions de cles : une requete pouvait recevoir les lignes en cache d'une autre
    (`{"x:y","z"}` et `{"x","y:z"}`, ou `1` et `"1"`).
  - `invalidateTable` parcourait tout le cache a chaque ecriture et vidait aussi les tables au nom
    proche (`users` vidait `users_logs`).
  - Le cache n'avait pas de taille maximale et ne purgeait pas les entrees expirees.
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
