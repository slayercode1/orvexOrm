-- tests/test_utils.lua
-- Validator and serializer (JSON, auto and date columns).
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_utils.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

-- ─── Test: Validator ───────────────────────────────────────────────

T.section("Validator")

local Validator = require("utils.validator")

local ok, err = Validator.validate(
    { identifier = "license:abc", money = 500 },
    { identifier = "string", money = "number" }
)
T.eq(ok, true, "valid data passes")

ok, err = Validator.validate({ identifier = 123 }, { identifier = "string" })
T.eq(ok, false, "wrong type fails")

-- ─── Test: Automatic JSON columns ──────────────────────────────────

T.section("Automatic JSON Columns")

local Serializer = require("utils.serializer")

-- Explicit json type
local encoded = Serializer.encode({ x = 1, y = 2 }, "json")
T.eq(type(encoded), "string", "json encode: table → string")
local decoded = Serializer.decode(encoded, "json")
T.eq(type(decoded), "table", "json decode: string → table")
T.eq(decoded.x, 1, "json decode: correct value")

-- Auto type: table → JSON
local autoEncoded = Serializer.encode({ a = 1 }, "auto")
T.eq(type(autoEncoded), "string", "auto encode: table → string")

-- Auto type: JSON string → table
local autoDecoded = Serializer.decode('{"a":1,"b":2}', "auto")
T.eq(type(autoDecoded), "table", "auto decode: JSON string → table")
T.eq(autoDecoded.a, 1, "auto decode: correct value a")
T.eq(autoDecoded.b, 2, "auto decode: correct value b")

-- Auto type: non-JSON string stays string
local plainDecoded = Serializer.decode("hello world", "auto")
T.eq(type(plainDecoded), "string", "auto decode: plain string stays string")
T.eq(plainDecoded, "hello world", "auto decode: plain string unchanged")

-- Auto type: number stays number
local numDecoded = Serializer.decode(42, "auto")
T.eq(numDecoded, 42, "auto decode: number stays number")

-- Arrays and nested values round-trip through a real JSON codec
local inventory = { { item = "bread", count = 5 }, { item = "water", count = 2 } }
local roundTrip = Serializer.decode(Serializer.encode(inventory, "json"), "json")
T.eq(#roundTrip, 2, "json round-trip: array length kept")
T.eq(roundTrip[2].item, "water", "json round-trip: nested object inside array")
T.eq(roundTrip[1].count, 5, "json round-trip: numbers inside array")

local autoArray = Serializer.decode(Serializer.encode({ 1, 2, 3 }, "auto"), "auto")
T.eq(type(autoArray), "table", "auto round-trip: array decodes to a table")
T.eq(autoArray[3], 3, "auto round-trip: array values kept")

-- Strings that need escaping survive the round-trip unchanged
local tricky = { note = 'say "hi"\\path\nline2\ttab', label = "é€ \1" }
local trickyEncoded = Serializer.encode(tricky, "json")
T.eq(trickyEncoded:find("\n", 1, true), nil, "json encode: newline is escaped, not raw")
local trickyBack = Serializer.decode(trickyEncoded, "json")
T.eq(trickyBack.note, tricky.note, "json round-trip: quotes, backslash, newline, tab")
T.eq(trickyBack.label, tricky.label, "json round-trip: UTF-8 and control characters")

-- Auto type: a string that only looks like JSON stays a string
local fakeJson = Serializer.decode("[not json", "auto")
T.eq(fakeJson, "[not json", "auto decode: invalid JSON starting with '[' stays a string")

-- ─── Test: Date types in serializer ──────────────────────────────────

T.section("Date types in serializer")

do
    local Ser = OrvexSerializer

    -- date: 806716800 is a Unix timestamp
    local dateResult = Ser.decode(806716800, "date")
    T.eq(type(dateResult), "string", "date decode: returns a string")
    T.match(dateResult, "^%d%d%d%d%-%d%d%-%d%d$", "date decode: format YYYY-MM-DD")

    -- datetime: 1710000000 is a Unix timestamp
    local dtResult = Ser.decode(1710000000, "datetime")
    T.eq(type(dtResult), "string", "datetime decode: returns a string")
    T.match(dtResult, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$", "datetime decode: format YYYY-MM-DD HH:MM:SS")

    -- timestamp type also converts
    local tsResult = Ser.decode(1710000000, "timestamp")
    T.eq(type(tsResult), "string", "timestamp decode: returns a string")
    T.match(tsResult, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$", "timestamp decode: format YYYY-MM-DD HH:MM:SS")

    -- string values pass through unchanged
    local strDate = Ser.decode("2024-01-15", "date")
    T.eq(strDate, "2024-01-15", "date decode: string passthrough unchanged")

    -- nil passes through
    local nilResult = Ser.decode(nil, "date")
    T.eq(nilResult, nil, "date decode: nil returns nil")
end

-- ─── Test: Shared helpers ──────────────────────────────────────────

T.section("Helpers: numbers, bound values and statement verbs")

local Helpers = require("utils.helpers")

T.eq(Helpers.isFiniteNumber(3), true, "isFiniteNumber: integer")
T.eq(Helpers.isFiniteNumber(-2.5), true, "isFiniteNumber: float")
T.eq(Helpers.isFiniteNumber(0 / 0), false, "isFiniteNumber: NaN")
T.eq(Helpers.isFiniteNumber(math.huge), false, "isFiniteNumber: infinity")
T.eq(Helpers.isFiniteNumber("3"), false, "isFiniteNumber: numeric string")

T.eq(Helpers.isBindable("a"), true, "isBindable: string")
T.eq(Helpers.isBindable(false), true, "isBindable: boolean")
T.eq(Helpers.isBindable(-math.huge), false, "isBindable: infinity")
T.eq(Helpers.isBindable({}), false, "isBindable: table")

T.eq(Helpers.sqlVerb("  select 1"), "SELECT", "sqlVerb: upper-cased first keyword")
T.eq(Helpers.sqlVerb("(SELECT 1) UNION (SELECT 2)"), "SELECT", "sqlVerb: skips opening parentheses")
T.eq(Helpers.sqlVerb(""), nil, "sqlVerb: nil for an empty statement")
T.eq(Helpers.isReadVerb("WITH"), true, "isReadVerb: WITH is routed as a read")
T.eq(Helpers.isReadVerb("UPDATE"), false, "isReadVerb: UPDATE is a write")

T.eq(table.concat(Validator.SUPPORTED_TYPES, ", "), "string, number, boolean, json, auto, date, datetime, timestamp",
    "Validator.SUPPORTED_TYPES lists every type in documentation order")
for _, fieldType in ipairs(Validator.SUPPORTED_TYPES) do
    T.eq(Validator.isKnownType(fieldType), true, "isKnownType: " .. fieldType)
end

T.finish()
