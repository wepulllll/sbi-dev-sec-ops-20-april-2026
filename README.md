# SBI Loan Management System (LMS)
## DevSecOps Intermediate Training — Java Spring Boot Project

> **This project is the hands-on vehicle for the SBI DevSecOps Intermediate training.**
> It is intentionally simple — three entities, JWT auth, REST API — so all lab time is
> spent on security tooling, not on understanding business logic.

---

## Quick Start

```bash
# 1. Build
mvn clean package -DskipTests

# 2. Run (set JWT_SECRET so the app starts cleanly)
export JWT_SECRET=dev-secret-key-change-in-prod
mvn spring-boot:run

# 3. Verify
curl http://localhost:8080/actuator/health
# → {"status":"UP"}

# 4. Open Swagger UI
# http://localhost:8080/swagger-ui.html
```

### Test Accounts

| Email | Password | Role |
|---|---|---|
| `admin@sbi.com` | `Admin@123` | MANAGER (sees full PII) |
| `officer@sbi.com` | `Officer@123` | OFFICER (PAN masked, income/CIBIL hidden) |

### Get a JWT Token

```bash
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@sbi.com","password":"Admin@123"}' | python -m json.tool
```

Copy the token, then use it:

```bash
TOKEN=<paste token here>

# List all applications (MANAGER sees full PII)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/applications

# Get single application
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/applications/1

# List branches
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/branches

# List loan products
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/products
```

---

## Lab Reference

### Lab 1 — SAST Scan + Fix (Day 1, 12:30–1:30)

```bash
# Step 1: Build
mvn clean package -DskipTests

# Step 2: Run SonarQube scan (trainer provides SONAR_IP and TOKEN)
mvn sonar:sonar  -Dsonar.host.url=http://SONAR_IP:9000 -Dsonar.token=YOUR_TOKEN

# Open dashboard → http://SONAR_IP:9000/dashboard?id=sbi-lms
# Find two Critical issues:
#   1. Hardcoded JWT secret in JwtUtils.java (java:S6418)
#   2. Missing @PreAuthorize on ApplicationController.getById()

# Step 3: Fix Issue 1 — in JwtUtils.java, delete:
#   private static final String JWT_SECRET = "SBIBankingSecretKey2024";
#   private static final long   JWT_EXPIRY  = 86400000;
# Uncomment:
#   @Value("${jwt.secret}")
#   private String jwtSecret;
#   @Value("${jwt.expiration.ms:900000}")
#   private long jwtExpirationMs;

# Step 4: Fix Issue 2 — in ApplicationController.java getById():
#   Add @PreAuthorize("hasAnyRole('MANAGER','OFFICER')")
#   Uncomment the maskPiiIfOfficer line

# Step 5: Re-scan
mvn clean package -DskipTests sonar:sonar -Dsonar.host.url=http://SONAR_IP:9000 -Dsonar.token=YOUR_TOKEN

# Expected: Quality Gate PASSED, 0 Critical issues
```

---

### Lab 2 — DAST Scan (Day 1, 3:00–4:00)

```bash
# Step 1: Start LMS with Docker
docker build -f Dockerfile.secure -t lms:secure .
docker compose up -d

# Step 2: Confirm OpenAPI spec
curl http://localhost:8080/v3/api-docs | python -m json.tool | head -20

# Step 3: Open ZAP → Import > OpenAPI definition from URL
#   URL: http://localhost:8080/v3/api-docs

# Step 4: Get JWT and configure ZAP Authorization header
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@sbi.com","password":"Admin@123"}'

# Step 5: Right-click site in ZAP → Attack → Active Scan
# Expected alerts: Missing CSP header, X-Content-Type-Options, CORS issues

# Step 6: Apply security header fixes in SecurityConfig.java (already present)
# Rebuild and re-scan → header alerts should disappear
mvn clean package -DskipTests
docker compose down && docker compose up -d
```

---

### Lab 3 — Container Scan + Dockerfile Hardening (Day 2, 11:30–12:15)

```bash
# Step 1: Build insecure image
mvn clean package -DskipTests
docker build -f Dockerfile.insecure -t lms:insecure .

# Step 2: Scan insecure image — record HIGH/CRITICAL count
trivy image --severity HIGH,CRITICAL lms:insecure

# Step 3: Build secure image
docker build -f Dockerfile.secure -t lms:secure .

# Step 4: Re-scan — compare CVE counts
trivy image --severity HIGH,CRITICAL lms:secure

# Step 5: Compare image sizes
docker images | grep lms

# Step 6: Scan Dockerfile for misconfigurations
trivy config ./Dockerfile.secure
```

---

### Lab 4 — IaC Security Scan (Day 2, 1:30–2:15)

```bash
cd terraform/lms

# Step 1: Scan — note all FAILED checks
checkov -d . --compact

# Step 2: Fix the three misconfigurations in main.tf:
#   - aws_db_instance:    publicly_accessible = false
#                         storage_encrypted   = true
#                         deletion_protection = true
#                         multi_az            = true
#   - aws_s3_bucket:      remove acl "public-read" resource
#                         add aws_s3_bucket_public_access_block
#                         add aws_s3_bucket_server_side_encryption_configuration
#   - aws_security_group: restrict ingress (see comments in main.tf)

# Step 3: Re-scan — confirm 0 FAILED
checkov -d . --compact

# Step 4: Add custom SBI policy (Multi-AZ check)
checkov -d . --external-checks-dir ../../custom_policies --compact
# Expected: CKV_SBI_001 PASSED (after you set multi_az = true)
```

---

