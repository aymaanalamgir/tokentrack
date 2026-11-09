package com.tokentrack.usage.ingestion

import com.tokentrack.usage.domain.*
import org.apache.commons.csv.CSVFormat
import java.io.Reader

class UsageCsvReader(reader: Reader) : AutoCloseable {
    companion object {
        val REQUIRED = listOf("schema_version", "event_id", "organization_id", "user_id", "project_id", "provider", "model", "tool", "input_tokens", "output_tokens", "occurred_at")
        val OPTIONAL = listOf("cached_input_tokens", "agent_run_id", "workflow_type")
        val HEADERS = REQUIRED + OPTIONAL
        const val MAX_BYTES = 20 * 1024 * 1024
        const val MAX_ROWS = 100_000
    }
    private val parser = CSVFormat.RFC4180.builder().setIgnoreEmptyLines(false).setLenientEof(false).setTrailingData(false).get().parse(reader)
    private val iterator = parser.iterator()
    private val headers: List<String>
    init {
        try {
            if (!iterator.hasNext()) throw ImportFailure("EMPTY_FILE")
            headers = iterator.next().toList().mapIndexed { index, s -> if (index == 0) s.removePrefix("\uFEFF") else s }
            if (headers.size != headers.toSet().size || !headers.containsAll(REQUIRED)) throw ImportFailure("INVALID_HEADERS")
            if (headers.any { it !in HEADERS }) throw ImportFailure("UNSUPPORTED_COLUMNS")
        } catch (error: Exception) {
            parser.close()
            if (error is ImportFailure) throw error
            throw ImportFailure("INVALID_CSV")
        }
    }
    fun next(): Pair<RawUsageRecord?, PreparedRow?>? {
        val record = try { if (iterator.hasNext()) iterator.next() else return null } catch (_: Exception) { throw ImportFailure("INVALID_CSV") }
        val row = record.recordNumber.toInt()
        if (row > MAX_ROWS + 1) throw ImportFailure("ROW_LIMIT_EXCEEDED")
        if (record.size() != headers.size) return null to PreparedRow(row, null, error = ValidationError("COLUMN_COUNT", "row", "CSV row does not match the header column count"))
        return RawUsageRecord(row, headers.zip(record.toList()).toMap()) to null
    }
    override fun close() = parser.close()
}
