---@meta
-- lib/types/orvexorm.d.lua
-- LuaLS definitions for the public OrvexORM API. Never loaded at runtime
-- (not listed in fxmanifest.lua): it only feeds auto-completion and type
-- checking. Point `workspace.library` of your resource's .luarc.json at the
-- orvexorm folder to use it.
--
-- Builder, Instance and Transaction methods are declared on their classes in
-- core/builder.lua, core/model/instance.lua and core/transaction.lua. The
-- model class is assembled at runtime by several modules (core/model/*.lua),
-- which LuaLS cannot follow, so its methods are declared here.

-- ─── Model options ─────────────────────────────────────────────────

--- Inline hooks given to `ORM.model(..., { hooks = { ... } })`: one function
--- per event. Instance hooks receive the instance; class-level (bulk) writes
--- receive the data and the where clause, as no instance is loaded.
---@class OrvexHookMap
---@field beforeCreate? fun(data: table<string, any>) create, createMany (per row), findOrCreate, updateOrCreate; may modify `data`
---@field afterCreate? fun(instance: OrvexInstance) create, findOrCreate, updateOrCreate
---@field afterBulkCreate? fun(rows: table[]) createMany
---@field beforeUpdate? fun(instance: OrvexInstance, data: table<string, any>) Instance:update, updateOrCreate; may modify `data`
---@field afterUpdate? fun(instance: OrvexInstance) Instance:update, updateOrCreate
---@field beforeDelete? fun(instance: OrvexInstance) Instance:delete, Instance:forceDelete
---@field afterDelete? fun(instance: OrvexInstance) Instance:delete, Instance:forceDelete
---@field beforeBulkUpdate? fun(data: table<string, any>, where: table<string, any>) Model.update, Model.updateWhere; may modify `data`
---@field afterBulkUpdate? fun(data: table<string, any>, where: table<string, any>, affected: integer) Model.update, Model.updateWhere
---@field beforeBulkDelete? fun(where: table<string, any>) Model.delete, Model.deleteWhere, Model.forceDelete
---@field afterBulkDelete? fun(where: table<string, any>, affected: integer) Model.delete, Model.deleteWhere, Model.forceDelete
---@field beforeUpsert? fun(data: table<string, any>) Model.upsert; may modify `data`
---@field afterUpsert? fun(data: table<string, any>) Model.upsert

---@alias OrvexHookEvent "beforeCreate"|"afterCreate"|"afterBulkCreate"|"beforeUpdate"|"afterUpdate"|"beforeDelete"|"afterDelete"|"beforeBulkUpdate"|"afterBulkUpdate"|"beforeBulkDelete"|"afterBulkDelete"|"beforeUpsert"|"afterUpsert"

--- Options of `Model.find` / `Model.findAll` / `Model.all`.
---@class OrvexFindOpts
---@field select? string[]|string column names (plain identifiers), or a comma-separated string; the primary key is always added
---@field include? string[] relation names to eager load (one query per relation)

---@class OrvexPaginateResult
---@field data OrvexInstance[]
---@field total integer
---@field page integer
---@field perPage integer
---@field lastPage integer

---@class OrvexRelationCount
---@field instance OrvexInstance also carries the count in `_count_<relation>`
---@field count integer

---@alias OrvexWhere table<string, any|OrvexWhereValue> `{ column = value }` or `{ column = { operator, value } }`

-- ─── Model class ───────────────────────────────────────────────────
-- Write methods return the number of rows the driver reports as affected
-- (0: nothing matched). Misuse (missing where, invalid data) raises an error
-- located at the caller's line.

---@class OrvexModel
---@field create fun(data: table<string, any>): OrvexInstance
---@field createMany fun(rows: table[]): boolean one multi-row INSERT
---@field createWith fun(data: table<string, any>): OrvexInstance creates the row and its nested hasOne / hasMany / belongsToMany rows
---@field upsert fun(data: table<string, any>): boolean INSERT ... ON DUPLICATE KEY UPDATE
---@field find fun(where?: OrvexWhere, opts?: OrvexFindOpts): OrvexInstance|nil first matching row (LIMIT 1)
---@field findAll fun(where?: OrvexWhere, opts?: OrvexFindOpts): OrvexInstance[]
---@field all fun(opts?: OrvexFindOpts): OrvexInstance[]
---@field findOrFail fun(where: OrvexWhere, opts?: OrvexFindOpts): OrvexInstance raises when nothing matches
---@field findOrCreate fun(where: table<string, any>, defaults?: table<string, any>): OrvexInstance, boolean instance, created
---@field updateOrCreate fun(where: table<string, any>, data: table<string, any>): OrvexInstance, boolean instance, created
---@field update fun(data: table<string, any>, where: table<string, any>): integer data first; affected rows
---@field updateWhere fun(where: table<string, any>, data: table<string, any>): integer where first (alias of update); affected rows
---@field delete fun(where: table<string, any>): integer soft delete when enabled; affected rows
---@field deleteWhere fun(where: table<string, any>): integer alias of delete; affected rows
---@field forceDelete fun(where: table<string, any>): integer always a real DELETE; affected rows
---@field restore fun(where: table<string, any>): integer requires softDelete; affected rows
---@field increment fun(column: string, amount: number, where: table<string, any>): integer amount required here; affected rows
---@field decrement fun(column: string, amount: number, where: table<string, any>): integer amount required here; affected rows
---@field first fun(where?: OrvexWhere): OrvexInstance|nil
---@field exists fun(where?: OrvexWhere): boolean
---@field pluck fun(column: string, where?: OrvexWhere): any[]
---@field count fun(where?: OrvexWhere): integer where first
---@field sum fun(column: string, where?: OrvexWhere): number column first
---@field avg fun(column: string, where?: OrvexWhere): number column first
---@field min fun(column: string, where?: OrvexWhere): any column first
---@field max fun(column: string, where?: OrvexWhere): any column first
---@field query fun(): OrvexBuilder excludes soft-deleted rows when softDelete is on
---@field withTrashed fun(): OrvexBuilder
---@field onlyTrashed fun(): OrvexBuilder
---@field scope fun(name: string, fn: fun(builder: OrvexBuilder)) also installs `Model[name]()`
---@field scoped fun(name: string): OrvexBuilder
---@field whereHas fun(relationName: string, callback?: fun(builder: OrvexBuilder)): OrvexBuilder
---@field countByRelation fun(relationName: string, where?: OrvexWhere): OrvexRelationCount[]
---@field hasOne fun(name: string, relatedModel: OrvexModel, opts: OrvexHasOneOpts)
---@field hasMany fun(name: string, relatedModel: OrvexModel, opts: OrvexHasManyOpts)
---@field belongsTo fun(name: string, relatedModel: OrvexModel, opts: OrvexBelongsToOpts)
---@field belongsToMany fun(name: string, relatedModel: OrvexModel, opts: OrvexBelongsToManyOpts)
---@field applyRelations fun() runs the deferred `opts.relations` callback
---@field hook fun(event: OrvexHookEvent, fn: function)
---@field beforeCreate fun(fn: fun(data: table<string, any>))
---@field afterCreate fun(fn: fun(instance: OrvexInstance))
---@field afterBulkCreate fun(fn: fun(rows: table[]))
---@field beforeUpdate fun(fn: fun(instance: OrvexInstance, data: table<string, any>))
---@field afterUpdate fun(fn: fun(instance: OrvexInstance))
---@field beforeDelete fun(fn: fun(instance: OrvexInstance))
---@field afterDelete fun(fn: fun(instance: OrvexInstance))
---@field beforeBulkUpdate fun(fn: fun(data: table<string, any>, where: table<string, any>))
---@field afterBulkUpdate fun(fn: fun(data: table<string, any>, where: table<string, any>, affected: integer))
---@field beforeBulkDelete fun(fn: fun(where: table<string, any>))
---@field afterBulkDelete fun(fn: fun(where: table<string, any>, affected: integer))
---@field beforeUpsert fun(fn: fun(data: table<string, any>))
---@field afterUpsert fun(fn: fun(data: table<string, any>))
---@field flushCache fun() drops this model's table from its cache
---@field sync fun() CREATE TABLE IF NOT EXISTS from the schema (yields)
---@field [string] fun(...): OrvexBuilder scopes declared with `scope()` or `opts.scopes`

-- ─── Cache ─────────────────────────────────────────────────────────

---@class OrvexCacheOpts
---@field ttl? number seconds, default 60
---@field enabled? boolean default true for `OrvexCache.new`
---@field maxEntries? integer default 1000; least recently used entries are evicted
---@field sweepInterval? number seconds between purges of expired entries, default ttl (min 1)

---@class OrvexCacheStats
---@field hits integer
---@field misses integer
---@field hitRate number hits / (hits + misses)
---@field entries integer
---@field maxEntries integer

-- ─── Driver contract ───────────────────────────────────────────────

--- What `OrvexAdapter.new(driver)` expects. Every method may yield: call
--- them from a thread (Citizen.CreateThread, event or command handler).
---@class OrvexDriver
---@field execute fun(self: OrvexDriver, query: string, params: any[]): table[] rows of a SELECT
---@field scalar fun(self: OrvexDriver, query: string, params: any[]): any insert id for INSERT, affected rows (number or { affectedRows = n }) for UPDATE / DELETE
---@field transaction? fun(self: OrvexDriver, queries: OrvexTransactionQuery[]): boolean atomic; without it the adapter runs the queries one by one (NOT atomic)
