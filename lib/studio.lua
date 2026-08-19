-- lib/studio.lua
-- OrvexORM Studio — web database browser, 100% Lua, zero dependencies.
-- Uses FiveM's built-in HTTP handler + oxmysql for queries.
-- Commands: orvexstudio [port] / orvexstudio stop

local studioActive = false
local studioToken = nil
local studioTokenExpiresAt = 0
local Errors = OrvexErrors or require("utils.errors")
local Logger = OrvexLogger or require("utils.logger")

-- ─── Brute-force protection ─────────────────────────────────────────

local MAX_FAILED_ATTEMPTS = 5
local LOCKOUT_SECONDS = 300
local TOKEN_LIFETIME_SECONDS = 1800
local MAX_BODY_BYTES = 1024 * 1024
local REQUEST_WINDOW_SECONDS = 60
local MAX_REQUESTS_PER_WINDOW = 120

---@type table<string, { count: integer, lockedUntil: number }>
local failedAttempts = {}
local requestWindows = {}

local function boundedSet(store, key, value)
    local count = 0
    for _ in pairs(store) do
        count = count + 1
        if count >= 2048 then
            for existing in pairs(store) do store[existing] = nil end
            break
        end
    end
    store[key] = value
end

---@param address string
---@return boolean
local function isLockedOut(address)
    local entry = failedAttempts[address]
    if not entry then return false end
    if entry.lockedUntil > 0 and os.time() < entry.lockedUntil then
        return true
    end
    if entry.lockedUntil > 0 then
        failedAttempts[address] = nil
    end
    return false
end

---@param address string
local function registerFailure(address)
    local entry = failedAttempts[address] or { count = 0, lockedUntil = 0 }
    entry.count = entry.count + 1
    if entry.count >= MAX_FAILED_ATTEMPTS then
        entry.lockedUntil = os.time() + LOCKOUT_SECONDS
        print(("^1[OrvexORM Studio] %s locked out after %d failed token attempts.^0"):format(address, entry.count))
    end
    boundedSet(failedAttempts, address, entry)
end

-- ─── Token generation ──────────────────────────────────────────────

local function configuredToken()
    if type(GetConvar) ~= "function" then return nil end
    local token = GetConvar("orvex_studio_token", "")
    if #token >= 32 then return token end
    return nil
end

local function generateToken()
    local provided = configuredToken()
    if provided then return provided end

    local source = io.open("/dev/urandom", "rb")
    if not source then
        return nil, "Secure randomness is unavailable. Set orvex_studio_token to at least 32 random characters."
    end
    local bytes = source:read(32)
    source:close()
    if not bytes or #bytes ~= 32 then return nil, "Secure token generation failed." end
    return (bytes:gsub(".", function(byte) return ("%02x"):format(byte:byte()) end))
end

