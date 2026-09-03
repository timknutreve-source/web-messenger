# Mobile Messenger

## 1. Project Overview

Mobile Messenger is a full-stack messaging application. **This repository currently contains Phase 1 (project foundation) and Phase 2 (authentication).** Later phases will add profiles, messaging, invitations, media, notifications, and encryption.

Functional today:
- A backend health check the Flutter app calls to display whether the backend (and its database connection) is reachable.
- Full registration and login with JWT-based authentication, a protected `/api/auth/me` endpoint, and a Flutter app that persists the session between launches and protects its authenticated screens.

## 2. Technology Stack

### Frontend
- Flutter / Dart, Material 3
- Feature-based architecture (`core/`, `features/`, `routing/`)
- [Riverpod](https://riverpod.dev/) for state management
- [go_router](https://pub.dev/packages/go_router) for navigation, with auth-aware redirects
- [Dio](https://pub.dev/packages/dio) for HTTP communication
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) for persisting the auth token

### Backend
- Java 21, Spring Boot 4, Spring Security
- Spring Web (MVC), Spring Data JPA
- PostgreSQL, with Flyway-managed schema migrations
- JWT (jjwt) for stateless authentication, BCrypt for password hashing
- Maven
- Docker / Docker Compose

## 3. Project Structure

```text
mobile-messenger/
├── mobile_messenger/            # Flutter app
│   ├── lib/
│   │   ├── core/                # Config, network client, theme, shared error types
│   │   ├── features/
│   │   │   ├── auth/            # Registration, login, session persistence, route guarding
│   │   │   └── health/          # Backend connectivity check + authenticated home shell
│   │   ├── routing/              # go_router configuration (auth-aware redirects)
│   │   ├── app.dart               # MaterialApp.router root widget
│   │   └── main.dart              # Entry point
│   ├── test/                      # Unit + widget tests (fakes only, no real network)
│   ├── integration_test/          # Real end-to-end test against a live backend
│   └── pubspec.yaml
│
├── backend/                      # Spring Boot app
│   ├── src/main/java/com/mobilemessenger/backend/
│   │   ├── auth/                  # controller / service / DTOs / JWT / Spring Security config
│   │   ├── user/                  # User entity + repository
│   │   ├── health/                # controller / service / repository for health checks
│   │   └── common/                # Shared error response + exception handling
│   ├── src/main/resources/
│   │   ├── application.properties
│   │   └── db/migration/          # Flyway SQL migrations (schema of record)
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

1. Copy the environment template and set a real JWT secret:
   ```bash
   cp .env.example .env
   # generate one with: openssl rand -base64 48
   ```
2. Start PostgreSQL and the backend:
   ```bash
   docker compose up --build
   ```
   The backend waits for PostgreSQL to report healthy (via `depends_on: condition: service_healthy` plus a Hikari connection retry) before it starts serving traffic, and retries the database connection automatically if it isn't immediately ready. On startup it runs Flyway migrations to create/update the schema.
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
export JWT_SECRET=some-long-random-development-secret
./mvnw spring-boot:run
```

All configuration is environment-variable driven — no credentials or secrets are hardcoded. See `.env.example` for the full list. If `JWT_SECRET` is not set, the backend falls back to a clearly-marked insecure development default; **always set a real one outside local development.**

## 8. How to Start the Flutter Application

```bash
cd mobile_messenger
flutter run
```

By default the app calls the backend at `http://localhost:8080`, except on the Android emulator, where it automatically uses `http://10.0.2.2:8080` (the emulator's alias for the host machine). Override this at any time with:

```bash
flutter run --dart-define=API_BASE_URL=http://<host>:<port>
```

The app opens on a **Login** screen if no session is stored, or straight into the **home shell** if a valid session was previously saved. From Login you can register a new account; after registering or logging in, the home shell shows your username, an unverified-email notice (email verification isn't implemented yet), a **Log out** button, and the Phase 1 backend connectivity check:
- a loading indicator while the check is in progress,
- **"Connected"** if the backend responds `{"status":"ok"}`,
- **"Connection failed"** with a user-friendly message and a **Retry** button otherwise (covers backend unavailable, timeouts, and unexpected responses/status codes).

## 9. How to Verify the Backend

With the backend running (Docker or local):

```bash
curl http://localhost:8080/api/health
# {"status":"ok"}

curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com","password":"Str0ng!Pass"}'
# {"token":"...","user":{"id":"...","username":"alice","email":"alice@example.com","emailVerified":false,"createdAt":"..."}}

curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"usernameOrEmail":"alice","password":"Str0ng!Pass"}'

curl http://localhost:8080/api/auth/me -H "Authorization: Bearer <token from above>"
```

A `200 OK` with `{"status":"ok"}` on `/api/health` means both the backend and its PostgreSQL connection are healthy. If the database is unreachable, the endpoint returns `503 Service Unavailable` with `{"status":"error"}` instead of crashing.

Backend tests (health endpoint slice test, Spring context load test, and a full auth API integration test covering registration, duplicate detection, validation, login, and `/api/auth/me`) can be run with:
```bash
cd backend
./mvnw test
```

Flutter analysis and hermetic unit/widget tests (all use fakes — no real network calls):
```bash
cd mobile_messenger
flutter analyze
flutter test
```

A real end-to-end test that drives the compiled app (real HTTP, real secure storage) against a **live backend** is in `integration_test/`. It requires the backend to be running and reachable, and is not part of the default `flutter test` run:
```bash
cd mobile_messenger
flutter test integration_test/auth_flow_test.dart -d <device>
```

## 10. Current Implementation Status

**Phase 1: Project foundation.** **Phase 2: Authentication.** Both implemented in this repository.

Implemented:
- Flutter app shell: Material 3 theme, go_router with auth-aware redirects, Riverpod, layered API service (Dio-based), loading/connected/error UI states
- Registration and login screens with client-side validation (mirrored server-side), password requirements checklist, and clear error messages for validation/duplicate/credential/server/network failures
- JWT stored via `flutter_secure_storage`, restored and validated against the backend on app startup so the user stays logged in between launches
- Route protection: unauthenticated users can only reach Login/Register; authenticated users reach the home shell and are kept off Login/Register
- Spring Boot backend: layered `controller → service → repository` structure, environment-variable configuration, PostgreSQL + JPA wiring
- `/api/auth/register`, `/api/auth/login`, `/api/auth/me` with BCrypt password hashing, normalized/unique email and username (case-insensitive), strong-password validation, and stateless JWT auth via a Spring Security filter chain
- Flyway-managed database schema (no manual DDL, no `hibernate.ddl-auto=update`)
- `/api/health` endpoint with real database connectivity checking
- Docker Compose setup for PostgreSQL + backend, with health-checked startup ordering
- Backend integration tests covering registration, duplicate email/username, invalid email, weak password, login (success/wrong password/unknown user), and `/api/auth/me` (unauthenticated/authenticated). Flutter unit/widget tests covering validators, auth state transitions, route protection, and the home screen; a real end-to-end integration test against a live backend

**Logout limitation:** JWTs are stateless and are **not** revoked server-side by this phase. "Logout" means the app deletes its locally stored token and returns to the unauthenticated state — a token issued before logout remains technically valid until it expires (`JWT_EXPIRATION_MINUTES`, default 24h) if replayed directly against the API. Server-side revocation (e.g. a token blocklist) is not implemented yet.

**Not implemented yet** (planned for later phases): profile pictures/editing, user search, invitations, friends, chat, messaging, media, push notifications, and end-to-end encryption. Email verification and password reset are represented only as placeholders (`emailVerified` defaults to `false`, no email-sending infrastructure exists yet). Do not assume any of these exist yet.
