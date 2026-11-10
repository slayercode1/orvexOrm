-- core/model/hooks.lua
-- Lifecycle hooks: registration on a model class and dispatch.
--
-- Instance writes fire the instance hooks. Class-level writes act on a
-- WHERE clause, not on loaded rows, so they fire the bulk hooks with the
-- data and the clause instead of an instance:
--
--   beforeCreate(data)                      create, createMany / createWith (per row), findOrCreate, updateOrCreate
--   afterCreate(instance)                   create, findOrCreate, updateOrCreate
--   afterBulkCreate(rows)                   createMany, createWith (per hasOne / hasMany relation)
--   beforeUpdate(instance, data)            Instance:update, updateOrCreate
--   afterUpdate(instance)                   Instance:update, updateOrCreate
--   beforeDelete(instance)                  Instance:delete, Instance:forceDelete
--   afterDelete(instance)                   Instance:delete, Instance:forceDelete
--   beforeBulkUpdate(data, where)           update, updateWhere
--   afterBulkUpdate(data, where, affected)  update, updateWhere
--   beforeBulkDelete(where)                 delete, deleteWhere, forceDelete
--   afterBulkDelete(where, affected)        delete, deleteWhere, forceDelete
--   beforeUpsert(data)                      upsert
--   afterUpsert(data)                       upsert
--
-- No hook fires for increment / decrement or restore. The nested rows
-- createWith batches fire beforeCreate and afterBulkCreate, not afterCreate:
-- no instance is built for them.
-- `before*` hooks receive a copy of the caller's data and may modify it.

---@class OrvexModelHooks
local Hooks = {}

---@type string[]
Hooks.EVENTS = {
    "beforeCreate", "afterCreate", "afterBulkCreate",
    "beforeUpdate", "afterUpdate", "beforeDelete", "afterDelete",
    "beforeBulkUpdate", "afterBulkUpdate", "beforeBulkDelete", "afterBulkDelete",
    "beforeUpsert", "afterUpsert",
}

---@param hooks table<string, function[]>
---@param event string
---@param ... any
function Hooks.fire(hooks, event, ...)
    if hooks and hooks[event] then
        for _, fn in ipairs(hooks[event]) do fn(...) end
    end
end

--- Adds `M.hook(event, fn)` and one shortcut per event (`M.beforeCreate(fn)`,
--- `M.afterBulkUpdate(fn)`...), then registers the hooks given in the options.
---@param M OrvexModel
---@param hooks table<string, function[]> the model's hook registry
---@param initial? table<string, function> `opts.hooks`
function Hooks.install(M, hooks, initial)
    ---@param event string
    ---@param fn function
    function M.hook(event, fn)
        if not hooks[event] then
            hooks[event] = {}
        end
        hooks[event][#hooks[event] + 1] = fn
    end

    for _, event in ipairs(Hooks.EVENTS) do
        ---@diagnostic disable-next-line: missing-return
        M[event] = function(fn) M.hook(event, fn) end
    end

    if initial then
        for event, fn in pairs(initial) do
            M.hook(event, fn)
        end
    end
end

OrvexModelHooks = Hooks
return Hooks
