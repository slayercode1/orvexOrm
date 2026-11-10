-- core/model/querying.lua
-- Query entry points of a model class: builders (with the soft delete
-- filter), scopes, aggregates and the small read shortcuts built on them.

local Builder = OrvexBuilder or require("core.builder")
local Helpers = OrvexHelpers or require("utils.helpers")

local ensure = Helpers.ensure

---@class OrvexModelQuerying
local Querying = {}

--- `M.scope(name, fn)`, `M.scoped(name)` and the scopes given in the options.
--- Installed before the other methods, as before: a scope named like a
--- built-in method is replaced by that method.
---@param M OrvexModel
---@param initial? table<string, fun(builder: OrvexBuilder)> `opts.scopes`
function Querying.installScopes(M, initial)
    local scopes = {} ---@type table<string, function>

    ---@param name string
    ---@param fn fun(builder: OrvexBuilder)
    function M.scope(name, fn)
        scopes[name] = fn
        M[name] = function()
            local b = M.query()
            fn(b)
            return b
        end
    end

    ---@param name string
    ---@return OrvexBuilder
    function M.scoped(name)
        local fn = scopes[name]
        ensure(fn, ("Unknown scope '%s'"):format(name))
        local b = M.query()
        fn(b)
        return b
    end

    if initial then
        for name, fn in pairs(initial) do
            M.scope(name, fn)
        end
    end
end

---@param M OrvexModel
---@param where? table<string, any>
---@return OrvexBuilder
local function filtered(M, where)
    local b = M.query()
    if where then b:where(where) end
    return b
end

---@param M OrvexModel
---@param ctx OrvexInstanceContext
function Querying.install(M, ctx)
    local tableName, adapter, cache = ctx.tableName, ctx.adapter, ctx.cache

    ---@return OrvexBuilder
    function M.query()
        local b = Builder.new(tableName, adapter, M._wrapRow, cache)
        if ctx.softDelete then
            b:constrain(function(q) q:whereNull("deleted_at") end)
        end
        return b
    end

    ---@return OrvexBuilder
    function M.withTrashed()
        return Builder.new(tableName, adapter, M._wrapRow, cache)
    end

    ---@return OrvexBuilder
    function M.onlyTrashed()
        local b = Builder.new(tableName, adapter, M._wrapRow, cache)
        b:constrain(function(q) q:whereNotNull("deleted_at") end)
        return b
    end

    -- Argument order: count(where?) takes the clause first, while
    -- sum / avg / min / max(column, where?) take the column first.
    function M.count(where)
        return filtered(M, where):count()
    end
    for _, agg in ipairs({ "sum", "avg", "min", "max" }) do
        M[agg] = function(column, where)
            local b = filtered(M, where)
            return b[agg](b, column)
        end
    end

    ---@param where? table<string, any>
    ---@return OrvexInstance|nil
    function M.first(where)
        return filtered(M, where):first()
    end

    ---@param where table<string, any>
    ---@return boolean
    function M.exists(where)
        return filtered(M, where):exists()
    end

    ---@param column string
    ---@param where? table<string, any>
    ---@return any[]
    function M.pluck(column, where)
        return filtered(M, where):pluck(column)
    end
end

OrvexModelQuerying = Querying
return Querying
