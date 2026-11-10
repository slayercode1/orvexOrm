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
-- A strong token, as `openssl rand -hex 32` prints it.
local configuredToken = "f3a9c1d27b4e8f60a5d3c9e1b7f2046a8d5c3e9f1a7b6d4c2e0f8a9b3c5d7e1f"
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

local function paramsContain(params, value)
    for _, param in ipairs(params) do
        if param == value then return true end
    end
    return false
end

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

local function headerIn(headers, name)
    for key in pairs(headers) do
        if key:lower() == name then return true end
    end
    return false
end

-- Mirrors FXServer's request object: there is no req.body. The body is
-- delivered once, complete, to the callback given to req.setDataHandler,
-- and only when the request declares a Content-Length > 0 or is chunked.
local function request(path, method, headers, body, address)
    local response = { status = nil, headers = nil, body = nil, bodyRead = false }
    local requestHeaders = {}
    for name, value in pairs(headers or {}) do requestHeaders[name] = value end
    local chunked = headerIn(requestHeaders, "transfer-encoding")
    if body ~= nil and not chunked and not headerIn(requestHeaders, "content-length") then
        requestHeaders["content-length"] = tostring(#body)
    end
    local dataHandler
    handler({
        path = path,
        method = method or "GET",
        headers = requestHeaders,
        address = address or "127.0.0.1:30120",
        setDataHandler = function(callback)
            response.bodyRead = true
            dataHandler = callback
        end,
        setCancelHandler = function() end,
    }, {
        writeHead = function(status, responseHeaders)
            response.status = status
            response.headers = responseHeaders
        end,
        send = function(responseBody) response.body = responseBody end,
    })
    -- FXServer calls the data handler later, on the main thread.
    if dataHandler and body ~= nil and (#body > 0 or chunked) then dataHandler(body) end
    return response
end

-- The Studio prints to the console and reads /dev/urandom through globals,
-- so these doubles replace print and io.open for the duration of one call.
-- luacheck: push ignore 121 122
local printedLines = {}
local realPrint = print
local function capturePrints(action)
    printedLines = {}
    print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = tostring(select(index, ...)) end
        printedLines[#printedLines + 1] = table.concat(parts, " ")
    end
    local ok, err = pcall(action)
    print = realPrint
    if not ok then error(err, 0) end
    return table.concat(printedLines, "\n")
end

local realOpen = io.open
local function withoutSecureRandom(action)
    io.open = function(path, mode)
        if path == "/dev/urandom" then return nil, "unavailable" end
        return realOpen(path, mode)
    end
    local ok, err = pcall(action)
    io.open = realOpen
    if not ok then error(err, 0) end
end
-- luacheck: pop

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
check(not html:find("esc(", 1, true), "studio.html renders database values with textContent, not esc()-escaped HTML")
check(not html:find("innerHTML = html", 1, true), "data grid and schema view are not assembled from HTML strings")
check(not html:find("innerHTML = `", 1, true), "no template literal is parsed as markup")
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

-- ─── Request body delivery (FXServer setDataHandler) ────────────────

print("\n== Studio request body delivery ==")

startStudio()

local delivered = request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = "bob" }))
check(delivered.status == 200 and delivered.bodyRead, "the body is read through req.setDataHandler")

local forbiddenWrite = request("/api/tables/users/rows", "POST", { ["x-studio-token"] = "wrong" }, json.encode({ name = "x" }))
check(forbiddenWrite.status == 403 and not forbiddenWrite.bodyRead, "a bad token is rejected before the body is read")

local declaredTooLarge = request("/api/tables/users/rows", "POST",
    { ["x-studio-token"] = configuredToken, ["Content-Length"] = tostring(1024 * 1024 + 1) }, "{}")
check(declaredTooLarge.status == 422 and not declaredTooLarge.bodyRead, "a declared Content-Length over 1 MiB is rejected without reading the body")

