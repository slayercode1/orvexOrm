-- tests/support/harness.lua
-- Minimal assertion harness shared by the newer suites.
-- Usage:
--   local T = require("tests.support.harness")
--   T.section("Feature")
--   T.eq(actual, expected, "message")
--   T.match(str, "lua pattern", "message")
--   T.finish()  -- prints the totals and exits 1 on failure

local Harness = {}

local passed, failed = 0, 0

local function record(ok, message, detail)
    if ok then
        passed = passed + 1
        print("  ✓ " .. message)
    else
        failed = failed + 1
        print("  ✗ " .. message .. (detail and (" — " .. detail) or ""))
    end
    return ok
end

---@param title string
function Harness.section(title)
    print("\n== " .. title .. " ==")
end

---@param condition any
---@param message string
function Harness.check(condition, message)
    return record(condition and true or false, message)
end

---@param actual any
---@param expected any
---@param message string
function Harness.eq(actual, expected, message)
    return record(actual == expected, message,
        ("expected: %s, got: %s"):format(tostring(expected), tostring(actual)))
end

---@param str any converted with tostring()
---@param pattern string Lua pattern
---@param message string
function Harness.match(str, pattern, message)
    local text = tostring(str)
    return record(text:match(pattern) ~= nil, message,
        ("'%s' does not match '%s'"):format(text, pattern))
end

--- Runs `fn` and returns the error it raised as a string, or nil.
---@param fn function
---@return string|nil
function Harness.errorOf(fn)
    local ok, err = pcall(fn)
    if ok then return nil end
    if type(err) == "table" then return tostring(err.technicalMessage or err.message or err) end
    return tostring(err)
end

---@param fn function
---@param message string
---@param pattern? string plain substring the error must contain
function Harness.raises(fn, message, pattern)
    local err = Harness.errorOf(fn)
    if not err then return record(false, message, "no error raised") end
    if pattern and not err:find(pattern, 1, true) then
        return record(false, message, "error was: " .. err)
    end
    return record(true, message)
end

function Harness.finish()
    print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

return Harness
