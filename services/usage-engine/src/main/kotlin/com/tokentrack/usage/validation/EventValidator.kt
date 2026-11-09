package com.tokentrack.usage.validation

import com.tokentrack.usage.domain.*
import org.springframework.stereotype.Component
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

@Component
class EventValidator {
    companion object {
        const val MAX_TOKENS = 1_000_000_000_000L
        val ID = Regex("[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")
        val SOURCE = Regex("[a-z0-9][a-z0-9._-]{0,63}")
        private val UUID_FORMAT = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
    }
    private class Invalid(val error: ValidationError) : RuntimeException()
    fun validate(raw: RawUsageRecord, source: String): PreparedRow {
        fun bad(code: String, field: String, message: String): Nothing = throw Invalid(ValidationError(code, field, message))
        fun text(field: String, required: Boolean = true): String {
            val value = raw.values[field]?.trim().orEmpty()
            if (value.length > 512) bad("FIELD_TOO_LONG", field, "Field exceeds 512 characters")
            if (required && value.isEmpty()) bad("REQUIRED_VALUE", field, "$field is required")
            return value
        }
        fun uuid(field: String): UUID {
            val value = text(field)
            if (!UUID_FORMAT.matches(value)) bad("INVALID_UUID", field, "$field must be a UUID")
            return UUID.fromString(value)
        }
        fun tokens(field: String, optional: Boolean = false): Long {
            val value = text(field, !optional).ifEmpty { "0" }
            val number = if (value.matches(Regex("[0-9]+"))) value.toLongOrNull() else null
            if (number == null || number > MAX_TOKENS) bad("INVALID_TOKEN_COUNT", field, "$field must be an integer between 0 and $MAX_TOKENS")
            return number
        }
        fun identifier(field: String, regex: Regex, lower: Boolean = false, optional: Boolean = false): String? {
            val value = text(field, !optional).let { if (lower) it.lowercase(Locale.ROOT) else it }
            if (value.isEmpty() && optional) return null
            if (!regex.matches(value)) bad("INVALID_IDENTIFIER", field, "$field has unsupported characters or length")
            return value
        }
        return try {
            if (text("schema_version") != "1") bad("UNSUPPORTED_SCHEMA_VERSION", "schema_version", "Only schema version 1 is supported")
            val eventId = identifier("event_id", ID)!!
            val org = uuid("organization_id")
            val user = uuid("user_id")
            val project = text("project_id", false).takeIf { it.isNotEmpty() }?.let { uuid("project_id") }
            val provider = identifier("provider", SOURCE, lower = true)!!
            val model = identifier("model", Regex("[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,199}"))!!
            val tool = identifier("tool", Regex("[a-z0-9][a-z0-9._-]{0,127}"), lower = true)!!
            val input = tokens("input_tokens")
            val output = tokens("output_tokens")
            if (input == 0L && output == 0L) bad("ZERO_TOKEN_EVENT", "input_tokens", "At least one input or output token must be positive")
            val cached = tokens("cached_input_tokens", true)
            if (cached > input) bad("INVALID_CACHED_TOKENS", "cached_input_tokens", "Cached input tokens cannot exceed input tokens")
            val time = try { OffsetDateTime.parse(text("occurred_at")) } catch (_: java.time.format.DateTimeParseException) {
                bad("INVALID_TIMESTAMP", "occurred_at", "occurred_at requires an ISO 8601 timestamp with an explicit offset")
            }
            val instant = time.toInstant().truncatedTo(ChronoUnit.MICROS)
            if (instant < java.time.Instant.parse("2000-01-01T00:00:00Z") || instant >= java.time.Instant.parse("2100-01-01T00:00:00Z")) bad("INVALID_TIMESTAMP", "occurred_at", "occurred_at must be within UTC years 2000–2099")
            val event = UsageEvent(org, source, eventId, user, project, provider, model, tool, input, output, cached, instant,
                identifier("agent_run_id", ID, optional = true), identifier("workflow_type", SOURCE, lower = true, optional = true))
            PreparedRow(raw.row, eventId, event)
        } catch (invalid: Invalid) {
            PreparedRow(raw.row, raw.values["event_id"]?.trim()?.takeIf { ID.matches(it) }, error = invalid.error)
        }
    }
}
