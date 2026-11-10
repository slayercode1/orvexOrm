-- tests/test_relations.lua
-- Relations: lazy and eager loading, whereHas, countByRelation, nested writes, inline relations.
-- Run: docker run --rm -v "$(pwd)":/app -w /app nickblah/lua:5.4 lua tests/test_relations.lua

package.path = "./?/init.lua;./?.lua;" .. package.path

local Mock = require("tests.support.fivem_mock")
local T = require("tests.support.harness")

local dbLog, mockResults, txLog = Mock.log, Mock.results, Mock.txLog
local reset = Mock.reset

-- ─── Fixtures ──────────────────────────────────────────────────────

local ORM = require("core.orm")

local User = ORM.model("users", {
    identifier = "string",
    money      = "number",
    job        = "string",
}, { primaryKey = "identifier" })

-- ─── Test: Relations ───────────────────────────────────────────────

T.section("Relations")

reset()
local Profile = ORM.model("profiles", {
    id = "number", user_id = "string", bio = "string",
}, { primaryKey = "id" })

local Vehicle = ORM.model("vehicles", {
    id = "number", owner_id = "string", plate = "string",
}, { primaryKey = "id" })

local Role = ORM.model("roles", {
    id = "number", name = "string",
}, { primaryKey = "id" })

User.hasOne("profile", Profile, { foreignKey = "user_id" })
User.hasMany("vehicles", Vehicle, { foreignKey = "owner_id" })
Vehicle.belongsTo("owner", User, { foreignKey = "owner_id" })
User.belongsToMany("roles", Role, {
    pivot = "user_roles", foreignKey = "user_id", otherKey = "role_id",
})

-- hasOne
reset()
mockResults[1] = { { identifier = "license:abc", money = 500, job = "police" } }
mockResults[2] = { { id = 1, user_id = "license:abc", bio = "Hello" } }
local u = User.find({ identifier = "license:abc" })
local profile = u:get("profile")
T.eq(profile.bio, "Hello", "hasOne returns correct data")

