<<<<<<< Updated upstream

# AL-Mizan Deployment Registry (`al-mizan-deployments`)

This repository contains the orchestration, configuration, and environment setup required to deploy and run the **AL-Mizan** platform—a sovereign and intelligent public procurement management system.

The architecture is designed around an event-driven microservices topology, logically isolated at the service and database layers while being resource-optimized to run on a single host.

---

## 1. System Overview & Current Architecture

The production-like environment for the AL-Mizan platform is deployed on **Google Cloud Platform (GCP)** and routed securely via **Cloudflare**.

### Infrastructure Specs (GCP VM)

* **Instance Name:** `almizan`
* **Machine Type:** `c3d-standard-8` (Compute Engine 3rd Generation AMD)
* **CPU:** 8 vCPUs (Dedicated AMD EPYC Genoa Zen 4 threads with AVX-512 acceleration)
* **RAM:** 32 GB DDR5 High-Bandwidth Memory
* **Storage:** 100 GB Hyperdisk Balanced (`pd-balanced` / `pd-ssd`)
* **Region/Zone:** Netherlands (`europe-west4-a`)
* **Hardware Offloading:** Powered by Google's custom **Titanium IPU** (Infrastructure Processing Unit) to offload storage, networking, and hypervisor tasks.

### Networking & Routing Topology

* **Static External IP:** `34.7.144.196`
* **Primary Domain:** `https://klodit.app` (Routes to Next.js Client on Port `4000`)
* **API Domain:** `https://api.klodit.app` (Routes to API Gateway on Port `3000`)
* **DNS & WAF Provider:** Cloudflare
  * *Flexible SSL:* Manages public HTTPS (TLS 1.3) termination at the edge.
  * *Origin Rules:* Rewrites incoming traffic on port 80/443 directly to origin ports `4000` (for web client) and `3000` (for API gateway).

## 2. Docker Compose Topology

The platform deployment is split into two distinct orchestration files to ensure clean lifecycle management:

### A. Core Infrastructure (`docker-compose.infra.yml`)

Deploys shared middleware and stateful data stores on an isolated, external network.

* **MySQL 8 (`al-mizan-mysql`):** Listens on port `3306`. Persisted via `mysql_data` volume. Holds all isolated logical microservice databases.
* **Redis 7 (`al-mizan-redis`):** Listens on port `6379`. Handles session stores and global cache limits.
* **RabbitMQ 3 (`al-mizan-rabbitmq`):** Listens on ports `5672` (AMQP) and `15672` (Management UI). Manages asynchronous event publishing.
* **MinIO (`al-mizan-minio`):** Listens on ports `9000` (S3 API) and `9001` (Console). Persisted via `minio_data` volume. Manages encrypted administrative and financial PDF document storage.

### B. Microservices Application (`docker-compose.yml`)

Deploys the 11 stateless application containers. Build contexts are mapped as relative siblings (e.g., `../auth-service`).

* **api-gateway (Port `3000`):** Single entry point routing requests, validating RBAC, and publishing audit logs.
* **auth-service (Port `3001`):** Handles JWT generation, rotation, sessions, and MFA/TOTP flows.
* **users-service (Port `3002`):** Manages user profiles, organizations, and role assignments.
* **client (Port `4000`):** Next.js 14 bilingual web application.
* **appel-offres-service (Port `8003`):** Manages tender creation, lots, and eligibility rules.
* **soumission-service (Port `8004`):** Java Spring Boot application implementing E2EE bid submission.
* **documents-service (Port `8005`):** Integrates OCR/NLP processing and MinIO client integrations.
* **evaluation-service (Port `8008`):** Handles bid scoring, grading matrices, and ranking calculations.
* **commission-service (Port `8007`):** Manages opening sessions, jury quorums, and PV generation.
* **recours-service (Port `8008`):** Processes operator appeals and legal timeline verifications.
* **notification-service (Port `8010`):** Dispatches SMTP emails, SMS, and Android push notifications.

---

## 3. Database Isolation (Database-per-Service Pattern)