local chunkedTooLarge = request("/api/tables/users/rows", "POST",
    { ["x-studio-token"] = configuredToken, ["Transfer-Encoding"] = "chunked" }, string.rep("x", 1024 * 1024 + 1))
check(chunkedTooLarge.status == 422, "a delivered body over 1 MiB is rejected before decoding")

sentQueries = {}
local chunkedInsert = request("/api/tables/users/rows", "POST",
    { ["x-studio-token"] = configuredToken, ["Transfer-Encoding"] = "chunked" }, json.encode({ name = "chunk" }))
check(chunkedInsert.status == 200 and #sentQueries == 1, "a chunked body is decoded once delivered")

local emptyDelete = request("/api/tables/users/rows", "DELETE", AUTH)
check(emptyDelete.status == 422 and not emptyDelete.bodyRead, "a request without a body answers without waiting for one")

-- ─── Bound values must be JSON scalars ──────────────────────────────

print("\n== Studio bound value types ==")

sentQueries = {}
check(request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = { nested = "x" } })).status == 422,
    "insert rejects an object value")
check(request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = { 1, 2 } })).status == 422,
    "insert rejects an array value")
check(request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id", pkValue = 1, data = { name = { a = 1 } } })).status == 422,
    "update rejects an object value in data")
check(request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id", pkValue = { 1, 2 }, data = { name = "x" } })).status == 422,
    "update rejects an array primary key value")
check(request("/api/tables/users/rows", "PUT", AUTH, json.encode({ pk = "id", pkValue = 1, data = { 1, 2 } })).status == 422,
    "update rejects data that is not an object of columns")
check(request("/api/tables/users/rows", "DELETE", AUTH, json.encode({ pk = "id", pkValue = { id = 1 } })).status == 422,
    "delete rejects an object primary key value")
