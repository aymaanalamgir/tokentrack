package com.tokentrack.usage.references

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.tokentrack.usage.domain.*
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

fun interface ReferenceResolver {
    fun validate(references: List<UsageReference>): Map<String, ValidationError?>
}
@Component
class RailsReferenceResolver(
    private val mapper: ObjectMapper,
    @param:Value("\${tokentrack.references.url}") private val baseUrl: String,
    @param:Value("\${tokentrack.references.token}") private val token: String,
) : ReferenceResolver {
    private val client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).followRedirects(HttpClient.Redirect.NEVER).build()
    private fun request(path: String, payload: Any? = null): JsonNode {
        if (token.length < 32) throw ImportFailure("REFERENCE_SERVICE_AUTHORIZATION", true)
        try {
            val uri = URI.create(baseUrl.trimEnd('/') + path)
            if (uri.scheme !in listOf("http", "https") || uri.userInfo != null) throw ImportFailure("REFERENCE_SERVICE_CONFIGURATION", true)
            val request = HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(5)).header("Authorization", "Bearer $token").header("Accept", "application/json")
            if (payload == null) request.GET() else request.header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(mapper.writeValueAsString(payload)))
            val response = client.send(request.build(), HttpResponse.BodyHandlers.ofByteArray())
            val bytes = response.body()
            if (response.statusCode() in listOf(401, 403)) throw ImportFailure("REFERENCE_SERVICE_AUTHORIZATION", true)
            if (response.statusCode() >= 500) throw ImportFailure("REFERENCE_SERVICE_UNAVAILABLE", true)
            if (response.statusCode() != 200 || bytes.size > 2 * 1024 * 1024 || !response.headers().firstValue("content-type").orElse("").contains("application/json")) throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
            return try { mapper.readTree(bytes) } catch (_: com.fasterxml.jackson.core.JsonProcessingException) { throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true) }
        } catch (error: ImportFailure) { throw error }
        catch (_: Exception) { throw ImportFailure("REFERENCE_SERVICE_UNAVAILABLE", true) }
    }
    override fun validate(references: List<UsageReference>): Map<String, ValidationError?> {
        val results = mutableMapOf<String, ValidationError?>()
        references.distinct().chunked(100).forEach { chunk ->
            val body = request("/api/v1/internal/usage-references/validate", mapOf("references" to chunk.map {
                mapOf("key" to it.key(), "organization_id" to it.organizationId, "user_id" to it.userId, "project_id" to it.projectId, "occurred_at" to it.occurredAt.toString())
            }))
            val data = body["data"]
            if (body["policy_version"]?.asText() != "membership-period-v1" || data == null || !data.isArray || data.size() != chunk.size) throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
            val expected = chunk.map { it.key() }.toSet()
            data.forEach { row ->
                val key = row["key"]?.asText() ?: throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
                if (key !in expected || results.containsKey(key) || !row.path("valid").isBoolean) throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
                results[key] = if (row["valid"].asBoolean()) null else {
                    val code = row.path("code").asText()
                    val field = row.path("field").asText()
                    // Never persist arbitrary remote text in operational diagnostics.
                    val messages = mapOf("UNKNOWN_ORGANIZATION" to "Organization is not known", "INVALID_USER_REFERENCE" to "User does not belong to this organization", "USER_INELIGIBLE" to "User is not currently eligible for attribution", "INVALID_PROJECT_REFERENCE" to "Project does not belong to this organization", "PROJECT_MEMBERSHIP_NOT_ESTABLISHED" to "No recorded project membership covers the event time")
                    if (code !in messages || field !in listOf("organization_id", "user_id", "project_id")) throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
                    ValidationError(code, field, messages.getValue(code))
                }
            }
        }
        return results
    }
    fun demoSnapshot(): JsonNode = request("/api/v1/internal/usage-references/demo-snapshot").path("data").also {
        if (it.path("snapshot_version").asInt() != 1 || it.path("policy_version").asText() != "membership-period-v1") throw ImportFailure("REFERENCE_PROTOCOL_ERROR", true)
    }
}
