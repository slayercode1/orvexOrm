-- core/schema.lua
-- Stores and exposes the field definitions for a model.
-- Performance-optimized: pre-computes which fields need JSON decode.
-- No dependencies.

---@alias OrvexFieldType "string"|"number"|"boolean"|"json"|"auto"|"date"|"datetime"|"timestamp"

---@class OrvexSchema
---@field fields table<string, OrvexFieldType>
---@field fieldNames string[]
---@field decodeFields table[]  Pre-computed list of { name, type } for fields needing decode
local Schema = {}
Schema.__index = Schema

--- Create a schema from a field-definition table.
---@param fields table<string, OrvexFieldType>
---@return OrvexSchema
function Schema.new(fields)
    assert(type(fields) == "table", "Schema fields must be a table")

    local self = setmetatable({}, Schema)
    self.fields = fields
    self.fieldNames = {}
    self.decodeFields = {}

    for name, fieldType in pairs(fields) do
        self.fieldNames[#self.fieldNames + 1] = name
        -- Only json and auto types need decode processing
        if fieldType == "json" or fieldType == "auto" then
            self.decodeFields[#self.decodeFields + 1] = { name = name, type = fieldType }
        end
    end
    table.sort(self.fieldNames)

    return self
end

--- Return the declared type of a field, or nil if unknown.
---@param name string
---@return OrvexFieldType|nil
function Schema:typeOf(name)
    return self.fields[name]
end

--- Check whether a field exists in the schema.
---@param name string
---@return boolean
function Schema:hasField(name)
    return self.fields[name] ~= nil
end

OrvexSchema = Schema
return Schema
