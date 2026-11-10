package com.tokentrack.usage.analytics

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import jakarta.servlet.http.HttpServletRequestWrapper
import jakarta.servlet.ServletInputStream
import jakarta.servlet.ReadListener
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.io.ByteArrayInputStream

@Component
class AnalyticsBodyLimit:OncePerRequestFilter() {
    override fun doFilterInternal(request:HttpServletRequest,response:HttpServletResponse,chain:FilterChain) {
        if(request.requestURI!="/internal/v1/analytics") { chain.doFilter(request,response);return }
        val bytes=request.inputStream.readNBytes(65537)
        if(bytes.size>65536) { response.status=413;return }
        val stream=ByteArrayInputStream(bytes)
        val wrapped=object:HttpServletRequestWrapper(request) {
            override fun getInputStream()=object:ServletInputStream() {
                override fun read()=stream.read()
                override fun isFinished()=stream.available()==0
                override fun isReady()=true
                override fun setReadListener(listener:ReadListener?) {}
            }
        }
        chain.doFilter(wrapped,response)
    }
}
