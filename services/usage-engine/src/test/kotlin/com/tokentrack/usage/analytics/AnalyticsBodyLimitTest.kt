package com.tokentrack.usage.analytics

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.springframework.mock.web.MockHttpServletRequest
import org.springframework.mock.web.MockHttpServletResponse
import jakarta.servlet.FilterChain

class AnalyticsBodyLimitTest {
    @Test fun `rejects oversized and chunked analytics bodies before JSON parsing`() {
        val request=MockHttpServletRequest("POST","/internal/v1/analytics");request.setContent(ByteArray(65537))
        val response=MockHttpServletResponse();var called=false
        AnalyticsBodyLimit().doFilter(request,response,FilterChain { _,_->called=true })
        assertEquals(413,response.status);assertFalse(called)
    }
    @Test fun `retains bounded JSON body exactly and does not intercept other endpoints`() {
        val request=MockHttpServletRequest("POST","/internal/v1/analytics");request.setContent("{\"hello\":1}".toByteArray())
        val response=MockHttpServletResponse();var body=""
        AnalyticsBodyLimit().doFilter(request,response,FilterChain { r,_->body=String(r.inputStream.readAllBytes()) })
        assertEquals("{\"hello\":1}",body)
        val health=MockHttpServletRequest("GET","/actuator/health");var called=false
        AnalyticsBodyLimit().doFilter(health,MockHttpServletResponse(),FilterChain { _,_->called=true });assertTrue(called)
    }
}
