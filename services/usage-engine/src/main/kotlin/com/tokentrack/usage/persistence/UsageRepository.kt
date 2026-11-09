package com.tokentrack.usage.persistence

import com.tokentrack.usage.domain.*
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Repository
import org.springframework.transaction.PlatformTransactionManager
import org.springframework.transaction.support.TransactionTemplate
import java.sql.ResultSet
import java.sql.Timestamp
import java.util.UUID

@Repository
class UsageRepository(private val jdbc: JdbcTemplate, manager: PlatformTransactionManager) {
    private val transaction = TransactionTemplate(manager).apply { timeout = 30 }
    fun begin(source: String, label: String): UUID {
        val id = UUID.randomUUID()
        jdbc.update("INSERT INTO usage.import_batches(id,source,input_label,status) VALUES (?,?,?,'running')", id, source, label)
        return id
    }
    fun commitRows(id: UUID, rows: List<PreparedRow>, observed: Int) {
        transaction.executeWithoutResult {
            val status = jdbc.queryForObject("SELECT status FROM usage.import_batches WHERE id=? FOR UPDATE", String::class.java, id)
            if (status != "running") throw ImportFailure("IMPORT_LEASE_LOST", true)
            var accepted = 0; var duplicates = 0; var rejected = 0
            rows.forEach { row ->
                val event = row.event
                if (row.error != null) {
                    rejection(id, row.row, row.eventId, row.error); rejected++
                } else {
                    requireNotNull(event)
                    val fingerprint = event.fingerprint()
                    val inserted = jdbc.update("""
                        INSERT INTO usage.usage_events(id,organization_id,source,event_id,user_id,project_id,provider,model,tool,
                          input_tokens,output_tokens,cached_input_tokens,occurred_at,agent_run_id,workflow_type,import_batch_id,schema_version,payload_fingerprint)
                        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?) ON CONFLICT (organization_id,source,event_id) DO NOTHING
                    """.trimIndent(), UUID.randomUUID(), event.organizationId, event.source, event.eventId, event.userId, event.projectId,
                        event.provider, event.model, event.tool, event.inputTokens, event.outputTokens, event.cachedInputTokens,
                        Timestamp.from(event.occurredAt), event.agentRunId, event.workflowType, id, fingerprint)
                    if (inserted == 1) accepted++ else {
                        val existing = jdbc.queryForObject("SELECT payload_fingerprint FROM usage.usage_events WHERE organization_id=? AND source=? AND event_id=?", String::class.java, event.organizationId, event.source, event.eventId)
                        if (existing == fingerprint) duplicates++ else {
                            rejection(id, row.row, row.eventId, ValidationError("EVENT_ID_CONFLICT", "event_id", "Event identity already exists with a different canonical payload")); rejected++
                        }
                    }
                }
            }
            jdbc.update("""UPDATE usage.import_batches SET total_rows=?, accepted_rows=accepted_rows+?, duplicate_rows=duplicate_rows+?,
                rejected_rows=rejected_rows+?,heartbeat_at=CURRENT_TIMESTAMP WHERE id=?""", observed, accepted, duplicates, rejected, id)
        }
    }
    private fun rejection(id: UUID, row: Int, eventId: String?, error: ValidationError) {
        jdbc.update("INSERT INTO usage.import_rejections(id,import_batch_id,row_number,event_id,code,field,message) VALUES (?,?,?,?,?,?,?)",
            UUID.randomUUID(), id, row, eventId, error.code, error.field, error.message)
    }
    fun fileError(id: UUID, row: Int, code: String) {
        val message = when (code) {
            "EMPTY_FILE" -> "CSV is empty; include the v1 header and at least one data row"
            "EMPTY_DATASET" -> "CSV contains a header but no data rows"
            "INVALID_HEADERS" -> "Headers must be unique and include every required v1 column"
            "UNSUPPORTED_COLUMNS" -> "CSV contains an unsupported column; only documented v1 columns are accepted"
            "INVALID_UTF8" -> "CSV must be valid UTF-8 text"
            "INVALID_CSV" -> "Malformed CSV quoting; remaining record boundaries cannot be trusted"
            "FILE_TOO_LARGE" -> "CSV exceeds the 20 MiB file limit"
            "ROW_LIMIT_EXCEEDED" -> "CSV exceeds the 100000 data-record limit"
            "FILE_UNREADABLE" -> "CSV must be a readable regular file"
            else -> "CSV did not satisfy the v1 file contract"
        }
        val field = if (code in setOf("INVALID_HEADERS", "UNSUPPORTED_COLUMNS")) "header" else "file"
        rejection(id, row, null, ValidationError(code, field, message))
    }
    fun finish(id: UUID, observed: Int, scanComplete: Boolean, failure: ImportFailure? = null): BatchSummary {
        jdbc.update("""UPDATE usage.import_batches SET total_rows=?,scan_complete=?,failure_code=?,infrastructure_failures=?,completed_at=CURRENT_TIMESTAMP,
            heartbeat_at=CURRENT_TIMESTAMP,status=CASE WHEN CAST(? AS varchar) IS NOT NULL THEN CASE WHEN accepted_rows+duplicate_rows+rejected_rows>0 THEN 'partial' ELSE 'failed' END
            WHEN rejected_rows>0 THEN 'completed_with_rejections' ELSE 'completed' END WHERE id=? AND status='running'""",
            observed, scanComplete, failure?.code, if (failure?.retryable == true) 1 else 0, failure?.code, id)
        return summary(id)
    }
    fun recoverStale() {
        jdbc.update("""UPDATE usage.import_batches SET status=CASE WHEN accepted_rows+duplicate_rows+rejected_rows>0 THEN 'partial' ELSE 'failed' END,
            completed_at=CURRENT_TIMESTAMP,failure_code='IMPORT_INTERRUPTED',infrastructure_failures=infrastructure_failures+1
            WHERE status='running' AND heartbeat_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes'""")
    }
    fun summary(id: UUID): BatchSummary = jdbc.queryForObject("SELECT * FROM usage.import_batches WHERE id=?", { row, _ -> mapSummary(row) }, id)!!
    fun recent(): List<BatchSummary> = jdbc.query("SELECT * FROM usage.import_batches ORDER BY started_at DESC LIMIT 20", { row, _ -> mapSummary(row) })
    fun rejections(id: UUID, offset: Int = 0, limit: Int = 100): List<Map<String, Any?>> = jdbc.queryForList(
        "SELECT row_number,event_id,code,field,message FROM usage.import_rejections WHERE import_batch_id=? ORDER BY row_number,id LIMIT ? OFFSET ?", id, limit.coerceIn(1,100), offset.coerceAtLeast(0))
    fun errors(id: UUID): List<Map<String, Any?>> = jdbc.queryForList("SELECT code,COUNT(*) AS count FROM usage.import_rejections WHERE import_batch_id=? GROUP BY code ORDER BY code", id)
    private fun mapSummary(row: ResultSet) = BatchSummary(
        row.getObject("id", UUID::class.java), row.getString("source"), row.getString("input_label"), row.getString("status"),
        row.getTimestamp("started_at").toInstant(), row.getTimestamp("completed_at")?.toInstant(), row.getInt("total_rows"), row.getInt("accepted_rows"),
        row.getInt("duplicate_rows"), row.getInt("rejected_rows"), row.getInt("infrastructure_failures"), row.getBoolean("scan_complete"), row.getString("failure_code"))
}
