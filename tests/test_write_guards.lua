-- tests/test_write_guards.lua
-- Class writes on soft delete models leave trashed rows alone, callers
-- cannot set the ORM-managed columns, and createMany invalidates the
-- cache through its transaction.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_write_guards.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, txLog = Mock.log, Mock.txLog
local reset = Mock.reset

local ORM = require("core.orm")
local CacheLib = require("utils.cache")

---@param params any[]
---@param value any
---@return boolean
local function hasParam(params, value)
    for _, param in ipairs(params or {}) do
        if param == value then return true end
    end
    return false
end

local OLD_STAMP = "2020-01-01 00:00:00"

-- ─── Soft delete scope ─────────────────────────────────────────────

T.section("Class writes skip trashed rows")

local Soft = ORM.model("w_soft", { id = "number", name = "string", score = "number" }, { softDelete = true })
local Plain = ORM.model("w_plain", { id = "number", name = "string" })

reset()
Soft.update({ name = "x" }, { id = 1 })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `name` = ? WHERE `id` = ? AND `deleted_at` IS NULL",
    "update only targets rows that are not trashed")

reset()
Soft.updateWhere({ id = 1 }, { name = "x" })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `name` = ? WHERE `id` = ? AND `deleted_at` IS NULL",
    "updateWhere only targets rows that are not trashed")

reset()
Soft.increment("score", 2, { id = 1 })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `score` = `score` + ? WHERE `id` = ? AND `deleted_at` IS NULL",
    "increment only targets rows that are not trashed")

reset()
Soft.decrement("score", 2, { id = 1 })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `score` = `score` - ? WHERE `id` = ? AND `deleted_at` IS NULL",
    "decrement only targets rows that are not trashed")

reset()
Soft.delete({ id = 1 })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `deleted_at` = ? WHERE `id` = ? AND `deleted_at` IS NULL",
    "a soft delete keeps the deleted_at of rows already trashed")

reset()
Soft.restore({ id = 1 })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `deleted_at` = NULL WHERE `id` = ?",
    "restore still targets trashed rows")

reset()
Soft.forceDelete({ id = 1 })
T.eq((dbLog[1] or {}).sql, "DELETE FROM `w_soft` WHERE `id` = ?", "forceDelete is unchanged")

