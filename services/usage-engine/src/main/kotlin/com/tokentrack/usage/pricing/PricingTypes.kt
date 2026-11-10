package com.tokentrack.usage.pricing

import com.tokentrack.usage.domain.UsageEvent
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.format.DateTimeFormatterBuilder
import java.util.UUID

data class PricingRate(val id: UUID, val provider: String, val model: String, val tier: String, val currency: String,
    val input: BigDecimal, val cached: BigDecimal, val output: BigDecimal, val from: Instant, val until: Instant?,
    val sourceUrl: String, val verifiedAt: Instant, val synthetic: Boolean)
data class PricingMapping(val id: UUID, val source: String, val provider: String, val model: String,
    val targetProvider: String, val targetModel: String, val tier: String, val currency: String, val basis: String,
    val description: String, val maxInput: Long, val maxOutput: Long, val maxContext: Long)
data class Cost(val input: BigDecimal, val cached: BigDecimal, val output: BigDecimal) {
    val total: BigDecimal get() = input.add(cached).add(output)
}
object DecimalMoney {
    val million = BigDecimal("1000000")
    private val utcMicros = DateTimeFormatterBuilder().appendInstant(6).toFormatter()
    fun text(value: BigDecimal): String = value.stripTrailingZeros().toPlainString()
    fun time(value: Instant): String = utcMicros.format(value)
    fun rate(value: String): BigDecimal {
        require(Regex("(?:0|[1-9][0-9]{0,8})(?:\\.[0-9]{1,9})?").matches(value)) { "Rates require fixed nonnegative decimal strings" }
        return BigDecimal(value)
    }
}
object CostCalculator {
    fun calculate(event: UsageEvent, rate: PricingRate): Cost {
        require(event.cachedInputTokens in 0..event.inputTokens && event.inputTokens >= 0 && event.outputTokens >= 0)
        require(listOf(rate.input,rate.cached,rate.output).all { it.signum() >= 0 && it.scale() <= 9 })
        fun part(tokens: Long, price: BigDecimal) = BigDecimal.valueOf(tokens).multiply(price).divide(DecimalMoney.million,15,RoundingMode.UNNECESSARY)
        return Cost(part(event.inputTokens-event.cachedInputTokens,rate.input),part(event.cachedInputTokens,rate.cached),part(event.outputTokens,rate.output))
    }
}
object RateResolver {
    fun resolve(rates: List<PricingRate>, provider: String, model: String, currency: String, tier: String, time: Instant): PricingRate? {
        val matches = rates.filter { it.provider==provider && it.model==model && it.currency==currency && it.tier==tier && it.from<=time && (it.until==null || time<it.until) }
        check(matches.size<=1) { "Ambiguous pricing schedule" }
        return matches.singleOrNull()
    }
}
