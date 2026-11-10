-- core/schema.lua
-- Pre-computes which fields need JSON decode and which columns a write may set.

local Helpers   = OrvexHelpers or require("utils.helpers")
local Validator = OrvexValidator or require("utils.validator")

local SUPPORTED_TYPES = table.concat(Validator.SUPPORTED_TYPES, ", ")

---@alias OrvexFieldType "string"|"number"|"boolean"|"json"|"auto"|"date"|"datetime"|"timestamp"

---@class OrvexSchema
---@field fields table<string, OrvexFieldType> declared fields, as given
---@field allFields table<string, OrvexFieldType> declared fields plus the ORM-managed columns
---@field decodeFields table[]
---@field encodeSet table<string, boolean>
---@field managedColumns table<string, string> column -> option ("timestamps"/"softDelete") of the columns the ORM writes
---@field allowManagedColumns boolean callers may set the timestamp columns themselves
local Schema = {}
Schema.__index = Schema

---@class OrvexSchemaOpts
---@field timestamps? boolean
---@field softDelete? boolean
---@field allowManagedColumns? boolean

--- Columns the ORM writes itself when an option is on. Validation accepts
--- them even when undeclared (hooks may set them); caller data may not
--- (see core/model/write.lua).
---@type { option: string, column: string }[]
local MANAGED_COLUMNS = {
    { option = "timestamps", column = "created_at" },
    { option = "timestamps", column = "updated_at" },
    { option = "softDelete", column = "deleted_at" },
}

--- `fields` plus the managed columns it does not declare, typed datetime.
--- Returns `fields` itself when nothing is added; never modifies it.
---@param fields table<string, OrvexFieldType>
---@param opts? OrvexSchemaOpts
---@return table<string, OrvexFieldType>
local function withManagedColumns(fields, opts)
    local all = fields
    for _, managed in ipairs(MANAGED_COLUMNS) do
        if opts and opts[managed.option] and fields[managed.column] == nil then
            if all == fields then all = Helpers.shallowCopy(fields) end
            all[managed.column] = "datetime"
        end
    end
    return all
end

--- The managed columns whose option is on, with that option.
---@param opts? OrvexSchemaOpts
---@return table<string, string>
local function managedColumnsOf(opts)
    local managed = {}
    for _, entry in ipairs(MANAGED_COLUMNS) do
        if opts and opts[entry.option] then managed[entry.column] = entry.option end
    end
    return managed
end

---@param fields table<string, OrvexFieldType>
---@param opts? OrvexSchemaOpts
---@return OrvexSchema
function Schema.new(fields, opts)
    assert(type(fields) == "table", "Schema fields must be a table")

    local self = setmetatable({}, Schema)
    self.fields = fields
    self.allFields = withManagedColumns(fields, opts)
    self.managedColumns = managedColumnsOf(opts)
    self.allowManagedColumns = (opts and opts.allowManagedColumns) == true
    self.decodeFields = {}
    self.encodeSet = {}

    for name, fieldType in pairs(fields) do
        Helpers.ensure(Validator.isKnownType(fieldType),
            ("Field '%s': unknown type '%s' (supported: %s)"):format(tostring(name), tostring(fieldType), SUPPORTED_TYPES))
        if fieldType == "json" or fieldType == "auto" then
            self.decodeFields[#self.decodeFields + 1] = { name = name, type = fieldType }
            self.encodeSet[name] = true
        end
    end

    return self
end

OrvexSchema = Schema
return Schema