The platform utilizes a **Schema-per-Service** strategy.

While optimized physically inside a single MySQL engine container to prevent RAM exhaustion (OOM), each microservice is strictly isolated inside its own private logical database schema. Cross-service database queries are structurally impossible.

| Microservice             | Logical Database Schema |
| ------------------------ | ----------------------- |
| `auth-service`         | `auth_db`             |
| `users-service`        | `al_mizan_users`      |
| `appel-offres-service` | `ao_db`               |
| `soumission-service`   | `soumission_db`       |
| `documents-service`    | `document_db`         |
| `evaluation-service`   | `evaluation_db`       |
| `commission-service`   | `commission_db`       |
| `recours-service`      | `recours_db`          |
| `notification-service` | `notif_db`            |

---

## 4. Next.js Server-Side Render (SSR) Cloudflare Bypass

In traditional architectures where Next.js runs behind Cloudflare, server-side fetch calls (SSR) pointing back to the public domain (e.g., `https://klodit.app`) trigger **Cloudflare Error 1000 (prohibited IP loopback)** because Cloudflare detects a loopback connection coming from the origin IP itself.

To resolve this, the AL-Mizan frontend implements a **Server-Side Decoupling Pattern** in `client.ts`:

```typescript
function buildUrl(path: string): string {
  const isServer = typeof window === 'undefined';
  
  // If executing on the server (SSR), fetch directly inside the Docker network.
  // If executing on the browser, use relative paths to route safely via Cloudflare.
  const baseUrl = isServer 
    ? 'http://api-gateway:3000' 
    : '';

  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${baseUrl}${normalizedPath}`;
}
```

* **Server-Side:** Next.js bypasses Cloudflare entirely, calling `http://api-gateway:3000` over the internal Docker network (`al-mizan-network`), resulting in sub-millisecond API latency.
* **Client-Side:** The browser makes a relative call to `/api/v1/*`, resolving safely to `https://klodit.app/*`.

---

## 5. Automated CI/CD Pipelines

Each of the 12 repositories contains a GitHub Actions deployment workflow located in `.github/workflows/deploy.yml`.

When code is pushed to the `main` or `master` branches:

1. The GitHub runner establishes a secure SSH connection to the GCP VM.
2. The runner executes a remote pull (`git pull`) in the respective service folder.
3. It navigates to `~/al-mizan-deployments` and runs `docker compose up -d --build <service_name>` to compile and hot-swap the modified container.

### Required GitHub Secrets

To allow these workflows to run, the following secrets must be configured in your GitHub repository settings:

* `GCP_HOST`: `34.7.144.196` (The static public IP of your VM)
* `GCP_USERNAME`: `sariyanouche7_gmail_com` (Your VM SSH user)
* `GCP_SSH_KEY`: The private OpenSSH key corresponding to the authorized metadata key on the VM.
* `GCP_PASSPHRASE`: (The passphrase protecting your private key)
=======
# Al-Mizan — Guide de Déploiement & Orchestration

Ce dépôt centralise l'orchestration Docker-compose, les configurations d'infrastructure transversale et les scripts de validation de la plateforme **Al-Mizan**.

---

## 🏗️ Topologie Docker Compose

L'ensemble de la plateforme est orchestré dans un réseau virtuel Docker partagé nommé `al-mizan-network`. Le déploiement s'effectue sur une unique VM Google Cloud Platform (GCP) sous Debian 11.

### 📦 1. Conteneurs d'Infrastructure (docker-compose.infra.yml)

Ces conteneurs fournissent les couches d'accès aux données, de stockage d'objets, de cache de session et de messagerie asynchrone :