### Capstone Lab — Full Pipeline (Day 2, 4:00–5:00)

```bash
# Step 1: Introduce the SQL injection vulnerability
# In ApplicationController.java → the /search endpoint is ALREADY vulnerable.
# Commit it:
git add . && git commit -m "feat: add branch search endpoint"

# Step 2: Run SAST — confirm Blocker detected
mvn clean package -DskipTests sonar:sonar \
  -Dsonar.host.url=http://SONAR_IP:9000 \
  -Dsonar.token=YOUR_TOKEN
# Open dashboard → find SQL injection Blocker on /search

# Step 3: Confirm with DAST (ZAP)
docker compose up -d
# In ZAP: Spider + Active Scan → check /api/v1/applications/search for SQLi
# Fuzz with payload: ' OR '1'='1

# Step 4: Fix — in ApplicationController.java searchByBranch():
#   Delete the em.createQuery(...) block
#   Uncomment the safe findByBranchName() block

# Step 5: Rebuild and re-scan
mvn clean package -DskipTests
docker build -f Dockerfile.secure -t lms:capstone .
trivy image --severity HIGH,CRITICAL --exit-code 1 lms:capstone

# Step 6: IaC scan
checkov -d terraform/lms --compact

# Step 7: Final DAST
docker compose down && docker compose up -d
# Re-run ZAP Active Scan → SQL injection alert on /search is gone

# Full pipeline clean: SAST ✓  Container ✓  IaC ✓  DAST ✓
```

---

### Secrets Management Setup (Day 1, 4:00–4:45)

```bash
# Install detect-secrets and set up pre-commit hook
chmod +x setup-hooks.sh && ./setup-hooks.sh 
OR 
"C:\Program Files\Git\bin\sh.exe" setup-hooks.sh

# Test the hook
echo 'password=SuperSecret123' > test-secret.txt
git add test-secret.txt && git commit -m "test"
# Expected: COMMIT BLOCKED

rm test-secret.txt

# Vault (dev mode — lab only)
docker run --rm -d --name vault \
  -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  hashicorp/vault:latest

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

vault kv put secret/lms \
  db_password=SBI_LMS_DB_2024 \
  jwt_secret=$(openssl rand -hex 32)

vault kv get -field=jwt_secret secret/lms
```

---

### Semgrep (optional — command-line SAST)

```bash
# OWASP Top 10 rules
semgrep --config=p/owasp-top-ten ./src

# Custom LMS rules
semgrep --config=semgrep/lms-security-rules.yaml ./src
# Will flag: hardcoded JWT secret + string-concat JPQL
```

---

## Project Structure

```
lms/
├── src/main/java/com/sbi/lms/
│   ├── LmsApplication.java
│   ├── aspect/
│   │   └── AuditAspect.java            ← RBI audit logging (A09)
│   ├── config/
│   │   ├── SecurityConfig.java         ← CORS, headers, JWT filter (A05)
│   │   └── OpenApiConfig.java          ← Swagger/ZAP integration
│   ├── controller/
│   │   ├── AuthController.java         ← POST /api/v1/auth/login
│   │   ├── ApplicationController.java  ← LAB 1 + CAPSTONE targets
│   │   ├── BranchController.java
│   │   └── LoanProductController.java
│   ├── dto/                            ← Request/Response objects with @Valid
│   ├── exception/
│   │   └── GlobalExceptionHandler.java ← Secure error handling (A05)
│   ├── model/                          ← JPA entities (PII in LoanApplication)
│   ├── repository/                     ← Spring Data (safe derived queries)
│   ├── security/
│   │   └── JwtUtils.java               ← LAB 1: hardcoded secret to find+fix
│   └── service/
│       ├── LoanApplicationService.java ← State machine (A04), PII handling
│       └── SecurityService.java        ← PAN masking, role checks
├── src/main/resources/
│   ├── application.properties          ← Env-var references, no secrets
│   └── data.sql                        ← Seed data (4 applications, 2 users)
├── terraform/lms/
│   └── main.tf                         ← LAB 4: 3 misconfigs to find+fix
├── custom_policies/
│   └── CKV_SBI_001.py                  ← Custom Checkov policy (Multi-AZ)
├── semgrep/
│   └── lms-security-rules.yaml        ← Custom Semgrep rules
├── .github/workflows/
│   └── devsecops.yml                   ← Full 6-stage pipeline
├── Dockerfile.insecure                 ← LAB 3: scan this first
├── Dockerfile.secure                   ← LAB 3: compare after hardening
├── docker-compose.yml                  ← Runtime security constraints
├── .env.example                        ← Template — copy to .env (gitignored)
├── .secrets.baseline                   ← detect-secrets approved baseline
├── .gitignore                          ← .env excluded
├── setup-hooks.sh                      ← One-time pre-commit hook setup
└── pom.xml                             ← SonarQube + OWASP Dependency-Check
```

## Intentional Vulnerabilities (Lab Targets)

| Location | Vulnerability | Tool that finds it | Lab |
|---|---|---|---|
| `JwtUtils.java:27` | Hardcoded JWT secret | SonarQube (java:S6418) | Lab 1 |
| `ApplicationController.java:getById()` | Missing `@PreAuthorize` | SonarQube | Lab 1 |
| `ApplicationController.java:searchByBranch()` | SQL injection (string-concat JPQL) | SonarQube + ZAP | Capstone |
| `Dockerfile.insecure` | Root user, full JDK, no healthcheck | Trivy | Lab 3 |
| `terraform/lms/main.tf` | Public RDS, open S3, open SG | Checkov | Lab 4 |
