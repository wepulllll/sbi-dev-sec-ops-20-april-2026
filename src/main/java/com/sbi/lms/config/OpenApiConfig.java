package com.sbi.lms.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

/**
 * OpenAPI / Swagger UI configuration.
 *
 * Exposes /v3/api-docs for ZAP DAST auto-discovery.
 * The Authorize button in Swagger UI lets you paste a JWT token for manual testing.
 *
 * DevSecOps note: Swagger MUST be disabled in production
 * (springdoc.swagger-ui.enabled=false in application-prod.properties).
 * Swagger is an attack surface — it documents every endpoint and parameter for attackers.
 */
@Configuration
public class OpenApiConfig {

    @Value("${lms.app.name:SBI Loan Management System}")
    private String appName;

    @Value("${lms.app.version:1.0.0}")
    private String appVersion;

    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title(appName + " — REST API")
                        .version(appVersion)
                        .description(
                            "**SBI Loan Management System** REST API\n\n"
                            + "DevSecOps Training Project — State Bank of India\n\n"
                            + "---\n\n"
                            + "### How to Authenticate\n\n"
                            + "1. Expand **Authentication** below → `POST /api/v1/auth/login`\n"
                            + "2. Click **Try it out** → fill in username and password → **Execute**\n"
                            + "3. Copy the `token` value from the response body\n"
                            + "4. Click **Authorize** (top right) → paste the token → **Authorize**\n\n"
                            + "---\n\n"
                            + "### Training Accounts\n\n"
                            + "| Username | Password | Role | Access Level |\n"
                            + "|---|---|---|---|\n"
                            + "| `admin@sbi.com` | `Admin@123` | ADMIN | Full access — all operations |\n"
                            + "| `officer@sbi.com` | `Officer@123` | USER | Read + own records only |\n\n"
                            + "---\n\n"
                            + "### Known Issues (Pre-Training — Fix During Labs)\n\n"
                            + "| # | Endpoint | Issue | Lab |\n"
                            + "|---|---|---|---|\n"
                            + "| 1 | `POST /api/v1/auth/login` | Credentials sent as query params — logged in URLs | Lab 1 |\n"
                            + "| 2 | `GET /api/v1/applications` | Returns raw entity — sensitive fields exposed to all users | Lab 1 |\n"
                            + "| 3 | `GET /api/v1/applications/search` | SQL injection via branch name parameter | Lab 2 |\n"
                            + "| 4 | All write endpoints | No `@PreAuthorize` — any user can create/update/delete | Lab 1 |\n\n"
                            + "---\n\n"
                            + "> ⚠️ **Swagger UI is disabled in production** "
                            + "(`springdoc.swagger-ui.enabled=false` in `application-prod.properties`). "
                            + "Swagger documents every endpoint and parameter — "
                            + "leaving it on in production gives attackers a complete API map."
                        )
                        .contact(new Contact()
                                .name("SBI Technology Training Team")
                                .email("training@sbi.co.in"))
                        .license(new License()
                                .name("Internal Training Use Only")
                                .url("https://www.sbi.co.in")))

                .servers(List.of(
                        new Server()
                            .url("http://localhost:8080")
                            .description("Local Development")))

                // Registers the Authorize button in Swagger UI
                .components(new Components()
                        .addSecuritySchemes("bearerAuth",
                                new SecurityScheme()
                                        .type(SecurityScheme.Type.HTTP)
                                        .scheme("bearer")
                                        .bearerFormat("JWT")
                                        .description(
                                            "Paste the token returned by POST /api/v1/auth/login. "
                                            + "Do NOT include the word 'Bearer' here.")))
                .addSecurityItem(new SecurityRequirement().addList("bearerAuth"));
    }
}
