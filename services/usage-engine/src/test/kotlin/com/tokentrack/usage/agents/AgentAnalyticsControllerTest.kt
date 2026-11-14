package com.tokentrack.usage.agents

import com.fasterxml.jackson.databind.ObjectMapper
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.mockito.Mockito.mock
import org.springframework.jdbc.core.JdbcTemplate

class AgentAnalyticsControllerTest {
    private val token="a".repeat(64)
    private val controller=AgentAnalyticsController(AgentAnalytics(mock(JdbcTemplate::class.java)),AgentInsights(mock(JdbcTemplate::class.java),InsightThresholds()),token)
    private val body=ObjectMapper().createObjectNode()
    @Test fun `internal endpoint rejects browser and unrelated credentials`() {
        assertEquals(401,controller.report(null,body).statusCode.value())
        assertEquals(401,controller.report("Bearer "+"b".repeat(64),body).statusCode.value())
        assertEquals(400,controller.report("Bearer $token",body).statusCode.value())
    }
}
