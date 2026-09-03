# Mobile Messenger

## 1. Project Overview

Mobile Messenger is a full-stack messaging application. **This repository currently contains Phase 1: the project foundation only.** It establishes a clean, production-style skeleton — a Flutter client, a Spring Boot backend, and a Docker Compose setup — that later phases will extend with authentication, messaging, invitations, media, notifications, and encryption.

The only functional feature in this phase is a backend health check that the Flutter app calls to display whether the backend (and its database connection) is reachable.

## 2. Technology Stack

### Frontend
- Flutter / Dart, Material 3
- Feature-based architecture (`core/`, `features/`, `routing/`)
- [Riverpod](https://riverpod.dev/) for state management
- [go_router](https://pub.dev/packages/go_router) for navigation
- [Dio](https://pub.dev/packages/dio) for HTTP communication

### Backend
- Java 21, Spring Boot 4
- Spring Web (MVC), Spring Data JPA
- PostgreSQL
- Maven
- Docker / Docker Compose

## 3. Project Structure

```text
mobile-messenger/
├── mobile_messenger/            # Flutter app
│   ├── lib/
│   │   ├── core/                # Config, network client, theme, shared error types
│   │   ├── features/
│   │   │   └── health/          # Backend connectivity check (data/providers/UI)
│   │   ├── routing/              # go_router configuration
│   │   ├── app.dart              # MaterialApp.router root widget
│   │   └── main.dart             # Entry point
│   ├── test/
│   └── pubspec.yaml
│
├── backend/                      # Spring Boot app
│   ├── src/main/java/com/mobilemessenger/backend/
│   │   ├── health/                # controller / service / repository for health checks
│   │   ├── config/                # CORS / web configuration
│   │   └── BackendApplication.java
│   ├── src/main/resources/application.properties
│   ├── src/test/java/...
│   ├── Dockerfile
│   └── pom.xml
│
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

## 4. Requirements

- Docker and Docker Compose (recommended path — no local PostgreSQL/Java install needed)
- For local (non-Docker) backend development: JDK 21+ and Maven (or the bundled `./mvnw`)
- For the Flutter app: Flutter SDK (stable channel)

## 5. Docker Setup

1. Copy the environment template:
   ```bash
   cp .env.example .env
   ```
2. Start PostgreSQL and the backend:
   ```bash
   docker compose up --build
   ```
   The backend waits for PostgreSQL to report healthy (via `depends_on: condition: service_healthy` plus a Hikari connection retry) before it starts serving traffic, and retries the database connection automatically if it isn't immediately ready.
3. The backend is now available at `http://localhost:8080`.

No manual installation of PostgreSQL is required — it runs entirely inside the `postgres` container, and its data persists in the `postgres_data` Docker volume.

## 6. Flutter Setup

```bash
cd mobile_messenger
flutter pub get
```

## 7. How to Start the Backend

**Via Docker (recommended):** see [Docker Setup](#5-docker-setup) above.

**Locally, without Docker** (requires a running PostgreSQL instance):
```bash
cd backend
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=mobile_messenger
export DB_USERNAME=postgres
export DB_PASSWORD=postgres
export SERVER_PORT=8080
./mvnw spring-boot:run
```

All configuration is environment-variable driven — no credentials are hardcoded. See `.env.example` for the full list.

## 8. How to Start the Flutter Application

```bash
cd mobile_messenger
flutter run
```

By default the app calls the backend at `http://localhost:8080`, except on the Android emulator, where it automatically uses `http://10.0.2.2:8080` (the emulator's alias for the host machine). Override this at any time with:

```bash
flutter run --dart-define=API_BASE_URL=http://<host>:<port>
```

On startup, the home screen calls `GET /api/health` and shows:
- a loading indicator while the check is in progress,
- **"Connected"** if the backend responds `{"status":"ok"}`,
- **"Connection failed"** with a user-friendly message and a **Retry** button otherwise (covers backend unavailable, timeouts, and unexpected responses/status codes).

## 9. How to Verify the Backend

With the backend running (Docker or local):

```bash
curl http://localhost:8080/api/health
# {"status":"ok"}
```

A `200 OK` with `{"status":"ok"}` means both the backend and its PostgreSQL connection are healthy. If the database is unreachable, the endpoint returns `503 Service Unavailable` with `{"status":"error"}` instead of crashing.

Backend tests (a `@WebMvcTest` for the health endpoint plus the Spring context load test) can be run with:
```bash
cd backend
./mvnw test
```

Flutter analysis and tests:
```bash
cd mobile_messenger
flutter analyze
flutter test
```

## 10. Current Implementation Status

**Phase 1 (this repository): Project foundation only.**

Implemented:
- Flutter app shell: Material 3 theme, go_router, Riverpod, layered API service (Dio-based), loading/connected/error UI states
- Spring Boot backend: layered `controller → service → repository` structure, environment-variable configuration, PostgreSQL + JPA wiring, `/api/health` endpoint with real database connectivity checking
- Docker Compose setup for PostgreSQL + backend, with health-checked startup ordering
- Backend and Flutter test coverage for the health-check feature

**Not implemented yet** (planned for later phases): authentication, user accounts, messaging, invitations, media uploads, push notifications, and end-to-end encryption. Do not assume any of these exist yet.
