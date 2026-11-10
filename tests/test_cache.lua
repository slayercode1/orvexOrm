-- tests/test_cache.lua
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_cache.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Cache = require("utils.cache")

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

local function isHit(cache, key)
    local _, hit = cache:get(key)
    return hit
end

local realTime = os.time
local function withClock(start, fn)
    local now = start
    os.time = function() return now end
    local ok, err = pcall(fn, function(seconds) now = now + seconds end)
    os.time = realTime
    if not ok then error(err, 0) end
end

print("\n== Collision-free cache keys ==")

local sql = "SELECT * FROM users WHERE identifier = ? AND job = ?"
check(Cache.makeKey(sql, { "x:y", "z" }) ~= Cache.makeKey(sql, { "x", "y:z" }),
    "values shifted around ':' produce different keys")
check(Cache.makeKey("q ?", { 1 }) ~= Cache.makeKey("q ?", { "1" }),
    "number 1 and string '1' produce different keys")
check(Cache.makeKey("q ?", { true }) ~= Cache.makeKey("q ?", { "true" }),
    "boolean true and string 'true' produce different keys")
check(Cache.makeKey("q:1", {}) ~= Cache.makeKey("q", { 1 }),
    "sql suffix cannot impersonate a parameter")
check(Cache.makeKey("q ? ? ? ?", { "a", "b", "c", "d" }) ~= Cache.makeKey("q ? ? ? ?", { "a", "b", "c:d", "" }),
    "long parameter lists stay collision-free")
check(Cache.makeKey(sql, { "license:abc", "police" }) == Cache.makeKey(sql, { "license:abc", "police" }),
    "identical queries share a key")
check(Cache.makeKey("SELECT 1", nil) == Cache.makeKey("SELECT 1", {}),
    "nil and empty params share a key")
check(Cache.makeKey("q ?", { 100000000000001.0 }) ~= Cache.makeKey("q ?", { 100000000000002.0 }),
    "floats equal to 14 significant digits produce different keys")
check(Cache.makeKey("q ?", { 0.1 + 0.2 }) ~= Cache.makeKey("q ?", { 0.3 }),
    "0.1 + 0.2 and 0.3 produce different keys")
check(Cache.makeKey("q ?", { 1.0 }) ~= Cache.makeKey("q ?", { 1 }),
    "float 1.0 and integer 1 produce different keys")
check(Cache.makeKey("q ?", { 0.5 }) == Cache.makeKey("q ?", { 1 / 2 }),
    "equal floats share a key")

print("\n== Uncacheable parameters ==")

check(Cache.makeKey("q ?", { { 1, 2 } }) == nil, "table parameter makes the query uncacheable")
check(Cache.makeKey("q ? ?", { 1, function() end }) == nil, "function parameter makes the query uncacheable")

local guarded = Cache.new({ ttl = 60, enabled = true })
local ok = pcall(function() guarded:set(nil, { 1 }) end)
check(ok, "set with a nil key is a no-op")
check(guarded:size() == 0, "nil key is never stored")
local value, hit = guarded:get(nil)
check(value == nil and hit == false, "get with a nil key misses")
check(guarded:stats().misses == 0, "uncacheable lookups are not counted as misses")

print("\n== Exact table invalidation ==")

local byTable = Cache.new({ ttl = 60, enabled = true })
byTable:set(Cache.makeKey("SELECT * FROM users WHERE id = ?", { 1 }), "u")
byTable:set(Cache.makeKey("SELECT * FROM users_logs WHERE id = ?", { 1 }), "ul")
byTable:set(Cache.makeKey("SELECT * FROM items WHERE owner = ?", { "users" }), "i")
byTable:set(Cache.makeKey("SELECT v.* FROM vehicles v INNER JOIN users ON users.id = v.owner", {}), "j")
byTable:invalidateTable("users")
check(not isHit(byTable, Cache.makeKey("SELECT * FROM users WHERE id = ?", { 1 })), "users entry purged")
check(isHit(byTable, Cache.makeKey("SELECT * FROM users_logs WHERE id = ?", { 1 })), "users_logs entry kept")
check(isHit(byTable, Cache.makeKey("SELECT * FROM items WHERE owner = ?", { "users" })),
    "entry whose parameter value is the table name kept")
