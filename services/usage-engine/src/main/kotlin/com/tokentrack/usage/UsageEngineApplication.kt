package com.tokentrack.usage

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class UsageEngineApplication

fun main(args: Array<String>) {
    runApplication<UsageEngineApplication>(*args)
}
