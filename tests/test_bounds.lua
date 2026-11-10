-- tests/test_bounds.lua
-- Upper bounds on caller-supplied sizes: paginate perPage and whereIn lists.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_bounds.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local ORM = require("core.orm")
local Builder = require("core.builder")

local Item = ORM.model("bounded_items", { id = "number", name = "string" })

local function valuesOf(count)
    local values = {}
    for i = 1, count do values[i] = i end
    return values
end

T.section("paginate perPage upper bound")

T.eq(Builder.MAX_PER_PAGE, 1000, "the default perPage ceiling is 1000")

Mock.reset()
Mock.results[1] = { { cnt = 0 } }
Mock.results[2] = {}
T.check(pcall(function() return Item.query():paginate(1, 1000) end), "perPage at the ceiling is accepted")

Mock.reset()
T.raises(function() Item.query():paginate(1, 1001) end,
    "perPage above the ceiling raises", "perPage")
T.eq(#Mock.log, 0, "an oversized perPage sends no query")

T.raises(function() Item.query():paginate(1, "5000") end,
    "a numeric-string perPage above the ceiling raises too", "perPage")

T.section("whereIn list upper bound")

T.eq(Builder.MAX_IN_VALUES, 10000, "the default IN list ceiling is 10000")

T.check(pcall(function() return Item.query():whereIn("id", valuesOf(10000)):toSQL() end),
    "an IN list at the ceiling is accepted")
T.raises(function() Item.query():whereIn("id", valuesOf(10001)):toSQL() end,
    "an IN list above the ceiling raises", "at most")
T.raises(function() Item.query():whereNotIn("id", valuesOf(10001)):toSQL() end,
    "whereNotIn shares the ceiling", "at most")

T.section("ceilings can be raised by the server owner")

local defaultPerPage, defaultInValues = Builder.MAX_PER_PAGE, Builder.MAX_IN_VALUES
Builder.MAX_PER_PAGE, Builder.MAX_IN_VALUES = 5000, 20000
Mock.reset()
Mock.results[1] = { { cnt = 0 } }
Mock.results[2] = {}
T.check(pcall(function() return Item.query():paginate(1, 5000) end), "a raised perPage ceiling applies")
T.check(pcall(function() return Item.query():whereIn("id", valuesOf(15000)):toSQL() end),
    "a raised IN ceiling applies")
Builder.MAX_PER_PAGE, Builder.MAX_IN_VALUES = defaultPerPage, defaultInValues

T.finish()