| Conteneur | Image | Port Externe | Usage dans Al-Mizan |
| :--- | :--- | :--- | :--- |
| `al-mizan-mysql` | `mysql:8` | `:3306` | Base de données relationnelle (`auth_db`, `al_mizan_users`, `document_db`, `ao_db`, `soumission_db`, `evaluation_db`, `commission_db`, `recours_db`, `notif_db`, `audit_db`) |
| `al-mizan-redis` | `redis:7-alpine` | `:6379` | Gestion des sessions JWT, limitation de débit globale et blacklist de jetons révoqués |
| `al-mizan-rabbitmq` | `rabbitmq:3-management` | `:5672`, `:15672` | Courtier de messages asynchrones (Exchange Topic: `al-mizan.events`) |
| `al-mizan-minio` | `minio/minio` | `:9000`, `:9001` | Stockage S3 sécurisé des documents et des enveloppes chiffrées |

### 🚀 2. Conteneurs Applicatifs (docker-compose.yml)

Les 11 services applicatifs sont raccordés au même réseau interne :
- `api-gateway` (Port `:3000`)
- `auth-service` (Port `:3001`)
- `users-service` (Port `:3002`)
- `appel-offres-service` (Port `:8003`)
- `soumission-service` (Port `:8004`)
- `documents-service` (Port `:8005`)
- `commission-service` (Port `:8007`)
- `evaluation-service` (Port `:8008`)
- `recours-service` (Port `:8009`)
- `notification-service` (Port `:8010`)
- `audit-service` (Port `:3009`)

---

## 📂 Provisionnement Initial de MinIO

Les 5 buckets de stockage S3 requis doivent être créés au premier démarrage :
1. `al-mizan-docs` : Justificatifs d'organisation (géré par `documents-service`).
2. `offres-techniques` : Offres techniques (PDF).
3. `offres-financieres` : Enveloppes financières chiffrées RSA-4096.
4. `cautions` : Cautions bancaires des opérateurs économiques.
5. `offres-financieres-claires` : Offres financières déchiffrées après ouverture collective des plis.

---

## 🔄 Pipeline CI/CD (GitHub Actions)

La plateforme s'appuie sur une philosophie GitOps automatisée via GitHub Actions :
- **Déclencheur** : Tout push sur la branche `main` déclenche le workflow de déploiement.
- **Mécanisme** : SSH sur la VM GCP (`appleboy/ssh-action`) -> Pull du dépôt mis à jour -> Build et relance à chaud du conteneur concerné :
  ```bash
  sudo docker-compose up -d --build <service_name>
  ```

---

## 🛠️ Astuces Techniques & Particularités (Ne pas réinitialiser)

- **Alpine Linux & Prisma** : Ajout de la bibliothèque `openssl` via `RUN apk add --no-cache openssl` dans les Dockerfiles NestJS pour prévenir les plantages du moteur Prisma Query Engine sur Alpine.
- **TypeORM Auto-Migration** : Forcer la variable `NODE_ENV=development` dans Compose pour `evaluation-service` et `commission-service` afin de déclencher l'auto-génération des tables via `synchronize: true`.
- **Bypass d'Authentification Local** : En mode `dev` (`SPRING_PROFILES_ACTIVE=dev`), `soumission-service` autorise le bypass des sessions Redis en fournissant les en-têtes `X-User-Id` et `X-User-Role`.

---

## 💻 Instructions de Lancement

1. **Créer le réseau partagé** :
   ```bash
   docker network create al-mizan-network
   ```
2. **Démarrer l'infrastructure** :
   ```bash
   docker compose -f docker-compose.infra.yml up -d
   ```
3. **Démarrer l'ensemble des microservices** :
   ```bash
   docker compose up -d
   ```
4. **Vérifier l'état de la plateforme** :
   ```bash
   docker compose ps
   ```

---

## 🎯 Validation et Exécution des Tests

Les scripts d'intégration end-to-end automatisés se trouvent dans le répertoire `Al-Mizan-Tests/` :
- `phase1.sh` à `phase8.sh` : Permettent de rejouer séquentiellement le chemin critique nominal (Golden Path) de la plateforme (Authentification, Appel d'Offres, Soumission chiffrée E2E, Déchiffrement Shamir, Notation, Recours, Notifications).
- Pour exécuter les tests :
  ```bash
  cd Al-Mizan-Tests
  ./phase1.sh
  # ...
  ```
>>>>>>> Stashed changes
