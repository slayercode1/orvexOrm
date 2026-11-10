-- tests/test_logger.lua
-- Structured logger: one JSON line per event, safe to print on the FiveM console.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_logger.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local T = require("tests.support.harness")

local function contains(haystack, needle)
    return haystack:find(needle, 1, true) ~= nil
end

--- `T.check` that shows the emitted line when it fails.
local function checkLine(condition, message, emitted)
    if not T.check(condition, message) then print("    line: " .. emitted) end
end

local Logger = require("utils.logger")

local lines = {}
Logger.setSink(function(line) lines[#lines + 1] = line end)

--- Logs `message` (and `context`) at warn level and returns the emitted line.
local function logLine(message, context)
    lines = {}
    Logger.warn(message, context)
    return lines[1] or ""
end

T.section("logger: control characters")

local line = logLine("before\27[31mafter")
checkLine(not contains(line, "\27"), "raw ESC never reaches the console", line)
checkLine(contains(line, "before\\u001b[31mafter"), "ESC is written as \\u001b", line)

line = logLine("nul\0byte")
checkLine(contains(line, "nul\\u0000byte"), "NUL is written as \\u0000", line)

line = logLine("bell\7del\127end")
checkLine(contains(line, "bell\\u0007del\\u007fend"), "BEL and DEL are written as \\u00XX", line)

line = logLine("a\nb\rc\td")
checkLine(contains(line, "a\\nb\\rc\\td"), "LF, CR and TAB keep their short escapes", line)

line = logLine('say "hi" \\ bye')
checkLine(contains(line, 'say \\"hi\\" \\\\ bye'), "quote and backslash stay escaped", line)

local everyControl = {}
for byte = 0, 31 do everyControl[#everyControl + 1] = string.char(byte) end
everyControl[#everyControl + 1] = "\127"
line = logLine(table.concat(everyControl), { [table.concat(everyControl)] = table.concat(everyControl) })
checkLine(not line:find("%c"), "the emitted line holds no control character", line)

T.section("logger: FiveM colour codes")

line = logLine("^1red^7 normal ^0")
checkLine(not line:find("%^%d"), "no ^0-^9 colour code reaches the console", line)
checkLine(contains(line, "\\u005e1red\\u005e7 normal \\u005e0"), "the caret of a colour code is escaped", line)

line = logLine("2^8 and a^b")
checkLine(not line:find("%^%d"), "a caret followed by a digit is escaped anywhere", line)
checkLine(contains(line, "a^b"), "a caret not followed by a digit is kept", line)

line = logLine("static", { ["^2key"] = "^3value" })
checkLine(not line:find("%^%d"), "context keys and values are escaped too", line)

T.section("logger: sanitize still applies")

line = logLine("connect", { password = "hunter2", note = "Bearer abc.def" })
checkLine(not contains(line, "hunter2"), "sensitive keys are redacted", line)
checkLine(contains(line, '"password":"[REDACTED]"'), "redaction marker is kept", line)
checkLine(contains(line, "Bearer [REDACTED]"), "bearer tokens inside strings are redacted", line)

T.finish()