-- hasMany
reset()
mockResults[1] = { { identifier = "license:abc", money = 500, job = "police" } }
mockResults[2] = {
    { id = 1, owner_id = "license:abc", plate = "ABC123" },
    { id = 2, owner_id = "license:abc", plate = "XYZ789" },
}
u = User.find({ identifier = "license:abc" })
local vehicles = u:get("vehicles")
T.eq(#vehicles, 2, "hasMany returns multiple instances")

-- belongsTo
reset()
mockResults[1] = { { id = 1, owner_id = "license:abc", plate = "ABC123" } }
mockResults[2] = { { identifier = "license:abc", money = 500, job = "police" } }
local car = Vehicle.find({ plate = "ABC123" })
local owner = car:get("owner")
T.eq(owner.identifier, "license:abc", "belongsTo returns correct owner")

-- belongsToMany
reset()
mockResults[1] = { { identifier = "license:abc", money = 500, job = "police" } }
mockResults[2] = { { id = 1, name = "admin" }, { id = 2, name = "mod" } }
u = User.find({ identifier = "license:abc" })
local roles = u:get("roles")
T.eq(#roles, 2, "belongsToMany returns multiple")
T.match(dbLog[2].sql, "INNER JOIN `user_roles`", "belongsToMany uses JOIN")

-- attach / detach
reset()
mockResults[1] = { { identifier = "license:abc", money = 500, job = "police" } }
u = User.find({ identifier = "license:abc" })
reset()
u:attach("roles", { id = 5, name = "vip" })
T.match(dbLog[1].sql, "INSERT INTO `user_roles`", "attach inserts pivot")
reset()
u:detach("roles", { id = 5, name = "vip" })
T.match(dbLog[1].sql, "DELETE FROM `user_roles`", "detach deletes pivot")

-- ─── Test: Eager Loading ──────────────────────────────────────────

T.section("Eager Loading")

reset()
-- Setup models with relations (reuse existing)
local EUser = ORM.model("eusers", {
    identifier = "string",
    money      = "number",
}, { primaryKey = "identifier" })

local EProfile = ORM.model("eprofiles", {
    id = "number", user_id = "string", bio = "string",
}, { primaryKey = "id" })

EUser.hasOne("profile", EProfile, { foreignKey = "user_id" })

reset()
mockResults[1] = { { identifier = "license:eager", money = 500 } }
mockResults[2] = { { id = 1, user_id = "license:eager", bio = "Hello" } }
local eager = EUser.find({ identifier = "license:eager" }, { include = { "profile" } })
T.eq(eager.profile.bio, "Hello", "eager loading: profile loaded automatically")

-- ─── Test: whereHas ──────────────────────────────────────────────

T.section("whereHas")

reset()
local WHUser = ORM.model("wh_users", {
    id         = "number",
    identifier = "string",
    money      = "number",
}, { primaryKey = "id" })

local WHVehicle = ORM.model("wh_vehicles", {
    id       = "number",
    owner_id = "number",
    plate    = "string",
}, { primaryKey = "id" })

WHUser.hasMany("vehicles", WHVehicle, { foreignKey = "owner_id" })

reset()
mockResults[1] = { { id = 1, identifier = "license:wh1", money = 500 } }
local whBuilder = WHUser.whereHas("vehicles")
local whResults = whBuilder:get()
T.eq(#whResults, 1, "whereHas: returns users with vehicles")
T.match(dbLog[1].sql, "EXISTS", "whereHas: SQL contains EXISTS")
T.match(dbLog[1].sql, "wh_vehicles", "whereHas: SQL references related table")

-- whereHas with callback
reset()
mockResults[1] = { { id = 2, identifier = "license:wh2", money = 300 } }
local whBuilder2 = WHUser.whereHas("vehicles", function(b)
    b:where({ plate = "ABC123" })
end)
local whResults2 = whBuilder2:get()
T.eq(#whResults2, 1, "whereHas with callback: returns filtered results")
T.match(dbLog[1].sql, "plate", "whereHas with callback: SQL contains filter column")

-- ─── Test: countByRelation ──────────────────────────────────────

T.section("countByRelation")

reset()
mockResults[1] = { { id = 1, identifier = "license:cr1", money = 100 } }
mockResults[2] = { { fk = 1, cnt = 3 } }
local crResults = WHUser.countByRelation("vehicles", { id = 1 })
T.eq(#crResults, 1, "countByRelation: returns result entries")
T.eq(crResults[1].count, 3, "countByRelation: count is correct")
T.eq(crResults[1].instance._count_vehicles, 3, "countByRelation: _count_ field set on instance")
T.match(dbLog[2].sql, "GROUP BY", "countByRelation: single GROUP BY query")

-- ─── Test: Nested Writes (createWith) ────────────────────────────

T.section("Nested Writes")

reset()
local NWUser = ORM.model("nw_users", {
    id   = "number",
    name = "string",
}, { primaryKey = "id" })

local NWProfile = ORM.model("nw_profiles", {
    id      = "number",
    user_id = "number",
    bio     = "string",
}, { primaryKey = "id" })

local NWPost = ORM.model("nw_posts", {
    id      = "number",
    user_id = "number",
    title   = "string",
}, { primaryKey = "id" })

NWUser.hasOne("profile", NWProfile, { foreignKey = "user_id" })
NWUser.hasMany("posts", NWPost, { foreignKey = "user_id" })

-- Test hasOne nested write
reset()
mockResults[1] = 1     -- insert user → id=1
local nwUser = NWUser.createWith({
    name = "Alice",
    profile = { bio = "Hello World" },
})
T.eq(nwUser.name, "Alice", "nested write hasOne: parent created")
T.eq(#dbLog, 1, "nested write hasOne: parent INSERT outside the transaction")
T.eq(#txLog, 1, "nested write hasOne: profile written in a transaction")
T.match(txLog[1][1].query, "nw_profiles", "nested write hasOne: profile INSERT references correct table")
T.match(txLog[1][1].query, "user_id", "nested write hasOne: profile INSERT includes FK")

-- Test hasMany nested write
reset()
mockResults[1] = 2     -- insert user → id=2
local nwUser2 = NWUser.createWith({
    name = "Bob",
    posts = {
        { title = "Post 1" },
        { title = "Post 2" },
    },
})
T.eq(nwUser2.name, "Bob", "nested write hasMany: parent created")
T.eq(#dbLog, 1, "nested write hasMany: parent INSERT outside the transaction")
T.eq(#txLog[1], 1, "nested write hasMany: posts use a single multi-row INSERT")
T.match(txLog[1][1].query, "VALUES %(%?, %?%), %(%?, %?%)", "nested write hasMany: one row per post")

-- ─── Test: Inline relations ─────────────────────────────────────

T.section("Inline relations")

reset()
local IRUser = ORM.model("ir_users", {
    identifier = "string",
    money      = "number",
}, {
    primaryKey = "identifier",
    relations = function(M)
        local IRProfile = ORM.model("ir_profiles", {
            id = "number", user_id = "string", bio = "string",
        }, { primaryKey = "id" })
        M.hasOne("profile", IRProfile, { foreignKey = "user_id" })
    end,
})

-- Apply relations
IRUser.applyRelations()

-- Test the relation works
reset()
mockResults[1] = { { identifier = "license:ir1", money = 500 } }
mockResults[2] = { { id = 1, user_id = "license:ir1", bio = "Inline!" } }
local irUser = IRUser.find({ identifier = "license:ir1" })
local irProfile = irUser:get("profile")
T.eq(irProfile.bio, "Inline!", "inline relations: hasOne works after applyRelations")

-- findAll with include (batched eager loading)
T.section("findAll include (batched)")

reset()
local ELUser = ORM.model("el_users", {
    id   = "number",
    name = "string",
}, { primaryKey = "id" })
local ELVehicle = ORM.model("el_vehicles", {
    id       = "number",
    owner_id = "number",
    plate    = "string",
}, { primaryKey = "id" })
ELUser.hasMany("vehicles", ELVehicle, { foreignKey = "owner_id" })

mockResults[1] = { { id = 1, name = "A" }, { id = 2, name = "B" } }
mockResults[2] = {
    { id = 10, owner_id = 1, plate = "AAA" },
    { id = 11, owner_id = 1, plate = "BBB" },
    { id = 12, owner_id = 2, plate = "CCC" },
}
local users = ELUser.findAll({}, { include = { "vehicles" } })
T.eq(#dbLog, 2, "include: exactly 2 queries (no N+1)")
T.match(dbLog[2].sql, "IN %(", "include: uses whereIn batch query")
T.eq(#users[1].vehicles, 2, "include: first user has 2 vehicles")
T.eq(#users[2].vehicles, 1, "include: second user has 1 vehicle")
T.eq(users[1].vehicles[1].plate, "AAA", "include: related rows wrapped")

T.finish()
