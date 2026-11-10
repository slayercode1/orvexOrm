-- tests/test_support_json.lua
-- Self-test of the JSON codec the other suites use as FiveM's `json` global,
-- so a broken mock cannot make the ORM's JSON tests pass by accident.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_support_json.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local JSON = require("tests.support.json")
local T = require("tests.support.harness")

T.section("Encoding")

T.eq(JSON.encode({}), "[]", "an empty table encodes as an empty array, like FiveM")
T.eq(JSON.encode({ 1, 2, 3 }), "[1,2,3]", "a sequence encodes as an array")
T.eq(JSON.encode({ b = 1, a = true }), '{"a":true,"b":1}', "object keys are sorted")
T.eq(JSON.encode({ [1] = "x", [3] = "y" }), '{"1":"x","3":"y"}', "a sparse table encodes as an object")
T.eq(JSON.encode(1.5), "1.5", "floats keep their value")
T.eq(JSON.encode('a"b\\c\n\t\1'), '"a\\"b\\\\c\\n\\t\\u0001"', "quotes, backslashes and control characters are escaped")
T.eq(JSON.encode("é€"), '"é€"', "UTF-8 text is kept as-is")
T.raises(function() JSON.encode(0 / 0) end, "NaN cannot be encoded")
T.raises(function() JSON.encode(print) end, "functions cannot be encoded")

T.section("Decoding")

local nested = JSON.decode(' { "list" : [1, 2.5, "x", true, false, null, {"k": []}], "n": -3e2 } ')
T.eq(nested.list[7] ~= nil, true, "values after a null keep their index")
T.eq(nested.list[2], 2.5, "floats are decoded")
T.eq(nested.list[6], nil, "null decodes to nil")
T.eq(#nested.list[7].k, 0, "nested empty array")
T.eq(nested.n, -300.0, "exponent numbers are decoded")
T.eq(math.type(JSON.decode("42")), "integer", "integers stay integers")
T.eq(JSON.decode('"\\u00e9\\ud83d\\ude00\\/"'), "é😀/", "unicode escapes and surrogate pairs become UTF-8")
T.raises(function() JSON.decode('{"a":1,}') end, "a trailing comma is rejected")
T.raises(function() JSON.decode("[1") end, "an unterminated array is rejected")
T.raises(function() JSON.decode('"a\nb"') end, "a raw control character in a string is rejected")
T.raises(function() JSON.decode("not-json") end, "an unknown token is rejected")
T.raises(function() JSON.decode("{} x") end, "trailing characters are rejected")

T.section("Round-trip")

local value = { name = 'he said "ok"\r\n', tags = { "a", "b" }, pos = { x = -1.25, y = 0 } }
local back = JSON.decode(JSON.encode(value))
T.eq(back.name, value.name, "escaped string round-trips")
T.eq(back.tags[2], "b", "array round-trips")
T.eq(back.pos.x, -1.25, "negative float round-trips")

T.finish()