check(not isHit(byTable, Cache.makeKey("SELECT v.* FROM vehicles v INNER JOIN users ON users.id = v.owner", {})),
    "entry joining the table purged")

byTable:set("SELECT * FROM `db`.`Accounts` WHERE id = 1", "a")
byTable:invalidateTable("accounts")
check(not isHit(byTable, "SELECT * FROM `db`.`Accounts` WHERE id = 1"), "quoted, schema-qualified table purged")

byTable:set("SELECT * FROM players WHERE id IN (SELECT player_id FROM bans)", "s")
byTable:invalidateTable("bans")
check(not isHit(byTable, "SELECT * FROM players WHERE id IN (SELECT player_id FROM bans)"), "subquery table purged")

byTable:set("CALL opaque_procedure()", "raw")
byTable:invalidateTable("anything")
check(not isHit(byTable, "CALL opaque_procedure()"), "entry without known table purged by any write")

byTable:set("explicit", "e", nil, { "zones" })
byTable:invalidateTable("zones")
check(not isHit(byTable, "explicit"), "explicit table list is honoured")

local qualifiedFind = Cache.makeKey("SELECT * FROM `gamedb`.`users` WHERE `id` = ? LIMIT 1", { 5 })
byTable:set(qualifiedFind, "stale")
byTable:invalidateTable("gamedb.users")
check(not isHit(byTable, qualifiedFind), "write through a schema-qualified model purges its reads")
byTable:set(qualifiedFind, "stale")
byTable:invalidateTable("`GameDB`.`Users`")
check(not isHit(byTable, qualifiedFind), "quoted, mixed-case qualified invalidation purges its reads")

byTable:set("explicit qualified", "eq", nil, { "gamedb.zones" })
byTable:invalidateTable("zones")
check(not isHit(byTable, "explicit qualified"), "qualified explicit table list is indexed by bare name")

local commaJoin = "SELECT p.* FROM players p, bans b WHERE b.pid = p.id"
byTable:set(commaJoin, "cj")
byTable:invalidateTable("bans")
check(not isHit(byTable, commaJoin), "comma-joined table purged")
local commaSubquery = "SELECT * FROM players WHERE id NOT IN (SELECT p.id FROM players p, bans b WHERE b.pid = p.id)"
byTable:set(commaSubquery, "cs")
byTable:invalidateTable("bans")
check(not isHit(byTable, commaSubquery), "comma-joined table inside a subquery purged")

local before = byTable:size()
byTable:invalidateTable("unknown_table")
check(byTable:size() == before, "invalidating an untouched table removes nothing")

print("\n== Bounded size with LRU eviction ==")

local lru = Cache.new({ ttl = 60, enabled = true, maxEntries = 3 })
lru:set("a", 1)
lru:set("b", 2)
lru:set("c", 3)
lru:get("a")
lru:set("d", 4)
check(lru:size() == 3, "size never exceeds maxEntries")
check(not isHit(lru, "b"), "least recently used entry evicted")
check(isHit(lru, "a") and isHit(lru, "c") and isHit(lru, "d"), "recently used entries kept")
lru:set("c", 33)
check(lru:size() == 3 and select(1, lru:get("c")) == 33, "overwriting a key does not grow the cache")

local bulk = Cache.new({ ttl = 60, enabled = true, maxEntries = 100 })
for i = 1, 1000 do bulk:set("SELECT * FROM t WHERE id = " .. i, i) end
check(bulk:size() == 100, "bulk inserts stay bounded")
bulk:invalidateTable("t")
check(bulk:size() == 0, "size tracks invalidation")

local counted = Cache.new({ ttl = 60, enabled = true })
counted:set("x", 1)
counted:set("x", 2)
counted:set("y", 3)
counted:invalidate("x")
counted:invalidate("missing")
check(counted:size() == 1, "size stays exact after overwrite and invalidate")
counted:invalidatePrefix("y")
check(counted:size() == 0, "size stays exact after invalidatePrefix")

