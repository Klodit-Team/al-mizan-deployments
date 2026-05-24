# Local Development & Execution Guide (`al-mizan-local`)

This guide provides the exact, step-by-step instructions to clone, build, run, and seed the entire AL-Mizan platform locally on a developer's machine using **Docker Desktop** and **Docker Compose**.

---

## 1. Prerequisites

Before starting, ensure your local development machine meets the following hardware and software requirements:

* **Operating System:** Windows 10/11 (with WSL2 enabled), macOS, or Linux.
* **RAM:** Minimum **16 GB** (32 GB highly recommended). Running 15 containers simultaneously is highly memory-intensive.
* **Docker:** Installed and running (Docker Desktop for Windows/Mac, Docker Engine + Compose plugin for Linux).
* **Git:** Installed and configured.

---

## 2. Step 1: Clone All Repositories Side-by-Side

To ensure the build contexts inside the `docker-compose.yml` resolve correctly, all 12 repositories must be cloned side-by-side as siblings inside a single parent workspace folder.

Create a parent directory and clone the repositories:

```bash
# Create and enter your local workspace
mkdir -p ~/al-mizan && cd ~/al-mizan

# Clone all 12 repositories
git clone https://github.com/Klodit-Team/al-mizan-api-gateway.git api-gateway
git clone https://github.com/Klodit-Team/al-mizan-auth-service.git auth-service
git clone https://github.com/Klodit-Team/al-mizan-users-service.git users-service
git clone https://github.com/Klodit-Team/al-mizan-appel-offres-service.git appel-offres-service
git clone https://github.com/Klodit-Team/al-mizan-soummission-service.git soumission-service
git clone https://github.com/Klodit-Team/al-mizan-documents-service.git documents-service
git clone https://github.com/Klodit-Team/al-mizan-evaluation-service.git evaluation-service
git clone https://github.com/Klodit-Team/al-mizan-commission-service.git commission-service
git clone https://github.com/Klodit-Team/al-mizan-recours-service.git recours-service
git clone https://github.com/Klodit-Team/al-mizan-notification-service.git notification-service
git clone https://github.com/Klodit-Team/al-mizan-client.git client
git clone https://github.com/Klodit-Team/al-mizan-deployments.git al-mizan-deployments
```

Your local directory structure must look exactly like this:

```text
~/al-mizan/
├── al-mizan-deployments/
├── api-gateway/
├── auth-service/
├── users-service/
├── appel-offres-service/
├── soumission-service/
├── documents-service/
├── evaluation-service/
├── commission-service/
├── recours-service/
├── notification-service/
└── client/
```

---

## 3. Step 2: Create the Shared Virtual Network

The container configurations declare an external network named `al-mizan-network`. You must manually initialize this network once in your local Docker daemon before launching any compose files:

```bash
docker network create al-mizan-network
```

---

## 4. Step 3: Spin Up Core Infrastructure

Navigate into your deployments repository and launch your database, cache, message broker, and object storage containers in the background:

```bash
cd ~/al-mizan/al-mizan-deployments
docker compose -f docker-compose.infra.yml up -d
```

*Wait approximately 30 seconds for the stateful engines (especially MySQL and RabbitMQ) to complete their internal startup sequences and begin accepting connections.*

---

## 5. Step 4: Initialize the Logical Databases

Because the MySQL container starts up as a clean, empty server, you must manually initialize the isolated logical databases required by the microservices.

Run this command block to connect to your running MySQL container and execute the database schema creation script:

```bash
docker exec -i al-mizan-mysql mysql -u root -ppassword -e "
CREATE DATABASE IF NOT EXISTS auth_db;
CREATE DATABASE IF NOT EXISTS al_mizan_users;
CREATE DATABASE IF NOT EXISTS ao_db;
CREATE DATABASE IF NOT EXISTS soumission_db;
CREATE DATABASE IF NOT EXISTS document_db;
CREATE DATABASE IF NOT EXISTS evaluation_db;
CREATE DATABASE IF NOT EXISTS commission_db;
CREATE DATABASE IF NOT EXISTS recours_db;
CREATE DATABASE IF NOT EXISTS notif_db;
"
```

---

## 6. Step 5: Build and Start Application Services

Now that your local databases exist and the shared network is active, compile and run the 11 stateless application microservices and the web frontend:

```bash
docker compose up -d --build
```

*Note: This first build will take several minutes as it downloads base images, installs node dependencies, and compiles the Next.js and Spring Boot binaries.*

---

## 7. Step 6: Populate Database Seeds (MANDATORY)

To navigate the platform, you must populate the empty database tables with default security roles, test operator profiles, and your master administrator account (`admin@al-mizan.dz` / `Admin@123`).

Because of production optimizations (like multi-stage builds) and ES Module (ESM) constraints within the containers, execute these precise commands one by one:

#### **1. Seed the Auth Service (Creates base security accounts)**

```bash
docker exec -it auth-service npm run db:seed
```

#### **2. Seed the Users Service (Bypasses ESM node restrictions)**

```bash
docker exec -it users-service npx ts-node -O '{"module":"commonjs"}' prisma/seed.ts
```

#### **3. Seed the Appels d'Offres Service (Populates sample tenders)**

```bash
docker exec -it appel-offres-service npm run db:seed
```

#### **4. Seed the Commission Service (Runs compiled JS inside /dist)**

```bash
docker exec -it commission-service node dist/database/seed.js
```

#### **5. Seed the Evaluation Service (Runs compiled JS inside /dist)**

```bash
docker exec -it evaluation-service node dist/database/seed.js
```

#### **6. Seed the Recours Service (Bypasses ESM restrictions)**

```bash
docker exec -it recours-service npx ts-node -O '{"module":"commonjs"}' prisma/seed.ts
```

#### **7. Verify All Organizations (Auto-approves operator profiles for testing)**

To test the electronic bidding/submission workflow, registered companies must be verified. Run this SQL query to auto-verify all registrants:

```bash
docker exec -i al-mizan-mysql mysql -u root -ppassword -e "USE al_mizan_users; UPDATE organisations SET is_verified = true;"
```

---

## 8. Local Access Ports

Once completed, you can access your local environment at the following endpoints:

* **Web Frontend:** `http://localhost:4000`
* **API Gateway (Base API):** `http://localhost:3000/api/v1`
* **API Documentation (Swagger UI):** `http://localhost:3000/docs`
* **RabbitMQ Management UI:** `http://localhost:15672` (User: `guest` / Password: `guest`)
* **MinIO Storage Console:** `http://localhost:9001` (User: `minioadmin` / Password: `minioadmin`)