local function constantTimeEquals(left, right)
    if type(left) ~= "string" or type(right) ~= "string" then return false end
    local difference = #left ~ #right
    local length = math.max(#left, #right)
    for index = 1, length do
        difference = difference | ((left:byte(index) or 0) ~ (right:byte(index) or 0))
    end
    return difference == 0
end

local function exceedsRequestLimit(address)
    local now = os.time()
    local window = requestWindows[address]
    if not window or now - window.startedAt >= REQUEST_WINDOW_SECONDS then
        boundedSet(requestWindows, address, { startedAt = now, count = 1 })
        return false
    end
    window.count = window.count + 1
    return window.count > MAX_REQUESTS_PER_WINDOW
end

-- ─── JSON encoder (minimal, for API responses) ────────────────────

local function jsonEncode(val)
    if type(val) == "nil" then return "null" end
    if type(val) == "boolean" then return val and "true" or "false" end
    if type(val) == "number" then return tostring(val) end
    if type(val) == "string" then
        return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    end
    if type(val) == "table" then
        -- Array check
        if #val > 0 or next(val) == nil then
            local isArray = true
            local maxIdx = 0
            for k in pairs(val) do
                if type(k) ~= "number" then isArray = false; break end
                if k > maxIdx then maxIdx = k end
            end
            if maxIdx ~= #val then isArray = false end
            if isArray then
                local parts = {}
                for i, v in ipairs(val) do parts[i] = jsonEncode(v) end
                return "[" .. table.concat(parts, ",") .. "]"
            end
        end
        -- Object
        local parts = {}
        for k, v in pairs(val) do
            parts[#parts + 1] = jsonEncode(tostring(k)) .. ":" .. jsonEncode(v)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return '"' .. tostring(val) .. '"'
end

-- ─── JSON decoder (minimal, for POST body) ─────────────────────────

local function jsonDecode(str)
    if not str or str == "" then return nil end
    -- Use FiveM's json global if available
    if json and json.decode then
        local ok, result = pcall(json.decode, str)
        if ok then return result end
    end
    return nil
end

-- ─── SQL safe identifier ───────────────────────────────────────────

local function safeName(name)
    if not name or not name:match("^[%w_]+$") then return nil end
    return "`" .. name .. "`"
end

-- ─── DB query helpers ───────────────────────────────────────────────
-- Routed through the ORM adapter, so the Studio works with both
-- oxmysql and mysql-async (same auto-detection as the ORM itself).

local function dbQuery(sql, params)
    local ok, result = pcall(OrvexORM.raw, sql, params or {})
    if ok then return result end
    error(Errors.new("INTERNAL_ERROR", tostring(result)))
end

local function dbScalar(sql, params)
    local ok, result = pcall(OrvexORM.raw, sql, params or {})
    if ok and type(result) == "table" and result[1] then return result[1] end
    if ok then return result end
    error(Errors.new("INTERNAL_ERROR", tostring(result)))
end

local function dbInsert(sql, params)
    local ok, result = pcall(OrvexORM.rawExec, sql, params or {})
    if ok then return result end
    error(Errors.new("INTERNAL_ERROR", tostring(result)))
end

local function dbUpdate(sql, params)
    local ok, result = pcall(OrvexORM.rawExec, sql, params or {})
    if ok then return result end
    error(Errors.new("INTERNAL_ERROR", tostring(result)))
end

-- ─── API handlers ──────────────────────────────────────────────────

local function apiTables()
    local rows = dbQuery("SHOW TABLES")
    local tables = {}
    for _, row in ipairs(rows) do
        for _, v in pairs(row) do
            tables[#tables + 1] = v
            break
        end
    end
    return { tables = tables }
end

local function apiSchema(tableName)
    local tn = safeName(tableName)
    if not tn then error(Errors.new("VALIDATION_ERROR", "Invalid table name")) end
    local rows = dbQuery("DESCRIBE " .. tn)
    if not rows then error(Errors.new("NOT_FOUND", "Table not found")) end
    return { schema = rows }
end

local function apiCount(tableName)
    local tn = safeName(tableName)
    if not tn then error(Errors.new("VALIDATION_ERROR", "Invalid table name")) end
    local row = dbScalar("SELECT COUNT(*) as cnt FROM " .. tn)
    local cnt = row and (row.cnt or row["COUNT(*)"]) or 0
    return { count = tonumber(cnt) or 0 }
end

local function apiRows(tableName, params)
    local tn = safeName(tableName)
    if not tn then error(Errors.new("VALIDATION_ERROR", "Invalid table name")) end

    local page = tonumber(params.page) or 1
    local perPage = tonumber(params.perPage) or 25
    if page < 1 or page % 1 ~= 0 then error(Errors.new("VALIDATION_ERROR", "Page must be a positive integer")) end
    if perPage < 1 or perPage % 1 ~= 0 then error(Errors.new("VALIDATION_ERROR", "Page size must be a positive integer")) end
    perPage = math.min(100, perPage)
    local offset = (page - 1) * perPage

    local orderClause = ""
    if params.sort and safeName(params.sort) then
        local dir = params.dir == "desc" and "DESC" or "ASC"
        orderClause = " ORDER BY " .. safeName(params.sort) .. " " .. dir
    end

    local whereClause = ""
    local whereParams = {}
    if params.filter_col and params.filter_op and safeName(params.filter_col) then
        local col = safeName(params.filter_col)
        local op = params.filter_op
        local allowed = { ["="] = true, ["!="] = true, [">"] = true, ["<"] = true, [">="] = true, ["<="] = true, ["LIKE"] = true, ["IS NULL"] = true, ["IS NOT NULL"] = true }
        if allowed[op] then
            if op == "IS NULL" then
                whereClause = " WHERE " .. col .. " IS NULL"
            elseif op == "IS NOT NULL" then
                whereClause = " WHERE " .. col .. " IS NOT NULL"
            else
                whereClause = " WHERE " .. col .. " " .. op .. " ?"
                local val = params.filter_val or ""
                if #val > 512 then error(Errors.new("VALIDATION_ERROR", "Filter value is too long")) end
                whereParams[1] = op == "LIKE" and ("%" .. val .. "%") or val
            end
        end
    end

    local sql = "SELECT * FROM " .. tn .. whereClause .. orderClause .. " LIMIT ? OFFSET ?"
    local qParams = {}
    for _, v in ipairs(whereParams) do qParams[#qParams + 1] = v end
    qParams[#qParams + 1] = perPage
    qParams[#qParams + 1] = offset

    local rows = dbQuery(sql, qParams)

    local countRow = dbScalar("SELECT COUNT(*) as cnt FROM " .. tn .. whereClause, whereParams)
    local total = countRow and (tonumber(countRow.cnt) or tonumber(countRow["COUNT(*)"])) or 0

    return { rows = rows, total = total, page = page, perPage = perPage }
end

local function apiInsert(tableName, body)
    local tn = safeName(tableName)
    if not tn then error(Errors.new("VALIDATION_ERROR", "Invalid table name")) end
    if not body or type(body) ~= "table" then error(Errors.new("VALIDATION_ERROR", "Missing JSON body")) end

    local cols, vals, placeholders = {}, {}, {}
    for k, v in pairs(body) do
        local sc = safeName(k)
        if sc then
            cols[#cols + 1] = sc
            vals[#vals + 1] = v
            placeholders[#placeholders + 1] = "?"
        end
    end
    if #cols == 0 then error(Errors.new("VALIDATION_ERROR", "No valid columns")) end

    local sql = "INSERT INTO " .. tn .. " (" .. table.concat(cols, ", ") .. ") VALUES (" .. table.concat(placeholders, ", ") .. ")"
    local id = dbInsert(sql, vals)
    return { success = true, insertId = id }
end

local function apiUpdate(tableName, body)
    local tn = safeName(tableName)
    if not tn then error(Errors.new("VALIDATION_ERROR", "Invalid table name")) end
    if not body or not body.pk or not body.data then error(Errors.new("VALIDATION_ERROR", "Missing pk or data")) end

    local pkCol = safeName(body.pk)
    if not pkCol then error(Errors.new("VALIDATION_ERROR", "Invalid primary key")) end

    if body.pkValue == nil then error(Errors.new("VALIDATION_ERROR", "Missing primary key value")) end

    local setClauses, vals = {}, {}
    for k, v in pairs(body.data) do
        local sc = safeName(k)
        if sc then
            setClauses[#setClauses + 1] = sc .. " = ?"
            vals[#vals + 1] = v
        end
    end
    if #setClauses == 0 then error(Errors.new("VALIDATION_ERROR", "No valid columns")) end
    vals[#vals + 1] = body.pkValue

    local sql = "UPDATE " .. tn .. " SET " .. table.concat(setClauses, ", ") .. " WHERE " .. pkCol .. " = ?"
    local affected = dbUpdate(sql, vals)
    return { success = true, affectedRows = affected }
end

local function apiDelete(tableName, body)
    local tn = safeName(tableName)
    if not tn then error(Errors.new("VALIDATION_ERROR", "Invalid table name")) end
    if not body or not body.pk then error(Errors.new("VALIDATION_ERROR", "Missing primary key")) end

    local pkCol = safeName(body.pk)
    if not pkCol then error(Errors.new("VALIDATION_ERROR", "Invalid primary key")) end
    if body.pkValue == nil then error(Errors.new("VALIDATION_ERROR", "Missing primary key value")) end

    local sql = "DELETE FROM " .. tn .. " WHERE " .. pkCol .. " = ? LIMIT 1"
    local affected = dbUpdate(sql, { body.pkValue })
    return { success = true, affectedRows = affected }
end

local function apiConnection()
    return { connected = true }
end

-- ─── URL query string parser ───────────────────────────────────────

local function parseQuery(queryString)
    local params = {}
    if not queryString then return params end
    for k, v in queryString:gmatch("([^&=]+)=([^&]*)") do
        v = v:gsub("%+", " ")
        params[k] = v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    end
    return params
end

-- ─── Frontend HTML ─────────────────────────────────────────────────

local function getStudioHTML()
    local resourcePath = GetResourcePath(GetCurrentResourceName())
    local f = io.open(resourcePath .. "/studio.html", "r")
    if f then
        local content = f:read("*a")
        f:close()
        return content
    end
    return "<html><body><h1>OrvexORM Studio</h1><p>studio.html not found</p></body></html>"
end

-- ─── HTTP Handler ──────────────────────────────────────────────────

local function correlationIdFrom(req)
    local headers = req.headers or {}
    local supplied = headers["x-correlation-id"] or headers["X-Correlation-Id"]
    if type(supplied) == "string" and supplied:match("^[%w%-_]+$") and #supplied <= 80 then return supplied end
    return Errors.generateId("REQ")
end

local function sendJson(res, status, payload, correlationId)
    res.writeHead(status, {
        ["Content-Type"] = "application/json; charset=utf-8",
        ["Cache-Control"] = "no-store",
        ["X-Correlation-Id"] = correlationId,
        ["X-Content-Type-Options"] = "nosniff",
        ["X-Frame-Options"] = "DENY",
        ["Referrer-Policy"] = "no-referrer",
    })
    res.send(jsonEncode(payload))
end

local function sendError(res, thrown, context)
    local appError = Errors.normalize(thrown)
    local errorId = appError.status >= 500 and Errors.generateId("ERR") or nil
    local logContext = {
        errorId = errorId,
        correlationId = context.correlationId,
        errorCode = appError.code,
        route = context.route,
        method = context.method,
        technicalMessage = appError.technicalMessage,
        stack = context.stack,
    }
    if appError.level == "error" then Logger.error("Studio request failed", logContext)
    elseif appError.level == "warn" then Logger.warn("Studio request rejected", logContext) end
    sendJson(res, appError.status, Errors.toResponse(appError, errorId), context.correlationId)
end

local function dispatchApi(path, method, params, body)
    if path == "/api/tables" and method == "GET" then return apiTables() end
    local tableName = path:match("^/api/tables/([^/]+)/schema$")
    if tableName and method == "GET" then return apiSchema(tableName) end
    tableName = path:match("^/api/tables/([^/]+)/count$")
    if tableName and method == "GET" then return apiCount(tableName) end
    tableName = path:match("^/api/tables/([^/]+)/rows$")
    if tableName and method == "GET" then return apiRows(tableName, params) end
    if tableName and method == "POST" then return apiInsert(tableName, body) end
    if tableName and method == "PUT" then return apiUpdate(tableName, body) end
    if tableName and method == "DELETE" then return apiDelete(tableName, body) end
    if path == "/api/connection" and method == "GET" then return apiConnection() end
    error(Errors.new("NOT_FOUND", "Unknown Studio route"))
end

local function handleRequest(req, res)
    local correlationId = correlationIdFrom(req)
    if not studioActive then
        sendError(res, Errors.new("SERVICE_UNAVAILABLE", "Studio is inactive"), {
            correlationId = correlationId, route = req.path, method = req.method,
        })
        return
    end

    -- Strip the port so lockouts apply per host, not per connection
    local address = (req.address or "unknown"):match("^(.-):%d+$") or req.address or "unknown"
    if exceedsRequestLimit(address) then
        sendError(res, Errors.new("RATE_LIMITED", "Studio request rate exceeded"), {
            correlationId = correlationId, route = req.path, method = req.method,
        })
        return
    end
    if isLockedOut(address) then
        sendError(res, Errors.new("RATE_LIMITED", "Studio token lockout"), {
            correlationId = correlationId, route = req.path, method = req.method,
        })
        return
    end

    local path = req.path or "/"
    local method = req.method or "GET"
    if #path > 2048 then
        sendError(res, Errors.new("VALIDATION_ERROR", "Request path exceeds the size limit"), {
            correlationId = correlationId, route = "[oversized]", method = method,
        })
        return
    end

    -- Parse query string
    local queryString = ""
    if path:find("?") then
        queryString = path:match("%?(.+)$") or ""
        path = path:match("^([^?]+)")
    end
    local params = parseQuery(queryString)

    -- Token check
    local headers = req.headers or {}
    local requestToken = headers["x-studio-token"] or headers["X-Studio-Token"] or params.token
    if os.time() >= studioTokenExpiresAt then
        studioActive = false
        studioToken = nil
        sendError(res, Errors.new("AUTHENTICATION_REQUIRED", "Studio token expired"), {
            correlationId = correlationId, route = path, method = method,
        })
        return
    end
    if not constantTimeEquals(requestToken, studioToken) then
        registerFailure(address)
        sendError(res, Errors.new("FORBIDDEN", "Invalid or missing Studio token"), {
            correlationId = correlationId, route = path, method = method,
        })
        return
    end
    failedAttempts[address] = nil

    -- Route: frontend
    if path == "/" or path == "" then
        res.writeHead(200, {
            ["Content-Type"] = "text/html; charset=utf-8",
            ["Cache-Control"] = "no-store",
            ["Content-Security-Policy"] = "default-src 'none'; connect-src 'self'; img-src 'self' data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
            ["X-Content-Type-Options"] = "nosniff",
            ["X-Frame-Options"] = "DENY",
            ["Referrer-Policy"] = "no-referrer",
            ["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()",
        })
        res.send(getStudioHTML())
        return
    end

    local hasBody = method == "POST" or method == "PUT" or method == "DELETE"
    if hasBody and type(req.body) == "string" and #req.body > MAX_BODY_BYTES then
        sendError(res, Errors.new("VALIDATION_ERROR", "Studio request body exceeds the size limit"), {
            correlationId = correlationId, route = path, method = method,
        })
        return
    end
    local body = hasBody and jsonDecode(req.body) or nil
    if (method == "POST" or method == "PUT" or method == "DELETE") and req.body and req.body ~= "" and not body then
        sendError(res, Errors.new("VALIDATION_ERROR", "Malformed JSON body"), {
            correlationId = correlationId, route = path, method = method,
        })
        return
    end

    local stack
    local ok, result = xpcall(function() return dispatchApi(path, method, params, body) end, function(thrown)
        stack = debug and debug.traceback and debug.traceback("", 2) or nil
        return thrown
    end)
    if ok then sendJson(res, 200, result, correlationId)
    else sendError(res, result, { correlationId = correlationId, route = path, method = method, stack = stack }) end
end

-- ─── Register HTTP handler ─────────────────────────────────────────

SetHttpHandler(handleRequest)

-- ─── Console command ───────────────────────────────────────────────

RegisterCommand("orvexstudio", function(source, args)
    if source ~= 0 then
        print("^1[OrvexORM Studio] Console only.^0")
        return
    end

    local action = args[1]

    if action == "stop" then
        if not studioActive then
            print("^1[OrvexORM Studio] Not running.^0")
            return
        end
        studioActive = false
        studioToken = nil
        studioTokenExpiresAt = 0
        failedAttempts = {}
        requestWindows = {}
        print("^2[OrvexORM Studio]^0 Studio stopped.")
        return
    end

    if studioActive then
        print("^3[OrvexORM Studio] Already running. Use 'orvexstudio stop' to stop.^0")
        return
    end

    -- Activate
    local token, tokenError = generateToken()
    if not token then
        Logger.error("Studio activation refused", { technicalMessage = tokenError })
        print("^1[OrvexORM Studio] " .. tokenError .. "^0")
        return
    end
    studioToken = token
    studioTokenExpiresAt = os.time() + TOKEN_LIFETIME_SECONDS
    studioActive = true

    -- Get the resource HTTP endpoint
    local endpoint = GetCurrentResourceName()

    print("")
    print("^5══════════════════════════════════════════════════^0")
    print("^5  OrvexORM Studio^0")
    print("^5══════════════════════════════════════════════════^0")
    print("")
    print("^2  URL : ^6http://localhost:30120/" .. endpoint .. "/?token=" .. studioToken .. "^0")
    print("")
    print("^3  Share this URL only with trusted people.^0")
    print("^3  The endpoint is reachable on the public game port:^0")
    print("^3  stop the Studio as soon as you are done.^0")
    print("^3  Type 'orvexstudio stop' to stop.^0")
    print("^3  This Studio session expires after 30 minutes.^0")
    print("")
    print("^5══════════════════════════════════════════════════^0")
    print("")
end, true)
