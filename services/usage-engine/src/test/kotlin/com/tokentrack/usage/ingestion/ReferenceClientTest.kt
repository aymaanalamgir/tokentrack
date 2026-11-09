package com.tokentrack.usage.ingestion

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.sun.net.httpserver.HttpServer
import com.tokentrack.usage.domain.*
import com.tokentrack.usage.references.RailsReferenceResolver
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.net.InetSocketAddress
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

class ReferenceClientTest {
    private val mapper = jacksonObjectMapper()
    private fun refs(size: Int) = (1..size).map { UsageReference(UUID.randomUUID(), UUID.randomUUID(), null, Instant.parse("2026-11-09T12:00:00Z")) }
    @Test fun `references are batched and authenticated without returning private data`() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val calls = AtomicInteger()
        server.createContext("/api/v1/internal/usage-references/validate") { exchange ->
            assertEquals("Bearer test-service-credential-at-least-32-characters", exchange.requestHeaders.getFirst("Authorization"))
            val payload = mapper.readTree(exchange.requestBody)["references"]
            assertTrue(payload.size() <= 100); calls.incrementAndGet()
            val body = mapper.writeValueAsBytes(mapOf("policy_version" to "membership-period-v1", "data" to payload.map { mapOf("key" to it["key"].asText(), "valid" to true) }))
            exchange.responseHeaders.add("Content-Type", "application/json"); exchange.sendResponseHeaders(200, body.size.toLong()); exchange.responseBody.use { it.write(body) }
        }
        server.start()
        try {
            val resolver = RailsReferenceResolver(mapper, "http://127.0.0.1:${server.address.port}", "test-service-credential-at-least-32-characters")
            assertEquals(205, resolver.validate(refs(205)).size); assertEquals(3, calls.get())
        } finally { server.stop(0) }
    }
    @Test fun `outage is retryable rather than an unknown employee rejection`() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { it.sendResponseHeaders(503, -1); it.close() }; server.start()
        try {
            val resolver = RailsReferenceResolver(mapper, "http://127.0.0.1:${server.address.port}", "test-service-credential-at-least-32-characters")
            val error = assertThrows(ImportFailure::class.java) { resolver.validate(refs(1)) }
            assertEquals("REFERENCE_SERVICE_UNAVAILABLE", error.code); assertTrue(error.retryable)
        } finally { server.stop(0) }
    }
    @Test fun `missing results and unknown policy fail closed`() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val body = "{\"policy_version\":\"future\",\"data\":[]}".toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json"); exchange.sendResponseHeaders(200, body.size.toLong()); exchange.responseBody.use { it.write(body) }
        }; server.start()
        try {
            val resolver = RailsReferenceResolver(mapper, "http://127.0.0.1:${server.address.port}", "test-service-credential-at-least-32-characters")
            assertEquals("REFERENCE_PROTOCOL_ERROR", assertThrows(ImportFailure::class.java) { resolver.validate(refs(1)) }.code)
        } finally { server.stop(0) }
    }
}