check(#sentQueries == 0, "rejected non-scalar values send no query")

sentQueries = {}
local scalars = request("/api/tables/users/rows", "POST", AUTH, json.encode({ name = "a", money = 1.5, active = false }))
check(scalars.status == 200 and paramsContain(lastQuery().params, false), "strings, numbers and booleans are accepted")

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

print("\n== Studio bounded address stores ==")

local function fakeAddress(index)
    return ("10.%d.%d.%d:1"):format(index // 65536, (index // 256) % 256, index % 256)
end

startStudio({ orvex_studio_allow = "*" })
for _ = 1, 5 do request("/api/connection", "GET", {}, nil, "198.51.100.1:1") end
for _ = 1, 121 do request("/api/connection", "GET", AUTH, nil, "198.51.100.2:1") end
for index = 1, 2100 do request("/api/connection", "GET", {}, nil, fakeAddress(index)) end
check(request("/api/connection", "GET", AUTH, nil, "198.51.100.1:1").status == 429,
    "cycling 2100 addresses does not wipe an active lockout")
check(request("/api/connection", "GET", AUTH, nil, "198.51.100.2:1").status == 429,
    "cycling 2100 addresses does not wipe an exceeded rate window")

startStudio({ orvex_studio_allow = "*" })
for _ = 1, 5 do request("/api/connection", "GET", {}, nil, "198.51.100.1:1") end
now = now + 300
for index = 1, 2100 do request("/api/connection", "GET", {}, nil, fakeAddress(index)) end
for _ = 1, 4 do request("/api/connection", "GET", {}, nil, fakeAddress(2100)) end
check(request("/api/connection", "GET", AUTH, nil, fakeAddress(2100)).status == 429,
    "new addresses are still tracked once the stores are full")

os.time = realTime
studioCommand(0, { "stop" })

-- ─── Configured token strength ──────────────────────────────────────

print("\n== Studio configured token strength ==")

local function activationOutput(token)
    studioCommand(0, { "stop" })
    convars = { orvex_studio_token = token }
    return capturePrints(function() studioCommand(0, {}) end)
end

for label, weakToken in pairs({
    ["32 identical characters"] = string.rep("a", 32),
    ["a short token"] = "short-token",
    ["a repeated short pattern"] = string.rep("ab12", 16),
}) do
    local output = activationOutput(weakToken)
    check(request("/api/connection", "GET", { ["x-studio-token"] = weakToken }).status == 404,
        "Studio refuses to start with " .. label)
    check(output:find("openssl rand -hex 32", 1, true) ~= nil, "the refusal for " .. label .. " explains how to generate a token")
end

for label, strongToken in pairs({
    ["hex"] = configuredToken,
    ["base64"] = "q8Vn3ZkP0xR7tLw2Yb9cJ4mHs6Ea1UdFgKiOpNrTvXy=",
}) do
    activationOutput(strongToken)
    check(request("/api/connection", "GET", { ["x-studio-token"] = strongToken }).status == 200,
        "a random " .. label .. " token is accepted")
end

-- ─── Console banner ─────────────────────────────────────────────────

print("\n== Studio console banner ==")

local banner = activationOutput(configuredToken)
check(banner:find("reverse proxy", 1, true) ~= nil and banner:find("127.0.0.1", 1, true) ~= nil,
    "the banner warns that a same-host reverse proxy makes every client look like 127.0.0.1")
check(banner:find("?token=" .. configuredToken, 1, true) ~= nil, "the banner still prints the URL with its token")
check(banner:find("txAdmin", 1, true) ~= nil and banner:find("log files", 1, true) ~= nil,
    "the banner warns that the console output may be mirrored to txAdmin and log files")

-- ─── CSP nonce without a secure random source ───────────────────────

print("\n== Studio CSP nonce without /dev/urandom ==")

local NONCE_WARNING = "CSP nonce is weaker on this host"
local function countOccurrences(text, needle)
    local count, position = 0, 1
    while true do
        local found = text:find(needle, position, true)
        if not found then return count end
        count, position = count + 1, found + #needle
    end
end
local function nonceOf(response)
    return (response.headers["Content-Security-Policy"] or ""):match("'nonce%-(%x+)'")
end

local secureActivation = activationOutput(configuredToken)
check(countOccurrences(secureActivation, NONCE_WARNING) == 0, "no nonce warning when /dev/urandom is available")

local fallbackPages = {}
local fallbackOutput = capturePrints(function()
    withoutSecureRandom(function()
        studioCommand(0, { "stop" })
        convars = { orvex_studio_token = configuredToken }
        studioCommand(0, {})
        for index = 1, 3 do fallbackPages[index] = request("/?token=" .. configuredToken, "GET") end
    end)
end)
check(fallbackPages[1].status == 200, "the page is still served without /dev/urandom")
check(nonceOf(fallbackPages[1]) ~= nil and #nonceOf(fallbackPages[1]) == 32, "the fallback nonce is 128 bits of hex")
check(nonceOf(fallbackPages[1]) ~= nonceOf(fallbackPages[2]), "the fallback nonce changes on every page load")
check(fallbackPages[1].body:find('<script nonce="' .. nonceOf(fallbackPages[1]) .. '">', 1, true) ~= nil,
    "the fallback nonce is substituted into the page")
check(countOccurrences(fallbackOutput, NONCE_WARNING) == 1, "the weaker-nonce warning is printed once, at activation")
check(fallbackOutput:find("no HTML injection sink", 1, true) ~= nil, "the warning explains why the page stays safe")

local noTokenOutput = capturePrints(function()
    withoutSecureRandom(function()
        studioCommand(0, { "stop" })
        convars = {}
        studioCommand(0, {})
    end)
end)
check(request("/api/connection", "GET", AUTH).status == 404, "without /dev/urandom an unconfigured token still refuses activation")
check(noTokenOutput:find("openssl rand -hex 32", 1, true) ~= nil, "the token refusal still explains how to configure one")

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
