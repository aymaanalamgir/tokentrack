import java.nio.file.Files
import java.nio.file.StandardCopyOption

plugins {
    kotlin("jvm") version "2.2.21"
    kotlin("plugin.spring") version "2.2.21"
    id("org.springframework.boot") version "3.5.16"
    id("io.spring.dependency-management") version "1.1.7"
}

group = "com.tokentrack"
version = "0.1.0"

java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }
kotlin { compilerOptions { freeCompilerArgs.addAll("-Xjsr305=strict") } }
repositories { mavenCentral() }

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-jdbc")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")
    implementation("org.jetbrains.kotlin:kotlin-reflect")
    implementation("org.apache.commons:commons-csv:1.14.1")
    implementation("org.flywaydb:flyway-core")
    runtimeOnly("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")
    developmentOnly("org.springframework.boot:spring-boot-devtools")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("com.h2database:h2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<Test> { useJUnitPlatform() }
tasks.bootJar { archiveFileName.set("usage-engine.jar") }
dependencyLocking { lockAllConfigurations() }

springBoot { mainClass.set("com.tokentrack.usage.UsageEngineApplicationKt") }
tasks.register<Test>("integrationTest") {
    description = "Real PostgreSQL ingestion tests; requires USAGE_TEST_DB_* environment"
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform { includeTags("postgres") }
    shouldRunAfter(tasks.test)
    // External PostgreSQL state must be checked even when source files did not change.
    outputs.upToDateWhen { false }
}
tasks.test { useJUnitPlatform { excludeTags("postgres") } }

tasks.register("writeCliClasspath") {
    doLast {
        val target = layout.buildDirectory.file("cli-classpath.txt").get().asFile.toPath()
        Files.createDirectories(target.parent)
        val temporary = Files.createTempFile(target.parent, "cli-classpath-", ".tmp")
        val classpath = sourceSets.main.get().runtimeClasspath.filter { !it.name.startsWith("spring-boot-devtools-") }.asPath
        Files.writeString(temporary, classpath)
        Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }
}
