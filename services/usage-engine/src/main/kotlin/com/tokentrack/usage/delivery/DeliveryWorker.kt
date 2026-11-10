package com.tokentrack.usage.delivery

import org.springframework.stereotype.Service
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@Service
class DeliveryWorker(private val repository:OutboxRepository,private val gateway:FinancialGateway) {
    fun deliver(limit:Int=1000,workers:Int=4,retryDead:Boolean=false):Map<String,Any> {
        require(limit in 1..10000 && workers in 1..8)
        val reset=if(retryDead) repository.resetDead() else 0
        val results=mutableMapOf("delivered" to 0,"retry" to 0,"dead" to 0,"lease_lost" to 0)
        var attempted=0
        val pool=Executors.newFixedThreadPool(workers)
        try {
            while(attempted<limit) {
                // Leases must cover the entire claimed queue at the configured
                // network timeout, not just a single HTTP request.
                val messages=repository.claim(minOf(workers*4,limit-attempted))
                if(messages.isEmpty()) break
                val tasks=messages.map { message -> pool.submit<String> { repository.finish(message,gateway.post(message.payload)) } }
                tasks.forEach { task -> val status=task.get(60,TimeUnit.SECONDS); results[status]=results.getValue(status)+1; attempted++ }
            }
        } finally { pool.shutdownNow() }
        return results+mapOf("attempted" to attempted,"manually_retried_dead" to reset,"outbox" to repository.report())
    }
}
