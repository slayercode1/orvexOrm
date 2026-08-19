-- core/schema.lua
-- Pre-computes which fields need JSON decode.

---@alias OrvexFieldType "string"|"number"|"boolean"|"json"|"auto"|"date"|"datetime"|"timestamp"

---@class OrvexSchema
---@field fields table<string, OrvexFieldType>
---@field fieldNames string[]
---@field decodeFields table[]
---@field encodeSet table<string, boolean>
local Schema = {}
Schema.__index = Schema

---@param fields table<string, OrvexFieldType>
---@return OrvexSchema
function Schema.new(fields)
    assert(type(fields) == "table", "Schema fields must be a table")

    local self = setmetatable({}, Schema)
    self.fields = fields
    self.fieldNames = {}
    self.decodeFields = {}
    self.encodeSet = {}

    for name, fieldType in pairs(fields) do
        self.fieldNames[#self.fieldNames + 1] = name
        if fieldType == "json" or fieldType == "auto" then
            self.decodeFields[#self.decodeFields + 1] = { name = name, type = fieldType }
            self.encodeSet[name] = true
        end
    end
    table.sort(self.fieldNames)

    return self
end

---@param name string
---@return OrvexFieldType|nil
function Schema:typeOf(name)
    return self.fields[name]
end

---@param name string
---@return boolean
function Schema:hasField(name)
    return self.fields[name] ~= nil
end

OrvexSchema = Schema
return Schema
