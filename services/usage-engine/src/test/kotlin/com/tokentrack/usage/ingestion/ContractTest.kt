package com.tokentrack.usage.ingestion

import com.tokentrack.usage.domain.*
import com.tokentrack.usage.validation.EventValidator
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import org.junit.jupiter.api.DynamicTest.dynamicTest
import java.io.StringReader

class ContractTest {
    private val validator = EventValidator()
    fun valid() = linkedMapOf("schema_version" to "1", "event_id" to "evt-1", "organization_id" to "11111111-1111-1111-1111-111111111111",
        "user_id" to "22222222-2222-2222-2222-222222222222", "project_id" to "", "provider" to "OpenAI", "model" to "Provider/Model-ABC:2026-11",
        "tool" to "Coding-Assistant", "input_tokens" to "12000000", "output_tokens" to "4200", "occurred_at" to "2026-11-09T14:30:00+02:00")
    private fun parse(text: String) = UsageCsvReader(StringReader(text))
    private fun line(values: Map<String,String>) = UsageCsvReader.REQUIRED.joinToString(",") { values[it].orEmpty() }

    @Test fun `quoted fields and BOM parse without discarding fields`() {
        parse("\uFEFF${UsageCsvReader.REQUIRED.joinToString(",")}\r\n${line(valid()).replace("OpenAI", "\"OpenAI\"")}\r\n").use {
            val record = it.next()!!.first!!
            assertEquals(2, record.row)
            assertEquals("OpenAI", record.values["provider"])
            assertNull(it.next())
        }
        parse("${UsageCsvReader.REQUIRED.joinToString(",")}\n${line(valid()).replace("OpenAI", "\"open,ai\"")}\n").use {
            assertEquals("open,ai", it.next()!!.first!!.values["provider"])
        }
    }
    @Test fun `column mismatches are recoverable and later rows remain available`() {
        parse("${UsageCsvReader.REQUIRED.joinToString(",")}\nwrong,columns\n${line(valid())}\n").use {
            assertEquals("COLUMN_COUNT", it.next()!!.second!!.error!!.code)
            assertEquals(3, it.next()!!.first!!.row)
        }
    }
    @TestFactory fun `fatal CSV structures are explicit`() = listOf(
        "" to "EMPTY_FILE", "event_id,user_id\n" to "INVALID_HEADERS",
        "${UsageCsvReader.REQUIRED.joinToString(",")},event_id\n" to "INVALID_HEADERS",
        "${UsageCsvReader.REQUIRED.joinToString(",")},prompt\n" to "UNSUPPORTED_COLUMNS",
    ).map { (csv, code) -> dynamicTest(code) { assertEquals(code, assertThrows(ImportFailure::class.java) { parse(csv) }.code) } }
    @Test fun `malformed quoting is never treated as a valid end of file`() {
        parse("${UsageCsvReader.REQUIRED.joinToString(",")}\n\"unterminated").use {
            assertEquals("INVALID_CSV", assertThrows(ImportFailure::class.java) { it.next() }.code)
        }
    }
    @Test fun `valid high token usage canonicalizes dimensions and UTC while retaining model identity`() {
        val event = validator.validate(RawUsageRecord(2, valid()), "unit-source").event!!
        assertEquals(12_000_000L, event.inputTokens)
        assertEquals("openai", event.provider)
        assertEquals("coding-assistant", event.tool)
        assertEquals("Provider/Model-ABC:2026-11", event.model)
        assertEquals("2026-11-09T12:30:00Z", event.occurredAt.toString())
        assertNull(event.projectId)
        val equivalent = valid() + mapOf("occurred_at" to "2026-11-09T12:30:00.000000999Z", "provider" to " openai ")
        assertEquals(event.fingerprint(), validator.validate(RawUsageRecord(3, equivalent), "unit-source").event!!.fingerprint())
    }
    @TestFactory fun `invalid values produce stable field errors`() = listOf(
        Triple("schema_version", "2", "UNSUPPORTED_SCHEMA_VERSION"), Triple("event_id", "", "REQUIRED_VALUE"),
        Triple("event_id", "contains space", "INVALID_IDENTIFIER"), Triple("organization_id", "abc", "INVALID_UUID"),
        Triple("user_id", "1-1-1-1-1", "INVALID_UUID"), Triple("project_id", "missing", "INVALID_UUID"),
        Triple("input_tokens", "-1", "INVALID_TOKEN_COUNT"), Triple("input_tokens", "1.5", "INVALID_TOKEN_COUNT"),
        Triple("output_tokens", "1e3", "INVALID_TOKEN_COUNT"), Triple("input_tokens", "1000000000001", "INVALID_TOKEN_COUNT"),
        Triple("input_tokens", "999999999999999999999999999", "INVALID_TOKEN_COUNT"), Triple("cached_input_tokens", "12000001", "INVALID_CACHED_TOKENS"),
        Triple("provider", "unknown provider", "INVALID_IDENTIFIER"), Triple("model", "model,quoted", "INVALID_IDENTIFIER"),
        Triple("tool", "a".repeat(129), "INVALID_IDENTIFIER"), Triple("model", "m".repeat(513), "FIELD_TOO_LONG"),
        Triple("occurred_at", "2026-11-09T12:30:00", "INVALID_TIMESTAMP"), Triple("occurred_at", "tomorrow", "INVALID_TIMESTAMP"),
        Triple("occurred_at", "2100-01-01T00:00:00Z", "INVALID_TIMESTAMP"), Triple("agent_run_id", "private content", "INVALID_IDENTIFIER")
    ).map { (field, value, code) -> dynamicTest("$field $code $value") {
        val result = validator.validate(RawUsageRecord(18, valid() + (field to value)), "unit-source")
        assertNull(result.event); assertEquals(code, result.error!!.code); assertEquals(field, result.error.field)
    } }
    @Test fun `zero tokens and cached tokens are cross-field constraints`() {
        val result = validator.validate(RawUsageRecord(2, valid() + mapOf("input_tokens" to "0", "output_tokens" to "0")), "unit-source")
        assertEquals("ZERO_TOKEN_EVENT", result.error!!.code)
    }
}