reset()
Soft.update({ name = "x" }, { deleted_at = OLD_STAMP })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_soft` SET `name` = ? WHERE `deleted_at` = ?",
    "an explicit deleted_at condition targets trashed rows on purpose")

reset()
Plain.update({ name = "x" }, { id = 1 })
T.eq((dbLog[1] or {}).sql, "UPDATE `w_plain` SET `name` = ? WHERE `id` = ?",
    "a model without soft delete gets no deleted_at condition")

-- ─── Managed columns ───────────────────────────────────────────────

T.section("Callers cannot set deleted_at")

local Stamped = ORM.model("w_stamped", { id = "number", name = "string" }, { timestamps = true, softDelete = true })

reset()
T.raises(function() Stamped.create({ name = "a", deleted_at = OLD_STAMP }) end,
    "create refuses deleted_at with a hint", "delete()")
T.raises(function() Stamped.createMany({ { name = "a" }, { name = "b", deleted_at = OLD_STAMP } }) end,
    "createMany refuses deleted_at", "deleted_at")
T.raises(function() Stamped.update({ deleted_at = OLD_STAMP }, { id = 1 }) end,
    "update refuses deleted_at with a hint", "restore()")
T.raises(function() Stamped.upsert({ id = 1, deleted_at = OLD_STAMP }) end,
    "upsert refuses deleted_at", "deleted_at")
T.raises(function() Stamped._wrapRow({ id = 1, name = "a" }):update({ deleted_at = OLD_STAMP }) end,
    "Instance:update refuses deleted_at", "deleted_at")
T.eq(#dbLog + #txLog, 0, "nothing reaches the database")

T.section("Callers cannot set timestamps unless the model allows it")

reset()
T.raises(function() Stamped.create({ name = "a", created_at = OLD_STAMP }) end,
    "create refuses created_at and names the option", "allowManagedColumns")
T.raises(function() Stamped.createMany({ { name = "a", updated_at = OLD_STAMP } }) end,
    "createMany refuses updated_at", "allowManagedColumns")
T.raises(function() Stamped.update({ updated_at = OLD_STAMP }, { id = 1 }) end,
    "update refuses updated_at", "allowManagedColumns")
T.raises(function() Stamped.upsert({ id = 1, created_at = OLD_STAMP }) end,
    "upsert refuses created_at", "allowManagedColumns")
T.raises(function() Stamped._wrapRow({ id = 1, name = "a" }):update({ updated_at = OLD_STAMP }) end,
    "Instance:update refuses updated_at", "allowManagedColumns")
T.eq(#dbLog + #txLog, 0, "nothing reaches the database")

local Parent = ORM.model("w_parents", { id = "number", name = "string" })
local Child = ORM.model("w_children", { id = "number", parent_id = "number", name = "string" }, { timestamps = true })
Parent.hasMany("children", Child, { foreignKey = "parent_id" })
reset()
T.raises(function() Parent.createWith({ name = "p", children = { { name = "c", created_at = OLD_STAMP } } }) end,
    "createWith refuses managed columns in nested rows", "allowManagedColumns")
T.eq(#dbLog + #txLog, 0, "the nested rows are checked before the parent is written")

reset()
local stamped = Stamped.create({ name = "a" })
T.eq(type(stamped.created_at), "string", "the ORM still stamps created_at")
T.eq(type(stamped.updated_at), "string", "the ORM still stamps updated_at")

reset()
Stamped.beforeCreate(function(data) data.created_at = OLD_STAMP end)
local hooked = Stamped.create({ name = "b" })
T.eq(hooked.created_at, OLD_STAMP, "a beforeCreate hook may still set created_at")

local Unmanaged = ORM.model("w_unmanaged", { id = "number", created_at = "datetime", deleted_at = "datetime" })
reset()
T.check(pcall(Unmanaged.create, { created_at = OLD_STAMP, deleted_at = OLD_STAMP }),
    "declared columns are plain fields when timestamps and soft delete are off")

T.section("allowManagedColumns = true")

local Imported = ORM.model("w_imported", { id = "number", name = "string" },
    { timestamps = true, softDelete = true, allowManagedColumns = true })

reset()
local imported = Imported.create({ name = "a", created_at = OLD_STAMP, updated_at = OLD_STAMP })
T.eq(imported.created_at, OLD_STAMP, "create keeps the caller's created_at")
T.check(hasParam((dbLog[1] or {}).params, OLD_STAMP), "the caller's timestamp is bound")
T.raises(function() Imported.update({ deleted_at = OLD_STAMP }, { id = 1 }) end,
    "deleted_at stays refused", "restore()")

T.section("Class and instance updates agree on updated_at")

reset()
Imported.update({ name = "x", updated_at = OLD_STAMP }, { id = 1 })
T.check(hasParam((dbLog[1] or {}).params, OLD_STAMP), "class update keeps an allowed updated_at")

reset()
Imported._wrapRow({ id = 1, name = "a" }):update({ name = "x", updated_at = OLD_STAMP })
T.check(hasParam((dbLog[1] or {}).params, OLD_STAMP), "Instance:update keeps an allowed updated_at")

local Touched = ORM.model("w_touched", { id = "number", name = "string" }, { timestamps = true })
Touched.beforeUpdate(function(_, data) data.updated_at = OLD_STAMP end)
Touched.beforeBulkUpdate(function(data) data.updated_at = OLD_STAMP end)

reset()
Touched.update({ name = "x" }, { id = 1 })
T.check(hasParam((dbLog[1] or {}).params, OLD_STAMP), "class update keeps an updated_at set by a hook")

reset()
Touched._wrapRow({ id = 1, name = "a" }):update({ name = "x" })
T.check(hasParam((dbLog[1] or {}).params, OLD_STAMP), "Instance:update keeps an updated_at set by a hook")

-- ─── createMany cache ──────────────────────────────────────────────

T.section("createMany invalidates the cache through its transaction")

local cache = CacheLib.new({ enabled = true })
local Cached = ORM.model("w_cached", { id = "number", name = "string", qty = "number" }, { cache = cache })
local cachedKey = CacheLib.makeKey("SELECT * FROM `w_cached`", {})

reset()
cache:set(cachedKey, { { id = 1 } })
Cached.createMany({ { name = "a", qty = 1 }, { name = "b" } })
T.eq(#txLog, 1, "rows with different key sets are written in one transaction")
local _, hit = cache:get(cachedKey)
T.eq(hit, false, "the committed transaction invalidates the model's table")

T.finish()
