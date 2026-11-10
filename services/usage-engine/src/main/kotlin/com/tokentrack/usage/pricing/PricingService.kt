package com.tokentrack.usage.pricing

import org.springframework.stereotype.Service
import java.util.UUID

@Service
class PricingService(private val repository: PricingRepository) {
    fun price(source:String?=null):Map<String,Any> {
        val rates=repository.rates(); val mappings=repository.mappings().associateBy { Triple(it.source,it.provider,it.model) }
        val outcomes=linkedMapOf("evaluated" to 0,"priced" to 0,"missing_rate" to 0,"insufficient_billing_metadata" to 0,"unsupported_profile" to 0,"failed_calculations" to 0,"concurrent_replays" to 0)
        val already=repository.counts(source)["priced"]!!
        var after:UUID?=null
        while(true) {
            val (records,_)=repository.batch(after,source) { batch ->
                batch.forEach { stored ->
                    val e=stored.event; outcomes["evaluated"]=outcomes.getValue("evaluated")+1
                    val mapping=mappings[Triple(e.source,e.provider,e.model)]
                    if(mapping==null) {
                        val code=if(RateResolver.resolve(rates,e.provider,e.model,"USD","standard_text_cache_read",e.occurredAt)!=null) "insufficient_billing_metadata" else "missing_rate"
                        repository.fail(stored,code.uppercase()); outcomes[code]=outcomes.getValue(code)+1
                    } else {
                        val rate=RateResolver.resolve(rates,mapping.targetProvider,mapping.targetModel,mapping.currency,mapping.tier,e.occurredAt)
                        val code=when {
                            rate==null -> "missing_rate"
                            mapping.basis !in setOf("synthetic_standard_cache_read","attested_standard_cache_read") || mapping.tier!="standard_text_cache_read" || e.inputTokens>mapping.maxInput || e.outputTokens>mapping.maxOutput || e.inputTokens+e.outputTokens>mapping.maxContext -> "unsupported_profile"
                            else -> null
                        }
                        if(code!=null) { repository.fail(stored,code.uppercase()); outcomes[code]=outcomes.getValue(code)+1 }
                        else {
                            val cost=try { CostCalculator.calculate(e,requireNotNull(rate)) } catch (_:ArithmeticException) { null }
                            if(cost==null) { repository.fail(stored,"FAILED_CALCULATION"); outcomes["failed_calculations"]=outcomes.getValue("failed_calculations")+1 }
                            else { val id=repository.persist(stored,mapping,requireNotNull(rate),cost); val category=if(id==null) "concurrent_replays" else "priced"; outcomes[category]=outcomes.getValue(category)+1 }
                        }
                    }
                }
            }
            if(records.isEmpty()) break
            after=records.last().id
        }
        return outcomes+mapOf("already_priced" to already,"summary" to repository.counts(source))
    }
}
