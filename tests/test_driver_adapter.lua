-- tests/test_driver_adapter.lua
-- Adapter around a custom driver: delegation and the non-atomic transaction fallback.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_driver_adapter.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local T = require("tests.support.harness")

local Adapter = require("database.adapter")
local Transaction = require("core.transaction")
local CacheLib = require("utils.cache")

--- Driver without :transaction; fails on any query listed in `failing`.
local function plainDriver(failing)
    local driver = { sent = {} }
    function driver:execute(query) self.sent[#self.sent + 1] = query; return {} end
    function driver:scalar(query)
        self.sent[#self.sent + 1] = query
        if failing and failing[query] then error("boom: " .. query) end
        return 1
    end
    return driver
end

local queries = {
    { query = "UPDATE a SET v = 1", values = {} },
    { query = "UPDATE b SET v = 2", values = {} },
}

T.section("adapter: driver with native transaction")

local nativeDriver = plainDriver()
function nativeDriver:transaction(qs) self.native = qs; return true end
T.eq(Adapter.new(nativeDriver):transaction(queries), true, "native transaction result is returned")
T.eq(nativeDriver.native, queries, "queries are handed to the driver's transaction")
T.eq(#nativeDriver.sent, 0, "no query is run one by one")

T.section("adapter: driver without transaction, no opt-in")

local refused = plainDriver()
T.raises(function() Adapter.new(refused):transaction(queries) end,
    "transaction is refused with an error naming the opt-in", "allowNonAtomicTransactions")
T.eq(#refused.sent, 0, "nothing is sent when the transaction is refused")

T.section("adapter: driver without transaction, explicit opt-in")

local optedIn = plainDriver()
local adapter = Adapter.new(optedIn, { allowNonAtomicTransactions = true })
T.eq(adapter:transaction(queries), true, "opt-in through Adapter.new options runs the fallback")
T.eq(#optedIn.sent, 2, "every query runs one by one")

local assigned = plainDriver()
local assignedAdapter = Adapter.new(assigned)
assignedAdapter.allowNonAtomicTransactions = true
T.eq(assignedAdapter:transaction(queries), true, "opt-in by setting the field on the adapter")

local partial = plainDriver({ ["UPDATE b SET v = 2"] = true })
local success, partiallyCommitted = Adapter.new(partial, { allowNonAtomicTransactions = true }):transaction(queries)
T.eq(success, false, "a failing query makes the fallback return false")
T.eq(partiallyCommitted, true, "a failure after the first query is reported as partially committed")
T.eq(#partial.sent, 2, "queries before the failure already ran (not atomic)")

local firstFails = plainDriver({ ["UPDATE a SET v = 1"] = true })
success, partiallyCommitted = Adapter.new(firstFails, { allowNonAtomicTransactions = true }):transaction(queries)
T.eq(success, false, "a failing first query makes the fallback return false")
T.eq(partiallyCommitted, false, "a failure on the first query committed nothing")
T.eq(#firstFails.sent, 1, "the fallback stops at the first failure")

T.section("transaction: partial commit through the non-atomic fallback")

--- Cache holding one SELECT result per table name.
local function cacheOver(tables)
    local cache = CacheLib.new({ enabled = true })
    for _, name in ipairs(tables) do
        cache:set(CacheLib.makeKey("SELECT * FROM " .. name, {}), { { id = 1 } })
    end
    return cache
end

local function isCached(cache, name)
    local _, hit = cache:get(CacheLib.makeKey("SELECT * FROM " .. name, {}))
    return hit
end

local cache = cacheOver({ "a", "b", "c" })
local tx = Transaction.new(Adapter.new(plainDriver({ ["UPDATE b SET v = 2"] = true }),
    { allowNonAtomicTransactions = true }), cache)
tx:addRaw("UPDATE a SET v = 1", {})
tx:addRaw("UPDATE b SET v = 2", {})
T.eq(tx:commit(), false, "a partially committed transaction still reports failure")
T.eq(isCached(cache, "a"), false, "the table written before the failure is invalidated")
T.eq(isCached(cache, "b"), false, "the table of the failing query is invalidated too")
T.eq(isCached(cache, "c"), true, "untouched tables stay cached")

cache = cacheOver({ "a", "b" })
tx = Transaction.new(Adapter.new(plainDriver({ ["UPDATE a SET v = 1"] = true }),
    { allowNonAtomicTransactions = true }), cache)
tx:addRaw("UPDATE a SET v = 1", {})
tx:addRaw("UPDATE b SET v = 2", {})
T.eq(tx:commit(), false, "a transaction whose first query fails reports failure")
T.eq(isCached(cache, "a") and isCached(cache, "b"), true, "nothing was committed, so the cache is kept")

T.finish()
