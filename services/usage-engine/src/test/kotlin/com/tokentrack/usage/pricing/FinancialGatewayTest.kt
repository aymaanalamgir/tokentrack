package com.tokentrack.usage.pricing

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.sun.net.httpserver.HttpServer
import com.tokentrack.usage.delivery.HttpFinancialGateway
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger

class FinancialGatewayTest {
    private val mapper=jacksonObjectMapper()
    @Test fun `financial requests use the dedicated credential without demo cookies`() {
        val server=HttpServer.create(InetSocketAddress("127.0.0.1",0),0)
        server.createContext("/") { exchange ->
            assertEquals("Bearer financial-test-token-at-least-32-characters",exchange.requestHeaders.getFirst("Authorization"))
            assertNull(exchange.requestHeaders.getFirst("Cookie"))
            assertEquals("0.1065",mapper.readTree(exchange.requestBody)["amount"].asText())
            val body="{\"status\":\"posted\"}".toByteArray();exchange.responseHeaders.add("Content-Type","application/json");exchange.sendResponseHeaders(201,body.size.toLong());exchange.responseBody.use { it.write(body) }
        };server.start()
        try { val result=HttpFinancialGateway(mapper,"http://127.0.0.1:${server.address.port}","financial-test-token-at-least-32-characters").post("{\"amount\":\"0.1065\"}");assertEquals(201,result.status) } finally { server.stop(0) }
    }
    @Test fun `redirects never forward financial credentials to another endpoint`() {
        val server=HttpServer.create(InetSocketAddress("127.0.0.1",0),0);val redirected=AtomicInteger()
        server.createContext("/api/") { exchange -> exchange.responseHeaders.add("Location","/untrusted");exchange.sendResponseHeaders(302,-1);exchange.close() }
        server.createContext("/untrusted") { redirected.incrementAndGet();it.sendResponseHeaders(200,-1);it.close() };server.start()
        try { assertEquals(302,HttpFinancialGateway(mapper,"http://127.0.0.1:${server.address.port}","financial-test-token-at-least-32-characters").post("{}").status);assertEquals(0,redirected.get()) } finally { server.stop(0) }
    }
    @Test fun `missing configuration fails closed and connection failure stays an infrastructure result`() {
        assertEquals(401,HttpFinancialGateway(mapper,"http://127.0.0.1:1","").post("{}").status)
        assertEquals(0,HttpFinancialGateway(mapper,"http://127.0.0.1:1","financial-test-token-at-least-32-characters").post("{}").status)
    }
}
