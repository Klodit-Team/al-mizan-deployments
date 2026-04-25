# *(AI SYSTEM PROMPT: ARCHITECTURAL BOUNDARIES & CONTEXT)*


## SYSTEM ARCHITECTURE & CONTEXT HANDOFF DOCUMENT

**Project Name:** **AL-Mizan (Public Procurement Platform / e-Procurement)**
Architecture: **Event-Driven Microservices (Dockerized)**
Deployment: **Single Google Cloud Platform (GCP) Compute Engine VM (Debian 11)**

**Hello AI! I am transitioning from a previous architecture setup chat. You are now assisting me as a Senior DevOps and Full-Stack Architect. Below is the complete context of my environment. Please read this carefully and strictly adhere to these constraints when providing solutions.**

### 1. Infrastructure (GCP & Networking)

* **Public IP**: **34.155.70.30**
* **DNS & Routing**: Managed via Cloudflare.

  * **https://klodit.app** **→ Cloudflare Origin Rule rewrites to** **34.155.70.30:4000** **(Next.js Client).**
* **https://api.klodit.app** **→ Cloudflare Origin Rule rewrites to** **34.155.70.30:3000** **(API Gateway).**
* **TLS is handled by Cloudflare (Flexible mode).**
* **Constraint**: Do NOT suggest managed cloud databases (Cloud SQL, Memorystore). Everything runs locally on this single VM via **docker-compose** **to fit a strict startup budget.**

### 2. Docker Compose Topology (**al-mizan-deployments** **repo)**

**All services run in a single** **docker-compose.yml** **under a custom external bridge network (**al-mizan-network**).**

**Infrastructure Containers:**

* **al-mizan-mysql** **(MySQL 8): Exposed on** **3306**. Houses **all** **microservice databases (**auth_db**,** **al_mizan_users**, **document_db**, **ao_db**, **soumission_db**, **evaluation_db**, **commission_db**, **recours_db**, **notif_db**).
* **al-mizan-redis** **(Redis 7-alpine): Exposed on** **6379**. Used for Session caching, Rate Limiting, and JWT Blacklisting.
* **al-mizan-rabbitmq** **(RabbitMQ 3-management): Exposed on** **5672**. Exchange: **al-mizan.events** **(topic).**
* **al-mizan-minio** **(MinIO): Exposed on** **9000** **(API) and** **9001** **(Console). Used for secure PDF/Document storage.**

**Microservice Containers (11 total):**

* **api-gateway** **(Port 3000): Node.js / Express.**
* **auth-service** **(Port 3001): Node.js / Prisma.**
* **users-service** **(Port 3002): NestJS / Prisma.**
* **documents-service** **(Port 8005): NestJS / Prisma.**
* **appel-offres-service** **(Port 8003): NestJS / Prisma.**
* **soumission-service** **(Port 8004):** **Java Spring Boot 3 / Hibernate**. (Handles Shamir Secret Sharing & AES-GCM Encryption).
* **evaluation-service** **(Port 8008): NestJS / TypeORM.**
* **commission-service** **(Port 8007): NestJS / TypeORM.**
* **recours-service** **(Port 8008 mapped to 8008): NestJS / Prisma 7 (Requires** **prisma.config.ts**).
* **notification-service** **(Port 8010): NestJS / Prisma.**
* **client** **(Port 4000): Next.js 15+ (App Router).**

### 3. CI/CD Pipeline (GitHub Actions)

* **GitOps Workflow**: We use GitHub Actions (**appleboy/ssh-action**) to automate deployments.
* **Secrets**: **GCP_HOST**, **GCP_USERNAME**, and **GCP_SSH_KEY** **are injected into every private repository using the** **gh** **CLI.**
* **Trigger**: Any push to **main** **triggers a workflow that SSHs into the GCP server, pulls the specific repository, navigates to** **~/al-mizan-deployment**, and runs **sudo docker-compose up -d --build <service_name>**.

### 4. Technical Quirks & Hacks Applied (DO NOT REVERT THESE)

* **Alpine Linux & Prisma**: Added **RUN apk add --no-cache openssl** **to all Node Dockerfiles to prevent Prisma Engine crashes on Alpine.**
* **Next.js 15 Suspense**: Added a **`<Suspense>`** **boundary in** **src/app/[locale]/auth/layout.tsx** **to prevent production build crashes caused by** **useSearchParams()**.
* **API Gateway Routing**: The backend services use global prefixes (e.g., **/api/v1/** **or** **/recours-service/v1/**). The API Gateway handles the routing via **http-proxy-middleware**.
* **TypeORM Auto-Migration**: For **evaluation-service** **and** **commission-service**, **NODE_ENV=development** **is forced in the** **docker-compose.yml** **so TypeORM uses** **synchronize: true** **to auto-create tables.**
* **Shamir's Secret Sharing (Java)**: The Java **soumission-service** **implements strict Shamir cryptography. It requires exactly 5 User IDs (Commission Members) to generate a key, and exactly 3 Key Fragments (**fragment_cle**) to decrypt financial offers.**
* **E2EE File Uploads (Java)**: MinIO financial uploads require **fichierChiffre** **(AES encrypted),** **signatureEcdsa** **(digital signature), and** **clePubliqueEcdsaPem**.

### 5. Current State & Testing

* **All 11 microservices and 5 infra containers are** **UP** **and** **healthy**.
* **We have a comprehensive Integration Test suite in** **~/Al-Mizan-Tests/** **consisting of 8 bash scripts (**phase1.sh **to** **phase8.sh**) that use **curl** **and** **jq** **to execute the full Golden Path (Auth -> Tender -> E2EE Bid -> Shamir Decrypt -> Score -> Contract -> Appeal -> Notification).**
* **Everything is 100% operational.**
