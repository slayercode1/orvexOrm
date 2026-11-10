-- Central error catalogue and safe API error contracts.
local Errors = {}

local definitions = {
    VALIDATION_ERROR = { status = 422, level = "warn", retryable = false, message = "Some information is invalid. Check the highlighted fields." },
    AUTHENTICATION_REQUIRED = { status = 401, level = "warn", retryable = false, message = "Your session has expired. Please sign in again." },
    FORBIDDEN = { status = 403, level = "warn", retryable = false, message = "You do not have permission to perform this action." },
    NOT_FOUND = { status = 404, level = "info", retryable = false, message = "The requested item could not be found or is no longer available." },
    CONFLICT = { status = 409, level = "warn", retryable = false, message = "This change conflicts with the current data. Refresh and try again." },
    RATE_LIMITED = { status = 429, level = "warn", retryable = true, message = "Too many requests. Wait a moment before trying again." },
    EXTERNAL_SERVICE_ERROR = { status = 502, level = "error", retryable = true, message = "A required service could not complete the request. Please try again." },
    SERVICE_UNAVAILABLE = { status = 503, level = "error", retryable = true, message = "The service is temporarily unavailable. Please try again shortly." },
    TIMEOUT = { status = 504, level = "error", retryable = true, message = "The request took too long. Please try again." },
    NETWORK_ERROR = { status = 503, level = "error", retryable = true, message = "The server could not be reached. Check your connection and try again." },
    INTERNAL_ERROR = { status = 500, level = "error", retryable = true, message = "An unexpected error occurred. Please try again." },
}

local sequence = 0

function Errors.generateId(prefix)
    sequence = (sequence + 1) % 0xFFFF
    local random = math.random(0, 0xFFFFFF)
    return ("%s-%s-%04X%06X"):format(prefix or "ERR", os.date("!%Y%m%d%H%M%S"), sequence, random)
end

function Errors.new(code, technicalMessage, details)
    local definition = definitions[code] or definitions.INTERNAL_ERROR
    return {
        isAppError = true,
        code = definitions[code] and code or "INTERNAL_ERROR",
        status = definition.status,
        level = definition.level,
        retryable = definition.retryable,
        userMessage = definition.message,
        technicalMessage = technicalMessage,
        details = details,
    }
end

function Errors.normalize(value)
    if type(value) == "table" and value.isAppError then return value end
    return Errors.new("INTERNAL_ERROR", tostring(value))
end

function Errors.toResponse(appError, errorId)
    local response = { success = false, error = {
        code = appError.code,
        message = appError.userMessage,
        retryable = appError.retryable,
    } }
    if errorId then response.error.errorId = errorId end
    return response
end

OrvexErrors = Errors
return Errors
