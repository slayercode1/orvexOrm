-- tests/test_transaction.lua
-- Transactions: builder mode, callback mode, custom adapter.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_transaction.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local txLog = Mock.txLog
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

-- ─── Test: Transactions ────────────────────────────────────────────

T.section("Transactions")

reset()
local Transaction = require("core.transaction")
local Adapter     = require("database.adapter")
local MySQLDriver = require("database.mysql")

local testAdapter = Adapter.new(MySQLDriver.new())

-- Transaction via module
local tx = Transaction.new(testAdapter)
tx:insert("users", { identifier = "license:tx1", money = 500 })
tx:update("users", { money = 1000 }, { identifier = "license:tx1" })
tx:delete("vehicles", { owner = "license:tx1" })

local queries = tx:getQueries()
T.eq(#queries, 3, "transaction has 3 queries")
T.match(queries[1].query, "INSERT INTO `users`", "tx query 1 is INSERT")
T.match(queries[2].query, "UPDATE `users` SET", "tx query 2 is UPDATE")
T.match(queries[3].query, "DELETE FROM `vehicles`", "tx query 3 is DELETE")

-- Commit
reset()
local success = tx:commit()
T.eq(success, true, "transaction commit returns true")
T.eq(#txLog, 1, "transaction sent to MySQL.transaction")
T.eq(#txLog[1], 3, "transaction has 3 queries in batch")

-- Transaction via ORM.transaction()
reset()
local tx2 = ORM.transaction()
tx2:insert("users", { identifier = "license:tx2", money = 100 })
tx2:upsert("users", { identifier = "license:tx2", money = 200 })
local success2 = tx2:commit()
T.eq(success2, true, "ORM.transaction commit works")
T.eq(#txLog[1], 2, "ORM.transaction has 2 queries")

-- Empty transaction
reset()
local tx3 = ORM.transaction()
T.eq(tx3:commit(), true, "empty transaction returns true")

-- Transaction with addRaw
reset()
local tx4 = ORM.transaction()
tx4:addRaw("ALTER TABLE users ADD COLUMN test INT", {})
tx4:insert("users", { identifier = "license:raw", money = 0 })
T.eq(#tx4:getQueries(), 2, "addRaw + insert = 2 queries")

-- ─── Test: Transaction callback ─────────────────────────────────

T.section("Transaction callback")

reset()
local txResult = ORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:cb1", money = 100 })
    tx:update("users", { money = 200 }, { identifier = "license:cb1" })
end)
T.eq(txResult, true, "tx callback: returns true on success")
T.eq(#txLog, 1, "tx callback: committed 1 transaction")
T.eq(#txLog[1], 2, "tx callback: has 2 queries")

-- Transaction callback with custom adapter
reset()
local txResult2 = ORM.transaction(function(tx)
    tx:insert("users", { identifier = "license:cb2", money = 500 })
end, testAdapter)
T.eq(txResult2, true, "tx callback with adapter: returns true")

-- Builder mode still works
reset()
local txBuilder = ORM.transaction()
txBuilder:insert("users", { identifier = "license:builder", money = 0 })
local txCommit = txBuilder:commit()
T.eq(txCommit, true, "tx builder mode: still works")

T.finish()
