package com.tokentrack.usage

import org.junit.jupiter.api.Test
import org.mockito.Mockito.doThrow
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.get
import java.sql.SQLException
import javax.sql.DataSource

@SpringBootTest(properties = [
    "spring.datasource.url=jdbc:h2:mem:health;DATABASE_TO_LOWER=TRUE;INIT=CREATE SCHEMA IF NOT EXISTS usage",
    "spring.datasource.username=sa",
    "spring.datasource.password=",
    "spring.datasource.driver-class-name=org.h2.Driver"
])
@AutoConfigureMockMvc
class HealthEndpointTest {
    @Autowired lateinit var mvc: MockMvc
    @MockitoSpyBean lateinit var dataSource: DataSource

    @Test
    fun `application starts and health includes a real database check`() {
        mvc.get("/actuator/health").andExpect {
            status { isOk() }
            jsonPath("$.status") { value("UP") }
            jsonPath("$.components.db.status") { value("UP") }
            jsonPath("$.components.db.details") { doesNotExist() }
        }
    }

    @Test
    fun `database failure returns unavailable and DOWN`() {
        doThrow(SQLException("Database unavailable")).`when`(dataSource).connection
        mvc.get("/actuator/health").andExpect {
            status { isServiceUnavailable() }
            jsonPath("$.status") { value("DOWN") }
            jsonPath("$.components.db.status") { value("DOWN") }
        }
    }
}
