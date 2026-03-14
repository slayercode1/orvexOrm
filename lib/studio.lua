-- lib/studio.lua
-- OrvexORM Studio — web database browser, 100% Lua, zero dependencies.
-- Uses FiveM's built-in HTTP handler + oxmysql for queries.
-- Commands: orvexstudio [port] / orvexstudio stop

local studioActive = false
local studioToken = nil
local studioPort = nil

-- ─── Token generation ──────────────────────────────────────────────

local function generateToken()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local t = {}
    for i = 1, 48 do
        local idx = math.random(1, #chars)
        t[i] = chars:sub(idx, idx)
    end
    return table.concat(t)
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

-- ─── DB query helpers (uses oxmysql sync exports) ──────────────────

local function dbQuery(sql, params)
    local ok, result = pcall(exports.oxmysql.executeSync, exports.oxmysql, sql, params or {})
    if ok then return result end
    return nil, result
end

local function dbScalar(sql, params)
    local ok, result = pcall(exports.oxmysql.executeSync, exports.oxmysql, sql, params or {})
    if ok and type(result) == "table" and result[1] then return result[1] end
    if ok then return result end
    return nil, result
end

local function dbInsert(sql, params)
    local ok, result = pcall(exports.oxmysql.insertSync, exports.oxmysql, sql, params or {})
    if ok then return result end
    return nil, result
end

local function dbUpdate(sql, params)
    local ok, result = pcall(exports.oxmysql.updateSync, exports.oxmysql, sql, params or {})
    if ok then return result end
    return nil, result
end

-- ─── API handlers ──────────────────────────────────────────────────

local function apiTables()
    local rows = dbQuery("SHOW TABLES")
    if not rows then return jsonEncode({ error = "Failed to fetch tables" }) end
    local tables = {}
    for _, row in ipairs(rows) do
        for _, v in pairs(row) do
            tables[#tables + 1] = v
            break
        end
    end
    return jsonEncode({ tables = tables })
end

local function apiSchema(tableName)
    local tn = safeName(tableName)
    if not tn then return jsonEncode({ error = "Invalid table name" }) end
    local rows = dbQuery("DESCRIBE " .. tn)
    if not rows then return jsonEncode({ error = "Table not found" }) end
    return jsonEncode({ schema = rows })
end

local function apiCount(tableName)
    local tn = safeName(tableName)
    if not tn then return jsonEncode({ error = "Invalid table name" }) end
    local row = dbScalar("SELECT COUNT(*) as cnt FROM " .. tn)
    local cnt = row and (row.cnt or row["COUNT(*)"]) or 0
    return jsonEncode({ count = tonumber(cnt) or 0 })
end

local function apiRows(tableName, params)
    local tn = safeName(tableName)
    if not tn then return jsonEncode({ error = "Invalid table name" }) end

    local page = tonumber(params.page) or 1
    local perPage = math.min(100, math.max(1, tonumber(params.perPage) or 25))
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
                whereParams[1] = op == "LIKE" and ("%" .. val .. "%") or val
            end
        end
    end

    local sql = "SELECT * FROM " .. tn .. whereClause .. orderClause .. " LIMIT ? OFFSET ?"
    local qParams = {}
    for _, v in ipairs(whereParams) do qParams[#qParams + 1] = v end
    qParams[#qParams + 1] = perPage
    qParams[#qParams + 1] = offset

    local rows = dbQuery(sql, qParams) or {}

    local countRow = dbScalar("SELECT COUNT(*) as cnt FROM " .. tn .. whereClause, whereParams)
    local total = countRow and (tonumber(countRow.cnt) or tonumber(countRow["COUNT(*)"])) or 0

    return jsonEncode({ rows = rows, total = total, page = page, perPage = perPage })
end

local function apiInsert(tableName, body)
    local tn = safeName(tableName)
    if not tn then return jsonEncode({ error = "Invalid table name" }) end
    if not body or type(body) ~= "table" then return jsonEncode({ error = "No data" }) end

    local cols, vals, placeholders = {}, {}, {}
    for k, v in pairs(body) do
        local sc = safeName(k)
        if sc then
            cols[#cols + 1] = sc
            vals[#vals + 1] = v
            placeholders[#placeholders + 1] = "?"
        end
    end
    if #cols == 0 then return jsonEncode({ error = "No valid columns" }) end

    local sql = "INSERT INTO " .. tn .. " (" .. table.concat(cols, ", ") .. ") VALUES (" .. table.concat(placeholders, ", ") .. ")"
    local id, err = dbInsert(sql, vals)
    if err then return jsonEncode({ error = tostring(err) }) end
    return jsonEncode({ success = true, insertId = id })
end

local function apiUpdate(tableName, body)
    local tn = safeName(tableName)
    if not tn then return jsonEncode({ error = "Invalid table name" }) end
    if not body or not body.pk or not body.data then return jsonEncode({ error = "Missing pk or data" }) end

    local pkCol = safeName(body.pk)
    if not pkCol then return jsonEncode({ error = "Invalid pk" }) end

    local setClauses, vals = {}, {}
    for k, v in pairs(body.data) do
        local sc = safeName(k)
        if sc then
            setClauses[#setClauses + 1] = sc .. " = ?"
            vals[#vals + 1] = v
        end
    end
    vals[#vals + 1] = body.pkValue

    local sql = "UPDATE " .. tn .. " SET " .. table.concat(setClauses, ", ") .. " WHERE " .. pkCol .. " = ?"
    local affected, err = dbUpdate(sql, vals)
    if err then return jsonEncode({ error = tostring(err) }) end
    return jsonEncode({ success = true, affectedRows = affected })
end

local function apiDelete(tableName, body)
    local tn = safeName(tableName)
    if not tn then return jsonEncode({ error = "Invalid table name" }) end
    if not body or not body.pk then return jsonEncode({ error = "Missing pk" }) end

    local pkCol = safeName(body.pk)
    if not pkCol then return jsonEncode({ error = "Invalid pk" }) end

    local sql = "DELETE FROM " .. tn .. " WHERE " .. pkCol .. " = ? LIMIT 1"
    local affected, err = dbUpdate(sql, { body.pkValue })
    if err then return jsonEncode({ error = tostring(err) }) end
    return jsonEncode({ success = true, affectedRows = affected })
end

local function apiConnection()
    local connStr = GetConvar("mysql_connection_string", "")
    local host, db, user = "unknown", "unknown", "unknown"
    -- Parse mysql://user:pass@host/database
    local u, h, d = connStr:match("mysql://([^:]+):[^@]+@([^/]+)/([^?]+)")
    if u then user, host, db = u, h, d end
    return jsonEncode({ host = host, database = db, user = user })
end

-- ─── URL query string parser ───────────────────────────────────────

local function parseQuery(queryString)
    local params = {}
    if not queryString then return params end
    for k, v in queryString:gmatch("([^&=]+)=([^&]*)") do
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

local function handleRequest(req, res)
    if not studioActive then
        res.send(jsonEncode({ error = "Studio not active" }))
        return
    end

    local path = req.path or "/"
    local method = req.method or "GET"

    -- Parse query string
    local queryString = ""
    if path:find("?") then
        queryString = path:match("%?(.+)$") or ""
        path = path:match("^([^?]+)")
    end
    local params = parseQuery(queryString)

    -- Token check
    local urlToken = params.token
    if not urlToken or urlToken ~= studioToken then
        res.writeHead(403, { ["Content-Type"] = "application/json" })
        res.send(jsonEncode({ error = "Access denied. Invalid or missing token." }))
        return
    end

    -- Route: frontend
    if path == "/" or path == "" then
        res.writeHead(200, { ["Content-Type"] = "text/html; charset=utf-8" })
        res.send(getStudioHTML())
        return
    end

    -- API routes
    res.writeHead(200, { ["Content-Type"] = "application/json" })

    if path == "/api/tables" and method == "GET" then
        res.send(apiTables())
    elseif path:match("^/api/tables/([^/]+)/schema$") then
        res.send(apiSchema(path:match("^/api/tables/([^/]+)/schema$")))
    elseif path:match("^/api/tables/([^/]+)/count$") then
        res.send(apiCount(path:match("^/api/tables/([^/]+)/count$")))
    elseif path:match("^/api/tables/([^/]+)/rows$") and method == "GET" then
        res.send(apiRows(path:match("^/api/tables/([^/]+)/rows$"), params))
    elseif path:match("^/api/tables/([^/]+)/rows$") and method == "POST" then
        local body = jsonDecode(req.body)
        res.send(apiInsert(path:match("^/api/tables/([^/]+)/rows$"), body))
    elseif path:match("^/api/tables/([^/]+)/rows$") and method == "PUT" then
        local body = jsonDecode(req.body)
        res.send(apiUpdate(path:match("^/api/tables/([^/]+)/rows$"), body))
    elseif path:match("^/api/tables/([^/]+)/rows$") and method == "DELETE" then
        local body = jsonDecode(req.body)
        res.send(apiDelete(path:match("^/api/tables/([^/]+)/rows$"), body))
    elseif path == "/api/connection" then
        res.send(apiConnection())
    else
        res.send(jsonEncode({ error = "Not found" }))
    end
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
        print("^2[OrvexORM Studio]^0 Studio stopped.")
        return
    end

    if studioActive then
        print("^3[OrvexORM Studio] Already running. Use 'orvexstudio stop' to stop.^0")
        return
    end

    -- Activate
    studioToken = generateToken()
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
    print("^3  Type 'orvexstudio stop' to stop.^0")
    print("")
    print("^5══════════════════════════════════════════════════^0")
    print("")
end, true)
