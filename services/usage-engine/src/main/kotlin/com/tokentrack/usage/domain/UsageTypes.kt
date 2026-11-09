package com.tokentrack.usage.domain

import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

data class ValidationError(val code: String, val field: String, val message: String)
data class RawUsageRecord(val row: Int, val values: Map<String, String>)
data class UsageEvent(
    val organizationId: UUID, val source: String, val eventId: String,
    val userId: UUID, val projectId: UUID?, val provider: String, val model: String, val tool: String,
    val inputTokens: Long, val outputTokens: Long, val cachedInputTokens: Long,
    val occurredAt: Instant, val agentRunId: String?, val workflowType: String?,
) {
    fun fingerprint(): String {
        val fields = listOf("1", organizationId.toString(), source, eventId, userId.toString(), projectId?.toString(),
            provider, model, tool, inputTokens.toString(), outputTokens.toString(), cachedInputTokens.toString(),
            occurredAt.toString(), agentRunId, workflowType)
        val canonical = fields.joinToString("") { value -> value?.let { "${it.toByteArray(Charsets.UTF_8).size}:$it" } ?: "-1:" }
        return sha256(canonical)
    }
    fun reference() = UsageReference(organizationId, userId, projectId, occurredAt)
}
fun sha256(value: String): String = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
data class UsageReference(val organizationId: UUID, val userId: UUID, val projectId: UUID?, val occurredAt: Instant) {
    fun key() = sha256("$organizationId/$userId/$projectId/$occurredAt")
}
data class PreparedRow(val row: Int, val eventId: String?, val event: UsageEvent? = null, val error: ValidationError? = null)
data class BatchSummary(
    val id: UUID, val source: String, val inputLabel: String, val status: String,
    val startedAt: Instant, val completedAt: Instant?, val totalRows: Int, val acceptedRows: Int,
    val duplicateRows: Int, val rejectedRows: Int, val infrastructureFailures: Int,
    val scanComplete: Boolean, val failureCode: String?,
) {
    val unprocessedRows: Int get() = totalRows - acceptedRows - duplicateRows - rejectedRows
    val durationMillis: Long? get() = completedAt?.let { java.time.Duration.between(startedAt, it).toMillis() }
}
class ImportFailure(val code: String, val retryable: Boolean = false, val batchId: UUID? = null) : RuntimeException(code)
