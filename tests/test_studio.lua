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
local convars = { orvex_studio_token = configuredToken }
local tableRows = {}

function SetHttpHandler(callback) handler = callback end
function RegisterCommand(_, callback) studioCommand = callback end
function GetConvar(name, default)
    if convars[name] ~= nil then return convars[name] end
    return default
end
function GetCurrentResourceName() return "orvexorm" end
function GetResourcePath() return "." end

json = require("tests.support.json")

-- ORM double: records every statement the Studio sends.
local sentQueries = {}
local failNextWrite = false

local function recordQuery(sql, params)
    sentQueries[#sentQueries + 1] = { sql = sql, params = params or {} }
end

OrvexORM = {
    raw = function(sql, params)
        recordQuery(sql, params)
        if sql == "SHOW TABLES" then return { { Tables_in_test = "users" } } end
        if sql:find("^SELECT %*") then return tableRows end
        return {}
    end,
    rawExec = function(sql, params)
        recordQuery(sql, params)
        if failNextWrite then
            failNextWrite = false
            error("Duplicate entry 'secret' for key 'PRIMARY'")
        end
        return 1
    end,
}

local function lastQuery() return sentQueries[#sentQueries] end

local Logger = require("utils.logger")
local loggedEvents = {}
Logger.setSink(function(_, event) loggedEvents[#loggedEvents + 1] = event end)
require("lib.studio")

local function clearLogs() loggedEvents = {} end

local function countLogs(predicate)
    local count = 0
    for _, event in ipairs(loggedEvents) do
        if predicate(event) then count = count + 1 end
    end
    return count
end

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

local AUTH = { ["x-studio-token"] = configuredToken }

local function startStudio(overrides)
    studioCommand(0, { "stop" })
    convars = { orvex_studio_token = configuredToken }
    for name, value in pairs(overrides or {}) do convars[name] = value end
    studioCommand(0, {})
    clearLogs()
end

local function readFile(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*a")
    file:close()
    return content
end

-- ─── Inactive Studio ────────────────────────────────────────────────

print("\n== Inactive Studio ==")

clearLogs()
local inactive = request("/api/connection")
check(inactive.status == 404, "inactive Studio answers a plain 404")
check(inactive.body:find('"errorId"', 1, true) == nil, "inactive Studio does not raise an incident")
check(#loggedEvents == 0, "inactive Studio requests are not logged")
for _ = 1, 50 do request("/orvexorm/", "GET", {}, nil, "203.0.113.9:4000") end
check(#loggedEvents == 0, "flooding an inactive Studio produces no log line")

-- ─── Authentication ─────────────────────────────────────────────────

print("\n== Studio authentication ==")

startStudio()

local denied = request("/api/connection", "GET", {}, nil, "127.0.0.1:30121")
check(denied.status == 403, "missing token is rejected")

local authorized = request("/api/connection", "GET", AUTH)
check(authorized.status == 200, "configured token is accepted in the header")
check(authorized.headers["X-Content-Type-Options"] == "nosniff", "API sets nosniff")
check(authorized.headers["X-Frame-Options"] == "DENY", "API denies framing")
check(authorized.headers["X-Correlation-Id"] ~= nil, "API returns a correlation ID")

local capitalised = request("/api/connection", "GET", { ["X-Studio-Token"] = configuredToken })
check(capitalised.status == 200, "header name is accepted regardless of case")

local queryOnApi = request("/api/connection?token=" .. configuredToken, "GET")
check(queryOnApi.status == 403, "query-string token is refused on API routes")

local page = request("/?token=" .. configuredToken, "GET")
check(page.status == 200, "initial token URL loads Studio")
check(page.headers["Referrer-Policy"] == "no-referrer", "Studio disables referrer leakage")

local headerPage = request("/", "GET", AUTH)
check(headerPage.status == 200, "Studio page also accepts the header token")

local wrongToken = request("/api/connection", "GET", { ["x-studio-token"] = string.rep("b", 32) })
check(wrongToken.status == 403, "wrong token is rejected")

-- ─── Content Security Policy ────────────────────────────────────────

print("\n== Studio Content Security Policy ==")

startStudio()

local csp = page.headers["Content-Security-Policy"]
local scriptSrc = csp:match("script%-src ([^;]*)") or ""
check(csp:find("frame%-ancestors 'none'") ~= nil, "Studio forbids framing")
check(scriptSrc ~= "" and not scriptSrc:find("unsafe%-inline"), "script-src no longer allows 'unsafe-inline'")

local firstLoad = request("/?token=" .. configuredToken, "GET")
local secondLoad = request("/?token=" .. configuredToken, "GET")
local nonce = firstLoad.headers["Content-Security-Policy"]:match("'nonce%-([%w%+/=_%-]+)'")
local otherNonce = secondLoad.headers["Content-Security-Policy"]:match("'nonce%-([%w%+/=_%-]+)'")
check(nonce ~= nil and #nonce >= 22, "script-src carries a strong nonce")
check(nonce ~= otherNonce, "a fresh nonce is generated on every page load")
check(nonce and firstLoad.body:find('<script nonce="' .. nonce .. '">', 1, true) ~= nil, "page script carries the CSP nonce")
check(nonce and firstLoad.body:find('<style nonce="' .. nonce .. '">', 1, true) ~= nil, "page stylesheet carries the CSP nonce")
check(not firstLoad.body:find("{{NONCE}}", 1, true), "nonce placeholder is fully substituted")
local styleSrc = csp:match("style%-src ([^;]*)") or ""
check(styleSrc:find("'nonce%-") ~= nil and not styleSrc:find("unsafe%-inline"), "style-src no longer allows 'unsafe-inline'")

-- ─── Frontend hardening (static) ────────────────────────────────────

print("\n== Studio frontend hardening ==")

local html = readFile("studio.html")
local inlineHandler = html:match("[%s\"']on%a+%s*=%s*[\"']")
check(inlineHandler == nil, "studio.html has no inline event handler attribute" .. (inlineHandler and (" (found " .. inlineHandler .. ")") or ""))
check(not html:find("javascript:", 1, true), "studio.html has no javascript: URL")
local _, scriptTags = html:gsub("<script", "")
check(scriptTags == 1, "studio.html has a single script block")
check(html:find('<script nonce="{{NONCE}}">', 1, true) ~= nil, "studio.html script block is nonce-tagged")
check(html:find('<style nonce="{{NONCE}}">', 1, true) ~= nil, "studio.html style block is nonce-tagged")
check(not html:find('style="', 1, true), "studio.html has no inline style attribute")
local escapeMap = html:match("const HTML_ESCAPES = (%b{})") or ""
check(escapeMap:find([['"': '&quot;']], 1, true) and escapeMap:find([["'": '&#39;']], 1, true), "esc() escapes double and single quotes")
check(not html:find([[value="' + esc]], 1, true), "edit form no longer builds value attributes from strings")
check(not html:find("insertAdjacentHTML", 1, true), "modals are no longer assembled with insertAdjacentHTML")

-- ─── Network allowlist ──────────────────────────────────────────────

print("\n== Studio network allowlist ==")

startStudio()
check(request("/api/connection", "GET", AUTH, nil, "127.0.0.1:5000").status == 200, "loopback IPv4 is allowed by default")
check(request("/api/connection", "GET", AUTH, nil, "[::1]:5000").status == 200, "loopback IPv6 is allowed by default")
check(request("/api/connection", "GET", AUTH, nil, "::ffff:127.0.0.1:5000").status == 200, "IPv4-mapped loopback is allowed by default")
clearLogs()
local remote = request("/api/connection", "GET", AUTH, nil, "198.51.100.7:5000")
check(remote.status == 404, "remote address is refused by default even with a valid token")
check(#loggedEvents == 0, "refused remote addresses are not logged")
for _ = 1, 10 do request("/api/connection", "GET", {}, nil, "198.51.100.7:5000") end
check(request("/api/connection", "GET", AUTH, nil, "127.0.0.1:5000").status == 200, "refused remote attempts do not lock out allowed hosts")

startStudio({ orvex_studio_allow = "127.0.0.1, 10.0.0.0/8 192.168.1.20" })
check(request("/api/connection", "GET", AUTH, nil, "10.42.1.3:5000").status == 200, "CIDR range in the allowlist is honoured")
check(request("/api/connection", "GET", AUTH, nil, "192.168.1.20:5000").status == 200, "exact address in the allowlist is honoured")
check(request("/api/connection", "GET", AUTH, nil, "11.0.0.1:5000").status == 404, "address outside the allowlist is refused")
check(request("/api/connection", "GET", AUTH, nil, "[::1]:5000").status == 404, "custom allowlist replaces the default")

startStudio({ orvex_studio_allow = "*" })
check(request("/api/connection", "GET", AUTH, nil, "198.51.100.7:5000").status == 200, "'*' explicitly allows every address")

-- ─── Request validation ─────────────────────────────────────────────

print("\n== Studio request validation ==")

startStudio()

local malformed = request("/api/tables/users/rows", "POST", AUTH, "not-json")
check(malformed.status == 422, "malformed JSON is rejected")

local oversized = request("/api/tables/users/rows", "POST", AUTH, string.rep("x", 1024 * 1024 + 1))
check(oversized.status == 422, "oversized body is rejected before decoding")

local invalidPage = request("/api/tables/users/rows?page=-1", "GET", AUTH)
check(invalidPage.status == 422, "invalid pagination is rejected")

-- ─── Rate limiting and lockout ──────────────────────────────────────

print("\n== Studio rate limiting ==")

startStudio({ orvex_studio_allow = "127.0.0.0/8" })

local limited
for _ = 1, 121 do
    limited = request("/api/connection", "GET", AUTH, nil, "127.0.0.3:30120")
end
check(limited.status == 429, "per-address request limit is enforced")
for _ = 1, 20 do request("/api/connection", "GET", AUTH, nil, "127.0.0.3:30120") end
local rateLogs = countLogs(function(event) return event.errorCode == "RATE_LIMITED" end)
check(rateLogs == 1, "rate-limited rejections are logged once per window (got " .. rateLogs .. ")")

clearLogs()
local unauthenticated
for _ = 1, 125 do
    unauthenticated = request("/api/connection", "GET", {}, nil, "127.0.0.4:30120")
end
check(unauthenticated.status == 429, "rate limit applies before token validation")
local forbiddenLogs = countLogs(function(event) return event.errorCode == "FORBIDDEN" end)
check(forbiddenLogs <= 5, "bad-token rejections stop being logged once the address is locked out (got " .. forbiddenLogs .. ")")

clearLogs()
for _ = 1, 5 do request("/api/connection", "GET", {}, nil, "127.0.0.5:30120") end
local lockedOut = request("/api/connection", "GET", AUTH, nil, "127.0.0.5:30120")
check(lockedOut.status == 429, "address is locked out after 5 bad tokens")
for _ = 1, 10 do request("/api/connection", "GET", AUTH, nil, "127.0.0.5:30120") end
local lockoutLogs = countLogs(function(event) return event.technicalMessage == "Studio token lockout" end)
check(lockoutLogs == 1, "lockout rejections are logged once (got " .. lockoutLogs .. ")")
check(request("/api/connection", "GET", AUTH, nil, "127.0.0.6:30120").status == 200, "lockout is per address")

-- ─── Writes: insert, update, delete ─────────────────────────────────

print("\n== Studio writes ==")

startStudio()

local function decodeBody(response) return json.decode(response.body) end

local function paramsContain(params, value)
    for _, param in ipairs(params) do
        if param == value then return true end
    end
    return false
end

sentQueries = {}
local inserted = request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = "bob", money = 5 }))
check(inserted.status == 200, "insert succeeds")
local insertSql = lastQuery().sql
check(insertSql:find("^INSERT INTO `users` %(") ~= nil, "insert targets the quoted table")
check(insertSql:find("`name`", 1, true) and insertSql:find("`money`", 1, true), "insert lists the quoted columns")
check(insertSql:find("VALUES (?, ?)", 1, true) ~= nil, "insert binds values as placeholders")
check(paramsContain(lastQuery().params, "bob") and paramsContain(lastQuery().params, 5), "insert passes the values as parameters")
check(decodeBody(inserted).insertId == 1, "insert returns the driver's insert id")

sentQueries = {}
request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = "eve", ["name`); DROP TABLE users; --"] = 1 }))
check(#sentQueries == 1 and not lastQuery().sql:find("DROP", 1, true), "insert drops column names that are not plain identifiers")

sentQueries = {}
local noColumns = request("/api/tables/users/rows", "POST", AUTH, json.encode({ ["a b"] = 1 }))
check(noColumns.status == 422 and #sentQueries == 0, "insert with no valid column is rejected before any query")

local badTable = request("/api/tables/us%60ers;/rows", "POST", AUTH, json.encode({ name = "x" }))
check(badTable.status == 422, "an unsafe table name is rejected")

sentQueries = {}
local updated = request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id", pkValue = 3, data = { name = "zed" } }))
check(updated.status == 200, "update succeeds")
check(lastQuery().sql == "UPDATE `users` SET `name` = ? WHERE `id` = ?", "update builds a parameterised statement on the primary key")
check(lastQuery().params[1] == "zed" and lastQuery().params[2] == 3, "update binds the new value then the primary key")
check(decodeBody(updated).affectedRows == 1, "update returns the affected rows")

sentQueries = {}
check(request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id", data = { name = "x" } })).status == 422,
    "update without a primary key value is rejected")
check(request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id = id OR 1", pkValue = 1, data = { name = "x" } })).status == 422,
    "update with an unsafe primary key column is rejected")
check(request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id", pkValue = 1 })).status == 422,
    "update without data is rejected")
check(#sentQueries == 0, "rejected updates send no query")

sentQueries = {}
local deleted = request("/api/tables/users/rows", "DELETE", AUTH, json.encode({ pk = "id", pkValue = 7 }))
check(deleted.status == 200, "delete succeeds")
check(lastQuery().sql == "DELETE FROM `users` WHERE `id` = ? LIMIT 1", "delete removes at most one row by primary key")
check(lastQuery().params[1] == 7, "delete binds the primary key value")

sentQueries = {}
check(request("/api/tables/users/rows", "DELETE", AUTH, json.encode({ pk = "id" })).status == 422,
    "delete without a primary key value is rejected")
check(request("/api/tables/users/rows", "DELETE", AUTH, "").status == 422, "delete without a body is rejected")
check(#sentQueries == 0, "rejected deletes send no query")

clearLogs()
failNextWrite = true
local failedWrite = request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = "dup" }))
check(failedWrite.status == 500, "a database failure answers 500")
check(not failedWrite.body:find("secret", 1, true), "the database error text is not sent to the browser")
check(decodeBody(failedWrite).error.errorId ~= nil, "a database failure returns an errorId")
check(countLogs(function(event) return event.errorCode == "INTERNAL_ERROR" end) == 1, "a database failure is logged once")

check(request("/api/nothing-here", "GET", AUTH).status == 404, "an unknown API route answers 404")

-- ─── Reads: filters and sorting ─────────────────────────────────────

print("\n== Studio reads ==")

sentQueries = {}
request("/api/tables/users/rows?filter_col=name&filter_op=LIKE&filter_val=bo&sort=money&dir=desc&page=2&perPage=10", "GET", AUTH)
local select = sentQueries[1]
check(select.sql == "SELECT * FROM `users` WHERE `name` LIKE ? ORDER BY `money` DESC LIMIT ? OFFSET ?",
    "filter, sort and pagination build one parameterised SELECT")
check(select.params[1] == "%bo%" and select.params[2] == 10 and select.params[3] == 10, "LIKE is wrapped in % and the page becomes an offset")

sentQueries = {}
request("/api/tables/users/rows?filter_col=name&filter_op=;DROP&sort=money;--", "GET", AUTH)
check(sentQueries[1].sql == "SELECT * FROM `users` LIMIT ? OFFSET ?", "unknown operators and unsafe sort columns are ignored")

sentQueries = {}
request("/api/tables/users/rows?perPage=1000", "GET", AUTH)
check(sentQueries[1].params[1] == 100, "page size is capped at 100")

local tables = decodeBody(request("/api/tables", "GET", AUTH))
check(tables.tables[1] == "users", "the table list is read from SHOW TABLES")

-- ─── Session expiry and lockout expiry (controlled clock) ───────────

print("\n== Studio session and lockout expiry ==")

local realTime = os.time
local now = realTime()
os.time = function(t) if t then return realTime(t) end return now end

startStudio()
now = now + 1799
check(request("/api/connection", "GET", AUTH).status == 200, "the session is valid until its 30-minute lifetime")
now = now + 1
local expired = request("/api/connection", "GET", AUTH)
check(expired.status == 401, "the session expires after 30 minutes")
check(request("/api/connection", "GET", AUTH).status == 404, "an expired Studio stops answering like an inactive one")

startStudio()
for _ = 1, 5 do request("/api/connection", "GET", {}, nil, "127.0.0.1:1") end
check(request("/api/connection", "GET", AUTH).status == 429, "the address is locked out after 5 bad tokens")
now = now + 299
check(request("/api/connection", "GET", AUTH).status == 429, "the lockout lasts 5 minutes")
now = now + 1
check(request("/api/connection", "GET", AUTH).status == 200, "the lockout lifts after 5 minutes")
for _ = 1, 4 do request("/api/connection", "GET", {}, nil, "127.0.0.1:1") end
check(request("/api/connection", "GET", AUTH).status == 200, "a successful login resets the failure count")

os.time = realTime
studioCommand(0, { "stop" })

-- ─── JSON encoder ───────────────────────────────────────────────────

print("\n== Studio JSON encoder ==")

startStudio()

tableRows = {
    { id = 1, name = "a\1b\0c\8\12\31\127", note = 'quote " back \\ nl \n tab \t', utf8 = "é€" },
    { id = 2, ratio = 0 / 0, big = math.huge, small = -math.huge, float = 1.5 },
}
local encoded = request("/api/tables/users/rows", "GET", AUTH).body
check(encoded ~= nil and not encoded:find("[%z\1-\31\127]"), "encoded JSON contains no raw control character")
check(encoded:find('"a\\u0001b\\u0000c\\b\\f\\u001f\\u007f"', 1, true) ~= nil, "control characters are escaped as \\uXXXX or short escapes")
check(encoded:find('"quote \\" back \\\\ nl \\n tab \\t"', 1, true) ~= nil, "quotes, backslashes, newlines and tabs are escaped")
check(encoded:find('"é€"', 1, true) ~= nil, "UTF-8 text is preserved")
check(encoded:find('"ratio":null', 1, true) ~= nil, "NaN is encoded as null")
check(encoded:find('"big":null', 1, true) ~= nil and encoded:find('"small":null', 1, true) ~= nil, "infinities are encoded as null")
check(encoded:find('"float":1.5', 1, true) ~= nil, "finite numbers are preserved")
check(not encoded:find("nan", 1, true) and not encoded:find("inf", 1, true), "no bare nan/inf token is emitted")
local parsedOk, parsed = pcall(json.decode, encoded)
check(parsedOk, "the response parses with a strict JSON decoder")
check(parsedOk and parsed.rows[1].note == 'quote " back \\ nl \n tab \t', "escaped strings decode back to the original text")
check(parsedOk and parsed.rows[1].name == "a\1b\0c\8\12\31\127", "control characters decode back to the original bytes")
tableRows = {}

studioCommand(0, { "stop" })
Logger.setSink(nil)

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
