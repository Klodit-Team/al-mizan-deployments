# Al-Mizan — Guide de Déploiement & Orchestration

Ce dépôt centralise l'orchestration Docker-compose, les configurations d'infrastructure transversale et les scripts de validation de la plateforme **Al-Mizan**.

---

## 🏗️ Topologie Docker Compose

L'ensemble de la plateforme est orchestré dans un réseau virtuel Docker partagé nommé `al-mizan-network`. Le déploiement s'effectue sur une unique VM Google Cloud Platform (GCP) sous Debian 11.

### 📦 1. Conteneurs d'Infrastructure (docker-compose.infra.yml)

Ces conteneurs fournissent les couches d'accès aux données, de stockage d'objets, de cache de session et de messagerie asynchrone :

| Conteneur           | Image                   | Port Externe      | Usage dans Al-Mizan                                                                                                                                                          |
| :------------------ | :---------------------- | :---------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `al-mizan-mysql`    | `mysql:8`               | `:3306`           | Base de données relationnelle (`auth_db`, `al_mizan_users`, `document_db`, `ao_db`, `soumission_db`, `evaluation_db`, `commission_db`, `recours_db`, `notif_db`, `audit_db`) |
| `al-mizan-redis`    | `redis:7-alpine`        | `:6379`           | Gestion des sessions JWT, limitation de débit globale et blacklist de jetons révoqués                                                                                        |
| `al-mizan-rabbitmq` | `rabbitmq:3-management` | `:5672`, `:15672` | Courtier de messages asynchrones (Exchange Topic: `al-mizan.events`)                                                                                                         |
| `al-mizan-minio`    | `minio/minio`           | `:9000`, `:9001`  | Stockage S3 sécurisé des documents et des enveloppes chiffrées                                                                                                               |

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
