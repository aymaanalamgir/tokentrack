FROM gradle:8.14.3-jdk21 AS development
WORKDIR /app
COPY --chown=gradle:gradle . .
RUN gradle dependencies --no-daemon > /tmp/dependencies.txt
EXPOSE 8080
CMD ["gradle", "bootRun", "--no-daemon"]

FROM development AS build
RUN gradle bootJar --no-daemon

FROM eclipse-temurin:21-jre AS production
WORKDIR /app
COPY --from=build /app/build/libs/usage-engine.jar app.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
