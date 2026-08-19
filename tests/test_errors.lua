local Errors = require("utils.errors")
local Logger = require("utils.logger")

local passed, failed = 0, 0

local function check(condition, message)
    if condition then
        passed = passed + 1
        print("  ✓ " .. message)
    else
        failed = failed + 1
        print("  ✗ " .. message)
    end
end

print("\n== Error contracts ==")

local expectedStatuses = {
    VALIDATION_ERROR = 422, AUTHENTICATION_REQUIRED = 401, FORBIDDEN = 403,
    NOT_FOUND = 404, CONFLICT = 409, RATE_LIMITED = 429,
    INTERNAL_ERROR = 500, EXTERNAL_SERVICE_ERROR = 502,
    SERVICE_UNAVAILABLE = 503, NETWORK_ERROR = 503, TIMEOUT = 504,
}

for code, status in pairs(expectedStatuses) do
    local appError = Errors.new(code, "SELECT secret FROM internal_users /srv/app.lua token=abc")
    local response = Errors.toResponse(appError, status >= 500 and "ERR-test" or nil)
    check(appError.status == status, code .. " uses HTTP " .. status)
    check(not response.error.message:find("SELECT", 1, true), code .. " hides technical details")
    check((status < 500 and response.error.errorId == nil) or response.error.errorId == "ERR-test", code .. " incident reference policy")
end

local firstId = Errors.generateId("ERR")
local secondId = Errors.generateId("ERR")
check(firstId ~= secondId, "incident identifiers are unique")
check(firstId:match("^ERR%-%d%d%d%d%d%d%d%d%d%d%d%d%d%d%-%x+$") ~= nil, "incident identifier format is searchable")

print("\n== Structured log redaction ==")

local clean = Logger.sanitize({
    password = "hunter2",
    authorization = "Bearer secret",
    nested = { api_key = "key-123", safe = "kept" },
    url = "/api?token=secret-value&ok=1",
})
check(clean.password == "[REDACTED]", "password is redacted")
check(clean.authorization == "[REDACTED]", "authorization header is redacted")
check(clean.nested.api_key == "[REDACTED]", "nested API key is redacted")
check(clean.nested.safe == "kept", "non-sensitive fields are retained")
check(not clean.url:find("secret-value", 1, true), "query-string token is redacted")

local captured
Logger.setSink(function(line) captured = line end)
Logger.error("database failed", { errorId = "ERR-test", token = "secret", route = "/api/tables" })
check(captured and captured:find('"errorId":"ERR%-test"') ~= nil, "structured logs contain errorId")
check(captured and not captured:find("secret", 1, true), "structured logs exclude secrets")
Logger.setSink(nil)

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
