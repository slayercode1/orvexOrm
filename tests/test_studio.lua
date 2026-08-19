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

local handler, studioCommand
local configuredToken = string.rep("a", 32)

function SetHttpHandler(callback) handler = callback end
function RegisterCommand(_, callback) studioCommand = callback end
function GetConvar(name, default)
    if name == "orvex_studio_token" then return configuredToken end
    return default
end
function GetCurrentResourceName() return "orvexorm" end
function GetResourcePath() return "." end

json = {
    decode = function(value)
        if value == "{}" then return {} end
        error("invalid json")
    end,
}

OrvexORM = {
    raw = function(sql)
        if sql == "SHOW TABLES" then return { { Tables_in_test = "users" } } end
        return {}
    end,
    rawExec = function() return 1 end,
}

local Logger = require("utils.logger")
Logger.setSink(function() end)
require("lib.studio")

local function request(path, method, headers, body, address)
    local response = { status = nil, headers = nil, body = nil }
    handler({
        path = path,
        method = method or "GET",
        headers = headers or {},
        body = body,
        address = address or "127.0.0.1:30120",
    }, {
        writeHead = function(status, responseHeaders)
            response.status = status
            response.headers = responseHeaders
        end,
        send = function(responseBody) response.body = responseBody end,
    })
    return response
end

print("\n== Studio HTTP security ==")

local inactive = request("/api/connection")
check(inactive.status == 503, "inactive Studio fails closed")
check(inactive.body:find('"errorId"', 1, true) ~= nil, "unexpected availability error has an incident ID")

studioCommand(0, {})

local denied = request("/api/connection", "GET", {}, nil, "127.0.0.2:30120")
check(denied.status == 403, "missing token is rejected")

local authorized = request("/api/connection", "GET", { ["x-studio-token"] = configuredToken })
check(authorized.status == 200, "configured token is accepted")
check(authorized.headers["X-Content-Type-Options"] == "nosniff", "API sets nosniff")
check(authorized.headers["X-Frame-Options"] == "DENY", "API denies framing")
check(authorized.headers["X-Correlation-Id"] ~= nil, "API returns a correlation ID")

local page = request("/?token=" .. configuredToken, "GET")
check(page.status == 200, "initial token URL loads Studio")
check(page.headers["Content-Security-Policy"]:find("frame%-ancestors 'none'") ~= nil, "Studio sends a restrictive CSP")
check(page.headers["Referrer-Policy"] == "no-referrer", "Studio disables referrer leakage")

local malformed = request("/api/tables/users/rows", "POST", { ["x-studio-token"] = configuredToken }, "not-json")
check(malformed.status == 422, "malformed JSON is rejected")

local oversized = request("/api/tables/users/rows", "POST", { ["x-studio-token"] = configuredToken }, string.rep("x", 1024 * 1024 + 1))
check(oversized.status == 422, "oversized body is rejected before decoding")

local invalidPage = request("/api/tables/users/rows?page=-1", "GET", { ["x-studio-token"] = configuredToken })
check(invalidPage.status == 422, "invalid pagination is rejected")

local limited
for _ = 1, 121 do
    limited = request("/api/connection", "GET", { ["x-studio-token"] = configuredToken }, nil, "127.0.0.3:30120")
end
check(limited.status == 429, "per-address request limit is enforced")

studioCommand(0, { "stop" })
Logger.setSink(nil)

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
