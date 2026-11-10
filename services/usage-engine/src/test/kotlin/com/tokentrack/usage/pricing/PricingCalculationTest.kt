package com.tokentrack.usage.pricing

import com.tokentrack.usage.domain.UsageEvent
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

class PricingCalculationTest {
    private fun event(input:Long=100000,cached:Long=20000,output:Long=10000)=UsageEvent(UUID.randomUUID(),"test","e-1",UUID.randomUUID(),null,"openai","gpt-5.4-mini","coding-assistant",input,output,cached,Instant.parse("2026-11-15T00:00:00Z"),null,null)
    private fun rate(input:String="0.75",cached:String="0.075",output:String="4.5",from:String="2026-11-01T00:00:00Z",until:String?=null)=PricingRate(UUID.randomUUID(),"openai","gpt-5.4-mini","standard_text_cache_read","USD",BigDecimal(input),BigDecimal(cached),BigDecimal(output),Instant.parse(from),until?.let(Instant::parse),"https://developers.openai.com/api/docs/pricing",Instant.parse("2026-11-09T00:00:00Z"),false)
    @Test fun `cached input example is exactly 0 point 1065 dollars`() {
        val result=CostCalculator.calculate(event(),rate())
        assertEquals("0.06",DecimalMoney.text(result.input));assertEquals("0.0015",DecimalMoney.text(result.cached));assertEquals("0.045",DecimalMoney.text(result.output));assertEquals("0.1065",DecimalMoney.text(result.total))
    }
    @Test fun `cached reads are a subset rather than an additional input charge`() {
        val cached=CostCalculator.calculate(event(),rate()).total
        val uncached=CostCalculator.calculate(event(cached=0),rate()).total
        assertEquals("0.12",DecimalMoney.text(uncached));assertTrue(cached<uncached)
    }
    @Test fun `single-token sub-cent costs aggregate without per-event cent rounding`() {
        val micro=CostCalculator.calculate(event(input=1,cached=1,output=0),rate()).total
        assertEquals("0.000000075",DecimalMoney.text(micro))
        assertEquals("0.0075",DecimalMoney.text(micro.multiply(BigDecimal("100000"))))
        val smallest=CostCalculator.calculate(event(input=1,cached=1,output=0),rate(cached="0.000000001")).total
        assertEquals("0.000000000000001",DecimalMoney.text(smallest))
    }
    @Test fun `trillion-token arithmetic stays exact without overflow`() {
        val total=CostCalculator.calculate(event(1_000_000_000_000,200_000_000_000,100_000_000_000),rate()).total
        assertEquals("1065000",DecimalMoney.text(total))
    }
    @Test fun `division precision never silently rounds an unsupported rate`() {
        assertThrows(IllegalArgumentException::class.java) { DecimalMoney.rate("0.0000000001") }
        assertThrows(IllegalArgumentException::class.java) { DecimalMoney.rate("1e-3") }
        assertThrows(IllegalArgumentException::class.java) { CostCalculator.calculate(event(),rate(input="-1")) }
    }
    @Test fun `effective intervals are half open and missing rates stay missing`() {
        val first=rate(input="3",from="2026-11-01T00:00:00Z",until="2026-11-20T00:00:00Z")
        val second=rate(input="2.5",from="2026-11-20T00:00:00Z")
        fun resolve(time:String)=RateResolver.resolve(listOf(first,second),"openai","gpt-5.4-mini","USD","standard_text_cache_read",Instant.parse(time))
        assertEquals(first.id,resolve("2026-11-19T23:59:59Z")!!.id)
        assertEquals(second.id,resolve("2026-11-20T00:00:00Z")!!.id)
        assertNull(resolve("2026-10-31T23:59:59Z"))
        assertEquals(BigDecimal("3"),first.input)
    }
    @Test fun `currency tier model identity and ambiguous schedules cannot be guessed`() {
        val r=rate()
        assertNull(RateResolver.resolve(listOf(r),"openai","GPT-5.4-MINI","USD",r.tier,r.from))
        assertNull(RateResolver.resolve(listOf(r),r.provider,r.model,"EUR",r.tier,r.from))
        assertNull(RateResolver.resolve(listOf(r),r.provider,r.model,"USD","priority",r.from))
        assertThrows(IllegalStateException::class.java) { RateResolver.resolve(listOf(r,r.copy(id=UUID.randomUUID())),r.provider,r.model,r.currency,r.tier,r.from) }
    }
    @Test fun `canonical serialization is decimal text and fixed UTC microseconds`() {
        assertEquals("0",DecimalMoney.text(BigDecimal("0.000000000")))
        assertEquals("1000000",DecimalMoney.text(BigDecimal("1E+6")))
        assertEquals("2026-11-15T00:00:00.000000Z",DecimalMoney.time(Instant.parse("2026-11-15T00:00:00Z")))
    }
}
