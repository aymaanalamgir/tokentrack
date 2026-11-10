package com.tokentrack.usage.delivery

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

data class FinancialResponse(val status:Int,val body:JsonNode?=null)
interface FinancialGateway {
    fun post(payload:String):FinancialResponse
    fun reconcile(ids:List<String>):FinancialResponse
}
@Component
class HttpFinancialGateway(private val mapper:ObjectMapper,
    @param:Value("\${tokentrack.references.url}") private val url:String,
    @param:Value("\${tokentrack.financial.token}") private val token:String):FinancialGateway {
    private val client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).followRedirects(HttpClient.Redirect.NEVER).build()
    private fun request(path:String,payload:String):FinancialResponse {
        if(token.length<32) return FinancialResponse(401)
        return try {
            val uri=URI.create(url.trimEnd('/')+path)
            require(uri.scheme in listOf("http","https") && uri.userInfo==null)
            val request=HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(10)).header("Authorization","Bearer $token")
                .header("Content-Type","application/json").header("Accept","application/json").POST(HttpRequest.BodyPublishers.ofString(payload)).build()
            val response=client.send(request,HttpResponse.BodyHandlers.ofByteArray())
            val body=if(response.body().size<=2*1024*1024 && response.headers().firstValue("content-type").orElse("").contains("application/json")) try { mapper.readTree(response.body()) } catch(_:Exception) { null } else null
            FinancialResponse(response.statusCode(),body)
        } catch(_:Exception) { FinancialResponse(0) }
    }
    override fun post(payload:String)=request("/api/v1/internal/priced-usage-events",payload)
    override fun reconcile(ids:List<String>)=request("/api/v1/internal/financial-reconciliation",mapper.writeValueAsString(mapOf("priced_event_ids" to ids)))
}