local prefixed = Cache.new({ ttl = 60, enabled = true })
prefixed:set("SELECT * FROM users WHERE id = ?:1", "u1")
prefixed:set("SELECT * FROM users WHERE id = ?:2", "u2")
prefixed:set("SELECT * FROM users_logs:1", "log")
prefixed:set("x SELECT * FROM users WHERE id = ?:3", "not a prefix")
prefixed:invalidatePrefix("SELECT * FROM users WHERE id = ?")
check(not isHit(prefixed, "SELECT * FROM users WHERE id = ?:1") and not isHit(prefixed, "SELECT * FROM users WHERE id = ?:2"),
    "invalidatePrefix removes every key starting with the prefix")
check(isHit(prefixed, "SELECT * FROM users_logs:1") and isHit(prefixed, "x SELECT * FROM users WHERE id = ?:3"),
    "invalidatePrefix keeps keys that only contain the prefix elsewhere")
prefixed:invalidatePrefix("%.*")
check(prefixed:size() == 2, "invalidatePrefix treats the prefix as plain text, not a pattern")
prefixed:invalidateTable("users_logs")
check(not isHit(prefixed, "SELECT * FROM users_logs:1") and prefixed:size() == 1,
    "entries removed by prefix leave the table index consistent")
counted:set("z", 1)
counted:flush()
check(counted:size() == 0 and not isHit(counted, "z"), "flush resets everything")

print("\n== Per-entry row budget ==")

local budget = Cache.new({ ttl = 60, enabled = true, maxRows = 2 })
budget:set("small", { 1, 2 })
budget:set("large", { 1, 2, 3 })
budget:set("scalar", 42)
check(isHit(budget, "small"), "result within the row budget is cached")
check(not isHit(budget, "large") and budget:size() == 2, "result over the row budget is not cached")
check(isHit(budget, "scalar"), "non-table result is cached")
budget:set("small", { 1, 2, 3 })
check(not isHit(budget, "small"), "oversized result replaces, never keeps, the previous entry")

local defaultBudget = Cache.new({ ttl = 60, enabled = true })
local rows = {}
for i = 1, 5001 do rows[i] = i end
defaultBudget:set("huge", rows)
check(not isHit(defaultBudget, "huge"), "default row budget is 5000")
rows[5001] = nil
defaultBudget:set("huge", rows)
check(isHit(defaultBudget, "huge"), "5000 rows fit the default budget")

print("\n== Expired entries are purged ==")

withClock(1000, function(advance)
    local sweeping = Cache.new({ ttl = 10, enabled = true })
    for i = 1, 50 do sweeping:set("SELECT * FROM t WHERE id = " .. i, i) end
    advance(11)
    sweeping:set("SELECT * FROM other", true)
    check(sweeping:size() == 1, "expired entries swept without being read")
    check(isHit(sweeping, "SELECT * FROM other"), "fresh entry survives the sweep")
    sweeping:invalidateTable("t")
    check(sweeping:size() == 1, "swept entries left no stale index")
end)

withClock(1000, function(advance)
    local purgeable = Cache.new({ ttl = 10, enabled = true })
    purgeable:set("old", 1)
    advance(5)
    purgeable:set("new", 2, 60)
    advance(6)
    check(purgeable:purgeExpired() == 1, "purgeExpired returns the number of removed entries")
    check(purgeable:size() == 1 and isHit(purgeable, "new"), "purgeExpired keeps live entries")
end)

print("\n== Backward compatibility ==")

local compat = Cache.new({ ttl = 60, enabled = true })
compat:set("SELECT * FROM users:1", "r1")
compat:set("SELECT * FROM vehicles:1", "r3")
compat:invalidateTable("users")
check(not isHit(compat, "SELECT * FROM users:1"), "hand-written keys still invalidated by table")
check(isHit(compat, "SELECT * FROM vehicles:1"), "hand-written keys of other tables kept")
check(Cache.makeKey("SELECT * FROM users WHERE id = ?", { 1 }):find("SELECT * FROM users WHERE id = ?:1", 1, true) ~= nil,
    "key stays readable for debugging")
local disabled = Cache.new({ enabled = false })
disabled:set("k", 1)
check(not isHit(disabled, "k") and disabled:size() == 0, "disabled cache stores nothing")

print(("\n== Results: %d passed, %d failed ==\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
