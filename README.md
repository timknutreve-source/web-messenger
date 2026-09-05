# Mobile Messenger

## 1. Project Overview

Mobile Messenger is a full-stack messaging application. **This repository currently contains Phase 1 (project foundation), Phase 2 (authentication), Phase 3 (user profile), Phase 4 (email verification & password reset), Phase 5 (contacts & chat invitations), Phase 6 (chat list & archive), Phase 7 (text messaging & real-time chat), Phase 8 (image & video attachments), and Phase 9 (application-level encryption at rest).** Later phases will add audio and push notifications.

Functional today:
- A backend health check the Flutter app calls to display whether the backend (and its database connection) is reachable.
- Full registration and login with JWT-based authentication, a protected `/api/auth/me` endpoint, and a Flutter app that persists the session between launches and protects its authenticated screens.
- A user profile: username, email, About Me, and a JPEG/PNG avatar, viewable and editable from the app, with the picture stored on the backend filesystem and referenced (not embedded) in PostgreSQL.
- Real email verification and password reset, with a genuine (configurable SMTP or safe local-log) email-sending abstraction, single-use expiring tokens, and matching Flutter screens reachable via deep link or in-app navigation.
- Contact search, chat invitations (send/accept/decline), and a persistent contacts list — see [Contacts & Chat Invitations](#13-contacts--chat-invitations) below.
- A per-user chat list with archive/unarchive, and real-time text messaging over WebSocket/STOMP with sent/delivered/read status, edit, delete, and typing indicators — see [Chat List & Archive](#14-chat-list--archive-phase-6) and [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7) below.
- Image and video attachments on messages (with or without accompanying text), with server-side validation/thumbnails and range-request video streaming — see [Image & Video Attachments](#16-image--video-attachments-phase-8) below.
- Message text, profile "About Me", and uploaded media are encrypted at rest with AES-256-GCM before they ever reach PostgreSQL or disk — see [Encryption](#17-encryption-phase-9) below.

## 2. Technology Stack

### Frontend
- Flutter / Dart, Material 3
- Feature-based architecture (`core/`, `features/`, `routing/`)
- [Riverpod](https://riverpod.dev/) for state management
- [go_router](https://pub.dev/packages/go_router) for navigation, with auth-aware redirects and deep-link routes
- [Dio](https://pub.dev/packages/dio) for HTTP communication
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) for persisting the auth token
- [image_picker](https://pub.dev/packages/image_picker) for selecting a profile picture from the device, and (Phase 8) chat image/video attachments from the gallery or camera
- [stomp_dart_client](https://pub.dev/packages/stomp_dart_client) for the real-time chat WebSocket/STOMP connection (see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7))
- [video_player](https://pub.dev/packages/video_player) (Flutter's official plugin) for chat video playback (see [Image & Video Attachments](#16-image--video-attachments-phase-8))

### Backend
- Java 21, Spring Boot 4, Spring Security
- Spring Web (MVC), Spring Data JPA
- Spring WebSocket (STOMP over WebSocket) for real-time chat events (see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7))
- PostgreSQL, with Flyway-managed schema migrations
- JWT (jjwt) for stateless authentication, BCrypt for password hashing
- Spring Mail (`spring-boot-starter-mail` / `JavaMailSender`) for real SMTP email delivery, behind a small provider-agnostic `EmailService` abstraction (see [Email Verification & Password Reset](#12-email-verification--password-reset) below)
- A small filesystem-backed file storage abstraction for uploaded avatars (see [Profile Feature](#11-profile-feature) below), encrypted at rest as of Phase 9
- AES-256-GCM application-level encryption via the JDK's own JCA/JCE (`javax.crypto`) — no third-party crypto library added (see [Encryption](#17-encryption-phase-9) below)
- Maven
- Docker / Docker Compose

## 3. Project Structure

```text
mobile-messenger/
├── mobile_messenger/            # Flutter app
│   ├── lib/
│   │   ├── core/                # Config, network client, theme, shared error types
│   │   ├── features/
│   │   │   ├── auth/            # Registration, login, verification, password reset, session, route guarding
│   │   │   ├── profile/         # View/edit profile, avatar upload
│   │   │   ├── contact/         # Contact search, invitations, contacts list
│   │   │   ├── chat/            # Chat list, archive, conversation screen, messages, WebSocket client
│   │   │   └── health/          # Backend connectivity check + authenticated home shell
│   │   ├── routing/              # go_router configuration (auth-aware redirects, deep links)
│   │   ├── app.dart               # MaterialApp.router root widget
│   │   └── main.dart              # Entry point
│   ├── android/                   # Android project (custom URL scheme deep-link intent-filter)
│   ├── test/                      # Unit + widget tests (fakes only, no real network)
│   ├── integration_test/          # Real end-to-end test against a live backend
│   └── pubspec.yaml
│
├── backend/                      # Spring Boot app
│   ├── src/main/java/com/mobilemessenger/backend/
│   │   ├── auth/                  # controller / service / DTOs / JWT / Spring Security config
│   │   │   └── token/              # Email-verification & password-reset token entities/repos/generator
│   │   ├── email/                  # EmailService abstraction (SMTP + local-log implementations)
│   │   ├── user/                  # User entity + repository + shared safe-view DTO
│   │   ├── profile/                # controller / service / DTOs for viewing/editing the profile
│   │   ├── contact/                 # Contact search, invitations, contacts (entities/services/controllers/DTOs)
│   │   ├── chat/                    # Conversations, chat list/archive, messages, WebSocket/STOMP config
│   │   ├── storage/                 # Generic file storage abstraction (avatars today; chat media later)
│   │   ├── health/                # controller / service / repository for health checks
│   │   └── common/                # Shared error/message response + exception handling
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
- For an Android build: the Android SDK/toolchain (`flutter doctor` should show it as ✓)
- Real SMTP credentials are **only** needed if you want to send real emails (`EMAIL_PROVIDER=smtp`) — everything works, and is fully testable, without them (see below)

## 5. Docker Setup

1. Copy the environment template and set a real JWT secret and encryption key:
   ```bash
   cp .env.example .env
   # JWT_SECRET: generate one with: openssl rand -base64 48
   # ENCRYPTION_MASTER_KEY: generate one with: openssl rand -base64 32
   ```
   Both are **required** — `docker compose up` refuses to start the backend if either is left at its placeholder value (see [Encryption](#17-encryption-phase-9) below for what `ENCRYPTION_MASTER_KEY` protects and exactly what format it must be).
2. Start PostgreSQL and the backend:
   ```bash
   docker compose up --build
   ```
   The backend waits for PostgreSQL to report healthy (via `depends_on: condition: service_healthy` plus a Hikari connection retry) before it starts serving traffic, and retries the database connection automatically if it isn't immediately ready. On startup it runs Flyway migrations to create/update the schema.
3. The backend is now available at `http://localhost:8080`.

No manual installation of PostgreSQL is required — it runs entirely inside the `postgres` container, and its data persists in the `postgres_data` Docker volume. Uploaded profile pictures persist in the `profile_storage` Docker volume, mounted at `/app/storage` inside the backend container — both volumes survive `docker compose down` / container recreation (only `docker compose down -v` removes them).

By default `EMAIL_PROVIDER` is `log`, so Compose works out of the box without any SMTP setup — verification/reset links are printed to `docker compose logs backend` instead of emailed. Set `EMAIL_PROVIDER=smtp` plus the `SMTP_*` variables in `.env` to send real email instead.

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
export ENCRYPTION_MASTER_KEY=$(openssl rand -base64 32)
./mvnw spring-boot:run
```

All configuration is environment-variable driven — no credentials or secrets are hardcoded. See `.env.example` for the full list. If `JWT_SECRET` or `ENCRYPTION_MASTER_KEY` is not set, the backend falls back to a clearly-marked insecure development default (a fixed, publicly-committed value); **always set real ones outside local development.** Unlike `JWT_SECRET`, `ENCRYPTION_MASTER_KEY` is validated strictly at startup — the app refuses to start if it's missing, isn't valid Base64, or doesn't decode to exactly 32 bytes (see [Encryption](#17-encryption-phase-9)). Uploaded avatars are written under `./data/storage` by default when run this way (override with `STORAGE_ROOT_DIR`). Email defaults to `EMAIL_PROVIDER=log` (see [Email Verification & Password Reset](#12-email-verification--password-reset)).

### How to start PostgreSQL (without Docker)

If you don't want to use Docker Compose, install PostgreSQL locally (e.g. `apt install postgresql`), then create a database matching your `DB_*` environment variables:
```bash
sudo -u postgres createdb mobile_messenger
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
```
The backend creates/updates all tables itself via Flyway on startup — no manual schema setup is needed beyond having an empty database to connect to.

## 8. How to Start the Flutter Application

```bash
cd mobile_messenger
flutter run
```

By default the app calls the backend at `http://localhost:8080`, except on the Android emulator, where it automatically uses `http://10.0.2.2:8080` (the emulator's alias for the host machine). Override this at any time with:

```bash
flutter run --dart-define=API_BASE_URL=http://<host>:<port>
```

The app opens on a **Login** screen if no session is stored, or straight into the **home shell** if a valid session was previously saved. From Login you can register a new account or tap **Forgot password?**; after registering or logging in, the home shell shows your username, an unverified-email notice with a **resend** action if applicable, a profile icon (tap to open your **Profile**), a **Log out** button, and the Phase 1 backend connectivity check:
- a loading indicator while the check is in progress,
- **"Connected"** if the backend responds `{"status":"ok"}`,
- **"Connection failed"** with a user-friendly message and a **Retry** button otherwise (covers backend unavailable, timeouts, and unexpected responses/status codes).

## 9. How to Run Tests

Backend tests (health, auth, profile, email verification, password reset, and contacts/invitations integration tests — see [Testing](#18-testing) below) run against a real PostgreSQL database:
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

A real end-to-end test that drives the compiled app (real HTTP, real secure storage, real file upload) against a **live backend** is in `integration_test/`. It requires the backend to be running and reachable, and is not part of the default `flutter test` run:
```bash
cd mobile_messenger
flutter test integration_test/auth_flow_test.dart -d <device>
```

## 10. How to Build the Android APK

With a working Android SDK (`flutter doctor` shows the Android toolchain as ✓):
```bash
cd mobile_messenger
flutter build apk --release
```
The APK is written to `mobile_messenger/build/app/outputs/flutter-apk/app-release.apk`. Since the app defaults to `http://localhost:8080` (or `http://10.0.2.2:8080` on the emulator), install it on a real device only if that device can reach your backend's address — otherwise pass the right host at build/run time:
```bash
flutter build apk --release --dart-define=API_BASE_URL=http://<your-backend-host>:8080
```

> **Note:** `flutter_secure_storage` currently requires compiling against Android SDK 37. If your local Android SDK only has platform 37 installed under a versioned folder name (e.g. `android-37.0` instead of the plain `android-37` Gradle looks for), create a symlink: `ln -s $ANDROID_HOME/platforms/android-37.0 $ANDROID_HOME/platforms/android-37`. This was needed in the environment this project was built in; a normal `sdkmanager "platforms;android-37"` install may not hit it.

## 11. Profile Feature

Every account has a profile: **username**, **email**, an optional **About Me** (up to 500 characters), and a **profile picture**.

- **Viewing**: tap the profile icon in the home screen's app bar to open your Profile screen (avatar, username, email, About Me).
- **Editing**: tap **Edit Profile** to change username, email, and About Me, and/or replace the profile picture. Changing your email automatically resets `emailVerified` to `false` (see [Email Verification & Password Reset](#12-email-verification--password-reset)).
- **Default avatar**: a brand-new account has no avatar file at all (`avatarFileName` is `null`) — the app renders a bundled Material icon in its place, so there is never a broken-image state and nothing is stored per-user until they actually upload a photo.
- **Supported formats**: JPEG and PNG only. The backend inspects the actual file bytes (not just the extension or the client-supplied `Content-Type`) to confirm the format, so a renamed non-image file is rejected.
- **Maximum size**: 5MB. Enforced both by the server's multipart upload limit and again explicitly in the profile service, and mirrored client-side in the picker flow for immediate feedback before any upload is attempted.
- **Storage**: uploaded images are saved to the backend's filesystem under a configurable root directory (`storage.root-dir` / `STORAGE_ROOT_DIR`, `/app/storage` in Docker, backed by the `profile_storage` volume). PostgreSQL stores only the generated file name, never the image bytes — see [Avatar Storage Approach](#avatar-storage-approach) below. Replacing an avatar deletes the previous file.
- **Access**: `GET /api/profile/avatar/{fileName}` requires authentication (any signed-in user, not just the owner — avatars aren't sensitive, and later phases need users to see each other's), and file names are unguessable, server-generated UUIDs — the endpoint never accepts or trusts a client-supplied path.

### Avatar Storage Approach

`storage.FileStorageService` is a small, generic interface (`store` / `load` / `exists` / `delete`, grouped by a `category` string like `"avatars"`) implemented today by `LocalFileStorageService`, which writes to a configurable local directory. It's intentionally not avatar-specific — the same interface is meant to back **chat images, videos, and audio** in later phases without redesign, just with a new `category`. File names are always server-generated (`UUID.randomUUID()` + a format-detected extension), never derived from the client-supplied file name, and every read/write is path-validated to stay inside the configured root directory (rejecting any `..`/`/`/`\` in a requested name) to prevent path traversal.

## 12. Email Verification & Password Reset

### How it works

- **On registration**, the backend generates a single-use verification token, stores only its SHA-256 hash (never the raw token), and emails a link containing the raw token: `<FRONTEND_BASE_URL>/verify-email?token=...`.
- **Logging in does not require a verified email** — verification and login are intentionally decoupled (see *Design decision* below). The home screen shows a banner with a **Resend verification email** action while `emailVerified` is `false`.
- Opening the verification link (`POST /api/auth/verify-email`) marks the account verified, and the token is immediately consumed - reusing it, or using an expired (24h) or unknown token, always returns the same generic "invalid or expired" error.
- **Forgot password** (`POST /api/auth/forgot-password`) always returns the same generic message ("If that email is registered...") whether or not the address exists, and only actually sends an email for a real account - so the endpoint never reveals account existence.
- The reset email links to `<FRONTEND_BASE_URL>/reset-password?token=...`; `POST /api/auth/reset-password` validates the token (unused, unexpired, 1h TTL), re-validates the new password server-side with the same strong-password rule as registration, and updates the BCrypt hash. The token is single-use and immediately consumed.
- Requesting a new verification or reset email invalidates any previous unused token of that kind for the account.

### Design decision: login is not gated on verification

The mandatory requirements describe the verification *mechanics* (token generation, expiry, single-use, resend) but don't mandate blocking login for unverified accounts. Blocking login was deliberately **not** implemented, for two reasons:
1. **Not breaking existing users.** Every account created during Phases 1–3 has `emailVerified=false` and no verification token (verification didn't exist yet) - gating login on verification would have permanently locked all of them out.
2. **Reasonable UX.** Many real apps let you use the app immediately and verify at your own pace, showing a persistent reminder instead of a hard block. That's what's implemented here: the unverified banner + resend action stays visible on the home screen until the account is verified.

If a hard login gate is desired later, it's a small, isolated change to `AuthService.login()`.

### Email sending: `EmailService`

`email.EmailService` is a two-method interface (`sendVerificationEmail`, `sendPasswordResetEmail`) with two implementations, selected by `EMAIL_PROVIDER`:
- **`log`** (default) — `LoggingEmailService` logs the generated link at INFO level instead of sending anything. Safe for local development and for reviewers without SMTP credentials; grep the backend's console output (or `docker compose logs backend`) for `[DEV EMAIL` to find the link.
- **`smtp`** — `SmtpEmailService` sends a real email via `JavaMailSender`/SMTP, configured entirely through environment variables (see below). It deliberately never logs the link/token itself, only that a message was sent and to which masked address, so a live token can never leak into production logs.

Registration/resend/forgot-password never fail just because the email provider is temporarily unreachable - the token is still created (and can be resent later); the send failure is only logged as a warning.

### SMTP configuration (`.env` / environment variables)

| Variable | Purpose | Default |
|---|---|---|
| `EMAIL_PROVIDER` | `log` or `smtp` | `log` |
| `SMTP_HOST` | SMTP server host | `localhost` |
| `SMTP_PORT` | SMTP server port | `587` |
| `SMTP_USERNAME` | SMTP auth username | *(empty)* |
| `SMTP_PASSWORD` | SMTP auth password | *(empty)* |
| `SMTP_FROM_EMAIL` | `From:` address on sent emails | `no-reply@example.com` |
| `SMTP_AUTH` | Whether to authenticate with the SMTP server | `true` |
| `SMTP_STARTTLS` | Whether to use STARTTLS if offered | `true` |
| `FRONTEND_BASE_URL` | Base URL embedded in email links | `mobilemessenger://` |

None of these are hardcoded anywhere in source; see `.env.example` and `application.properties`.

### Email links & Android deep linking

Links use the app's own custom URL scheme by default: `mobilemessenger://verify-email?token=...` and `mobilemessenger://reset-password?token=...` (written with a third slash - `mobilemessenger:///verify-email?...` - so the URI parses with an empty host and `/verify-email` as the path, matching go_router's route directly). `FRONTEND_BASE_URL` can instead point at a real HTTPS domain later (e.g. for proper Android App Links) with no backend code change.

On Android, `AndroidManifest.xml` declares a `VIEW`/`BROWSABLE` intent-filter for the `mobilemessenger` scheme (no host/path restriction - go_router matches the specific path once inside the app). `go_router` routes `/verify-email` and `/reset-password` read the `token` query parameter directly from the incoming URI.

## 13. Contacts & Chat Invitations

Users find each other, send a chat invitation, and become **contacts** once the invitation is accepted, which also creates a conversation for them — see [Chat List & Archive](#14-chat-list--archive-phase-6) below. Actual message sending is a later phase.

### Data model

- **`ContactInvitation`**: `id`, `senderId`, `recipientId`, `status` (`PENDING` / `ACCEPTED` / `DECLINED`), `createdAt`, `respondedAt` (set when accepted/declined).
- **`Contact`**: `id`, `userId`, `contactId`, `createdAt`. An accepted invitation between A and B creates **two** `Contact` rows — `(A, B)` and `(B, A)` — one per direction, so "list my contacts" is a single indexed lookup by `userId` rather than an `OR`-based query across two columns.

### Database (`V4__add_contacts_and_invitations.sql`)

Added without touching `V1`–`V3`; `ddl-auto=validate` is unchanged — Flyway remains the sole schema authority.
- `contact_invitations`: `sender_id`/`recipient_id` both `REFERENCES users(id) ON DELETE CASCADE` (deleting a user cannot leave a dangling invitation), a `CHECK (sender_id <> recipient_id)` constraint, an index on `(recipient_id, status)` for the pending-list query, and a **partial unique index** `ON (sender_id, recipient_id) WHERE status = 'PENDING'` — at most one active pending invitation per direction, while a past accepted/declined invitation never blocks a fresh one (e.g. re-inviting after a decline).
- `contacts`: `user_id`/`contact_id` both cascade-deleting the same way, a `CHECK (user_id <> contact_id)` constraint, a unique index on `(user_id, contact_id)`, and an index on `user_id` for listing.

### API endpoints

All require a valid JWT (`Authorization: Bearer <token>`); the acting user's identity always comes from the token, never from the request body/path.

| Method & path | Purpose |
|---|---|
| `GET /api/contacts/search?q=...` | Case-insensitive partial match on username or email, excluding yourself. `q` must be at least 2 characters (`400` otherwise). Returns up to 20 safe `{id, username, email, avatarFileName}` results. |
| `GET /api/contacts` | Lists your accepted contacts (`{user: {...}, since}`), most recent first. |
| `POST /api/contacts/invitations` | Body `{"recipientId": "<uuid>"}`. Sends an invitation. Rejects self-invites (`400`), a duplicate pending invitation (`409`), and inviting someone you're already a contact of (`409`). |
| `GET /api/contacts/invitations/pending` | Lists your incoming pending invitations (`{id, sender: {...}, createdAt}`). |
| `POST /api/contacts/invitations/{id}/accept` | Only the recipient may accept; the invitation must still be `PENDING` (`403`/`409` otherwise). Marks it `ACCEPTED` and creates the mutual `Contact` rows in one transaction. |
| `POST /api/contacts/invitations/{id}/decline` | Same ownership/status rules as accept; marks it `DECLINED`. |

### Reverse-direction invitations (design decision)

If B sends an invitation to A while A → B is still pending, the new B → A request is treated as **accepting the existing A → B invitation** instead of creating a second, conflicting one — two people inviting each other at roughly the same time become contacts immediately, matching what a user would actually expect, rather than surfacing a confusing duplicate-invitation error or leaving two independently pending invitations in place. See the Javadoc on `ContactInvitationService.sendInvitation()`.

### Security / IDOR prevention

Every endpoint resolves the acting user from `Authentication.getPrincipal()` (the JWT subject), never from client-supplied data. `acceptInvitation`/`declineInvitation` load the invitation, then explicitly check `invitation.recipientId == actingUserId` before allowing any state change — verified with integration tests where the original sender and an unrelated third party are both correctly rejected (`403`) when attempting to accept/decline someone else's invitation.

### Flutter

`features/contact/` follows the same `domain` / `data` / `presentation` split as `auth`/`profile`, with `contact_providers.dart` holding three `AsyncNotifier`s (`ContactsController`, `PendingInvitationsController`, `ContactSearchController`) and reusing the existing `AppException`/`presentError` error-handling architecture — no second error system.

The **Contacts** screen (reachable from a new icon in the home screen's app bar, protected by the same auth-aware router redirect as every other authenticated route) has three tabs:
- **Contacts** — your accepted contacts (avatar, username, email).
- **Requests** — incoming pending invitations, with **Accept**/**Decline** buttons, per-row loading state, and inline error feedback if a request fails; accepting removes it from the list and refreshes the contacts tab, declining just removes it.
- **Find People** — a search field plus results with a **Send invitation** action per row; a successful send replaces the button with an "Invitation sent" label, a failure shows an inline error without losing the result row.

## 14. Chat List & Archive (Phase 6)

Every pair of accepted contacts now has a persistent **conversation**. There is still no messaging in this phase — no message entity, no send/receive, no real-time transport — Phase 6 only builds the chat-list foundation (list, sort, archive, unarchive) that Phase 7 will attach actual messages to.

### Data model

- **`Conversation`**: `id` (UUID), `createdAt`, `lastActivityAt`, plus `directUserAId`/`directUserBId` — the two participants of a **direct** (1:1) conversation, stored directly on the conversation as an *ordered* pair (`directUserAId < directUserBId` per PostgreSQL's own byte-wise `uuid` ordering). Storing the pair this way, instead of only as two participant rows, lets a single partial unique index guarantee "at most one direct conversation per unordered pair of users" at the database level.
- **`ConversationParticipant`**: `id`, `conversationId`, `userId`, `archived`, `archivedAt`, `joinedAt` — one row per (conversation, user). **Archive state lives here, per participant, not on `Conversation`** — Alice archiving her copy of a chat with Bob never touches Bob's row for the same conversation.

`Conversation` also exposes `otherUserId(userId)` and a `touchActivity(Instant)` method; the latter is unused in Phase 6 (there are no messages yet to bump activity) but exists because Phase 7 will call it every time a message is sent.

**A subtle bug found and fixed during implementation**: Java's `UUID.compareTo()` compares the two 64-bit halves as *signed* longs, while PostgreSQL's `uuid` type comparison is byte-wise (effectively unsigned). For some UUID pairs the two disagree on which value is "lower", which broke the `direct_user_a_id < direct_user_b_id` database CHECK constraint when the ordering was computed with `UUID.compareTo()`. The fix (`ChatService.getOrCreateDirectConversation`) orders by the UUIDs' canonical **string** form instead, which matches PostgreSQL's ordering (hex-digit ASCII order tracks unsigned big-endian byte order). Caught by the integration test suite, not by inspection — a good example of why the tests in this phase run against a real Postgres rather than mocks.

### Database (`V5__add_conversations.sql`)

Added without touching `V1`–`V4`; `ddl-auto=validate` is unchanged.
- `conversations`: `direct_user_a_id`/`direct_user_b_id` both nullable `UUID REFERENCES users(id) ON DELETE CASCADE`, a `CHECK` enforcing the ordered pair, and a **partial unique index** on `(direct_user_a_id, direct_user_b_id) WHERE both NOT NULL` — the database itself refuses a second direct conversation between the same two users.
- `conversation_participants`: a unique index on `(conversation_id, user_id)` (no duplicate membership) and an index on `(user_id, archived)` (the chat-list query).
- **Backfill**: the migration also backfills a conversation (and both participant rows) for every pre-existing Phase 5 `contacts` pair that doesn't have one yet, so contacts created before this migration ran still show up in the chat list. This runs once, as part of the same Flyway migration, guarded by `NOT EXISTS` so it's safe even if re-examined.

### Conversation creation

`ChatService.getOrCreateDirectConversation(userIdA, userIdB)` is called from `ContactInvitationService.acceptInvitation()`, in the **same transaction** as `createMutualContact(...)` — accepting an invitation always ends up with both a contact relationship and a conversation, or (if anything fails) neither. The method is idempotent: it looks up the existing conversation for the ordered pair first, and only creates one if none exists, so calling it twice for the same two users never creates a duplicate (backed by the database's own unique index as a second layer of protection).

### API endpoints

All require a valid JWT; the acting user always comes from the token.

| Method & path | Purpose |
|---|---|
| `GET /api/chats` | The caller's non-archived chats, sorted by `lastActivityAt` **descending** (newest activity first) — sorting is done in the service layer, not left to the Flutter client. |
| `GET /api/chats/archived` | The caller's archived chats, same sort order. |
| `POST /api/chats/{chatId}/archive` | Archives the caller's own participant row only. Idempotent — archiving an already-archived chat just returns its current state. |
| `POST /api/chats/{chatId}/unarchive` | Restores the caller's own participant row only. Also idempotent. |

Each chat is returned as `{id, otherUser: {id, username, email, avatarFileName}, lastActivityAt, archived}` — `otherUser` reuses the existing `ContactUserSummary` DTO rather than introducing a near-identical duplicate.

### Security / IDOR prevention

Archive/unarchive/list all resolve the acting user from the JWT, never from the request. Looking up a conversation for archive/unarchive goes through the caller's **own** `ConversationParticipant` row (`findByConversationIdAndUserId`) — if the caller isn't a participant of that conversation, this lookup simply finds nothing and returns the same generic `404 Chat not found` as a conversation ID that doesn't exist at all. This means the API never reveals whether a given (inaccessible) chat ID exists. Verified with integration tests: an unrelated third party gets `404` attempting to archive/unarchive someone else's chat, and archiving/unarchiving never affects the other participant's own state.

### Flutter

`features/chat/` follows the same `domain`/`data`/`presentation` split as `contact`/`profile`, with `chat_providers.dart` holding two `AsyncNotifier`s (`ChatsController`, `ArchivedChatsController`) built on the same `AppException`/`presentError` error handling as every other feature.

- **Chats screen** (new "Chats" icon in the home app bar, first in the list) shows active chats — avatar, username, and "No messages yet" (no fake last-message text, since there are no messages yet) — with an inline **Archive** action per row, loading/empty/error states, and a link to the Archived screen.
- **Archived Chats screen** shows archived chats with an inline **Unarchive** action, and its own loading/empty/error states.
- Archiving/unarchiving optimistically removes the item from its current list on success and invalidates the other list, so a chat that moves from active to archived (or back) shows up correctly without a manual refresh.
- Tapping a chat row navigates to `/chats/:chatId` — see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7) below for what that screen does starting in Phase 7. Both `/chats` routes are protected by the same auth-aware router redirect as every other authenticated route.

## 15. Text Messaging & Real-Time Chat (Phase 7)

Conversations now carry real text messages, sent and received live over WebSocket/STOMP, with sent/delivered/read status, edit, delete, and typing indicators. Images/video are Phase 8, end-to-end/at-rest encryption is Phase 9, audio and push notifications are Phase 10 — none of that is implemented here.

### Data model

**`Message`**: `id`, `conversationId`, `senderId`, `content`, `status` (`SENT` / `DELIVERED` / `READ`), `createdAt`, `editedAt`, `deletedAt`. Deletion is soft: `deletedAt` is set and `content` is cleared in the same update, so a deleted message keeps its row (its position and timestamp are preserved in history) but its original text can never be read back from the database or re-sent to a client — the `MessageResponse` DTO returns `content: null` and `deleted: true` for it regardless of what's stored.

`status` is a deliberately simple three-state application-level field, not a mirror of any WebSocket transport acknowledgement — the two are explicitly kept separate (see below).

### Database (`V6__add_messages.sql`)

Added without touching `V1`–`V5`; `ddl-auto=validate` is unchanged.
- `messages.conversation_id`/`sender_id` both `REFERENCES ... ON DELETE CASCADE`.
- `messages_conversation_created_idx` on `(conversation_id, created_at DESC, id DESC)` — supports both "messages for a conversation, newest first" and, combined with a `(created_at, id)` cursor, stable keyset pagination for older pages.
- `messages_sender_idx` on `sender_id`.
- `messages_conversation_status_idx` on `(conversation_id, status)` — supports the bulk "mark conversation read" query (every message in the conversation not sent by the caller and not already `READ`).

### Pagination

`GET /api/chats/{chatId}/messages?before={messageId}&limit={n}` uses **keyset (cursor) pagination**, not offset-based paging, so it stays correct and fast regardless of how long a conversation gets: the first call (no `before`) returns the most recent `limit` messages (default 50, capped at 100); passing the oldest message's `id` from that page as `before` returns the next-older page. Cursoring by `(createdAt, id)` rather than `createdAt` alone keeps ordering stable even when two messages share a timestamp. Every page is returned to the client already in chronological (oldest-first) order, ready to render; the response also carries `hasMore` so the client knows whether to offer "load older messages" (triggered in the Flutter app by scrolling near the top of the list).

### API endpoints

All require a valid JWT; the acting user always comes from the token, and every endpoint first verifies the caller is a participant of `{chatId}` (same `404 Chat not found` for "doesn't exist" and "not yours" as Phase 6 — never leaks which is which).

| Method & path | Purpose |
|---|---|
| `GET /api/chats/{chatId}/messages` | Loads a page of messages (see pagination above). |
| `POST /api/chats/{chatId}/messages` | Body `{"content": "..."}`. Persists the message, bumps the conversation's `lastActivityAt` (so the chat list re-sorts), returns the message, and broadcasts a `NEW_MESSAGE` WebSocket event. Blank or >4000-character content is rejected (`400`). |
| `PUT /api/chats/{chatId}/messages/{messageId}` | Only the sender may edit; rejects a deleted message (`409`). Broadcasts `MESSAGE_UPDATED`. |
| `DELETE /api/chats/{chatId}/messages/{messageId}` | Only the sender may delete (soft-delete, idempotent). Broadcasts `MESSAGE_DELETED` (just the id — never the content). |
| `POST /api/chats/{chatId}/messages/read` | Bulk-marks every message from the *other* participant as `READ` (called when the recipient opens the conversation). Broadcasts one `MESSAGES_READ` event listing the changed ids. |
| `POST /api/chats/{chatId}/messages/{messageId}/delivered` | Only a non-sender participant may acknowledge delivery; `SENT → DELIVERED` (no-op otherwise). Broadcasts `MESSAGE_STATUS_UPDATED`. |

**Design decision — delivered/read as REST, not STOMP SEND frames:** the spec's suggested flow describes the recipient's client acknowledging receipt after getting the WebSocket push, but doesn't mandate *how* that acknowledgement travels. Both status transitions are implemented as ordinary authenticated REST calls (mirroring Phase 6's archive/unarchive pattern) — simpler, directly testable with the same MockMvc-based integration tests as everything else in this codebase, and still fully real-time from the *other* party's point of view, since the resulting status change is broadcast over the existing WebSocket topic immediately. WebSocket is reserved for genuinely push-only concerns: new/updated/deleted message events, status-change notifications, and typing.

### WebSocket / STOMP architecture

- **Endpoint**: `/ws` (STOMP over a raw WebSocket — no SockJS fallback, since this is a native mobile client, not a browser).
- **Broker destinations**: clients subscribe to `/topic/chats/{chatId}` for that conversation's events; typing events are sent to the application destination `/app/chats/{chatId}/typing`.
- **Event envelope**: every broadcast on `/topic/chats/{chatId}` is `{"type": "...", "payload": {...}}` — `NEW_MESSAGE`/`MESSAGE_UPDATED`/`MESSAGE_STATUS_UPDATED` carry a full `MessageResponse`, `MESSAGE_DELETED` carries `{messageId}`, `MESSAGES_READ` carries `{messageIds: [...]}`, and `TYPING_STARTED`/`TYPING_STOPPED` carry `{userId, username}`.

**Authentication** — reuses the existing JWT with no second login system and no token inside a STOMP frame: the WebSocket handshake is itself an ordinary HTTP `GET` request that passes through the same Spring Security filter chain (and the same `JwtAuthenticationFilter`) as every REST call, so the Flutter client sends `Authorization: Bearer <token>` as a plain HTTP header on the handshake (supported by `stomp_dart_client`'s `webSocketConnectHeaders`, since — unlike browser JavaScript's `WebSocket` API — a native Dart/Android WebSocket client can set arbitrary handshake headers). `/ws` is not in `SecurityConfig`'s `permitAll` list, so it's covered by the same `anyRequest().authenticated()` rule as everything else: an unauthenticated handshake is rejected before the upgrade even happens. `AuthHandshakeInterceptor` copies the resulting `Authentication` into the WebSocket session (via a custom `HandshakeHandler`) so it's available as the STOMP session's `Principal` for the lifetime of the connection.

**Per-conversation subscription authorization** — Spring's simple broker has no concept of "this destination is private," so `ChatSubscriptionInterceptor` (a `ChannelInterceptor` on the inbound channel) explicitly checks, on every `SUBSCRIBE` to a `/topic/chats/{chatId}` destination, that the authenticated session's user is actually a participant of that conversation, rejecting the subscription otherwise. Typing events go through the same participant check inside `ChatWebSocketController`, and the sender's identity for a typing event always comes from the authenticated STOMP session — never from the client's payload (`TypingRequest` only carries a `started` boolean; there's no field to spoof).

### Typing indicators

`TYPING_STARTED`/`TYPING_STOPPED` are pure WebSocket events and are **never** persisted as messages or stored anywhere — verified directly in `ChatWebSocketIntegrationTest` (a typing event that arrives leaves the `messages` table untouched). The Flutter composer debounces: typing sends `TYPING_STARTED` once per burst of keystrokes, then `TYPING_STOPPED` automatically after 3 seconds of no further input (or immediately when the message is sent or the field is cleared). The receiving side auto-clears its "X is typing…" indicator 5 seconds after the last `TYPING_STARTED` even if `TYPING_STOPPED` never arrives (e.g. the typing user's connection drops) — so it can never get stuck showing forever.

### Message status flow

`SENT` the instant a message is persisted → `DELIVERED` when the recipient's client explicitly acknowledges it (`POST .../delivered`) → `READ` when the recipient opens the conversation (`POST .../read`, called automatically by the Flutter chat screen on load and whenever a new message arrives while it's open). A reconnecting client never loses state: message content and status are only ever read from the persisted REST data (`GET .../messages`), so a client that missed WebSocket events while offline simply sees the correct up-to-date status on its next load — nothing depends on having received every live event.

### Chat-list integration

Sending a message calls `Conversation.touchActivity(message.createdAt)` in the same transaction as persisting it, so `lastActivityAt` (and therefore the Phase 6 chat list's sort order) updates immediately. `ChatSummaryResponse` (Phase 6's DTO) gained a `lastMessage` field (`MessagePreviewResponse`: id, content, senderId, createdAt, deleted) populated from the conversation's most recent message, if any — the Flutter Chats screen now shows the real last message text (or "This message was deleted") instead of the Phase 6 placeholder "No messages yet". Archive/unarchive behavior is unchanged.

### Security / IDOR protection

Every message operation re-derives the acting user from the JWT and re-validates conversation membership server-side — never from client-supplied ids. Edit/delete additionally verify the message actually belongs to the given conversation (`findByIdAndConversationId`) and that the caller is its sender (`403` otherwise, distinct from the `404` a non-participant gets, since the message's existence isn't private information from a legitimate participant's point of view). Delivery acknowledgement rejects the sender acknowledging their own message (`400`). WebSocket subscription authorization is covered above. Verified with integration tests: a non-participant gets `404` sending/loading/editing/deleting/marking-read in someone else's conversation and cannot subscribe to or receive events from its WebSocket topic; the original sender/an unrelated user get `403` editing or deleting someone else's message; a sender gets `400` acknowledging delivery of their own message.

### Flutter

Extends `features/chat/` with `data/message_api.dart` (REST), `data/chat_websocket_client.dart` (a thin wrapper around the `stomp_dart_client` package), `domain/message.dart` / `message_page.dart` / `chat_event.dart`, and `chat_room_providers.dart` (`ChatRoomController`, an `AsyncNotifier` scoped per conversation via `.autoDispose.family` — so its WebSocket connection is opened when the chat screen mounts and torn down automatically when it's popped).

- **Chat screen** (`ChatScreen`, replacing the Phase 6 placeholder at `/chats/:chatId`): message list (oldest to newest, auto-loads an older page when scrolled near the top), a composer with a send button, per-message status icon (sent/delivered/read, or a spinner while sending), a typing indicator line, and a long-press menu for **Edit**/**Delete** on the current user's own messages only.
- **Outgoing message states**: a sent message appears immediately (optimistic, spinner) before the server confirms it; on success it's replaced with the confirmed message (status icon); on failure it's marked **Failed** with a tap-to-retry action — a failed send is never silently dropped or shown as if it succeeded.
- **Edit**: a simple dialog; a successfully edited message shows `(edited)` next to its timestamp.
- **Delete**: a confirmation dialog; a deleted message renders as the neutral "This message was deleted" placeholder, with its original content never shown again (matching the backend, which never sends it back either).
- **Typing**: every composer keystroke goes through `ChatRoomController.onComposerChanged`, which debounces the `TYPING_STARTED`/`TYPING_STOPPED` sends; the other participant's typing status renders as "*username* is typing…" and clears itself automatically.
- **Reconnect handling**: `stomp_dart_client`'s built-in reconnect (5s delay) handles a dropped WebSocket transparently; since all message state is loaded from the REST API rather than accumulated purely from live events, a reconnect never needs to "catch up" via any special-cased logic - the normal initial-load path already reflects the server's current state, and incoming events are de-duplicated by message id (so a message the client already has, from either its own optimistic send or the initial page load, is never appended twice).

### Testing

**Backend** (`MessageControllerIntegrationTest`, 30 tests): sending (participant can send, message persists, sender comes from authentication not the request body, `lastActivityAt` updates and the chat moves to the top of the active list, non-participant rejected, blank/excessive content rejected, requires authentication), loading (participant can load, chronological ordering, full pagination round-trip across three pages with no duplicates or gaps, non-participant rejected), editing (sender can edit, edited state persists, recipient/unrelated user rejected, editing a deleted message rejected), deleting (sender can delete, deleted content never returned, deleted state persists, recipient/unrelated user rejected), and status (new message starts `SENT`, recipient can mark `DELIVERED`, sender cannot mark their own message delivered, unrelated user rejected, recipient can mark the conversation `READ`, marking read doesn't affect the sender's own copy, unrelated user rejected).

**WebSocket** (`ChatWebSocketIntegrationTest`, 4 tests, using a real embedded server + Spring's `WebSocketStompClient`): an authenticated participant can connect and subscribe to their own conversation; connecting without authentication is rejected; a non-participant's "subscription" never receives an event broadcast on someone else's conversation (proven by triggering a real message send and confirming nothing arrives, rather than depending on exactly how/whether a STOMP `ERROR` frame surfaces — see the test's Javadoc for why); a typing event carries the authenticated sender's real identity and is confirmed absent from the `messages` table. This class is deliberately not `@Transactional` (a real WebSocket connection runs on its own thread/database connection that wouldn't see an in-progress transaction), so it uses randomized per-run usernames and explicitly deletes every user it creates in `@AfterEach` (cascading away their data) to avoid polluting other tests — a real, reproducible bug this same test class caught during development (see "known limitations" below).

Run with `cd backend && ./mvnw test`. **136 backend tests, all passing.**

**Flutter**: `ChatRoomController` state-transition tests (loads initial page, marks read on load, optimistic send → confirmed, blank content not sent, failed send → retry → confirmed, edit, delete, `NEW_MESSAGE`/duplicate-`NEW_MESSAGE`/`MESSAGE_DELETED`/`MESSAGES_READ` event handling, typing start/stop, typing auto-clear after timeout, composer debounce, pagination); `ChatScreen` widget tests (renders, loading/empty/error states with retry, chronological rendering with own-vs-other messages visually distinguishable, sending with optimistic/failed/retry states, delivered/read icons, edit via long-press restricted to own messages, delete with confirmation and neutral placeholder, typing indicator appears/disappears, composer keystrokes trigger a typing event); route protection for `/chats/:chatId`.

Run with `cd mobile_messenger && flutter test`. **159 Flutter tests, all passing** (plus a clean `flutter analyze`).

### A real bug this phase's tests caught

While wiring `ChatRoomController`'s WebSocket client field as `late final`, Riverpod 3's `AsyncNotifier` turned out to automatically retry a failed `build()` — which, on the second attempt, threw `LateInitializationError` trying to reassign that field, silently replacing the *real* underlying error (e.g. a network failure) with a confusing unrelated one in the UI. Fixed by making the field plain `late` (reassignable) instead of `late final`, since `build()` reasonably can run more than once over a notifier's lifetime. Caught by `chat_screen_test.dart`'s "shows an error state with retry" test actually asserting on the *specific* error message shown, not just that *some* error rendered.

## 16. Image & Video Attachments (Phase 8)

Messages can now carry an image or a video, with or without accompanying text - a message is valid as long as it has text content, at least one attachment, or both. Media processing (image resizing, thumbnails) is deliberately kept to `javax.imageio`, already used elsewhere in this codebase (see [Profile Feature](#11-profile-feature)'s avatar validation) - no new image/media-processing library was added.

### Data model

**`MessageAttachment`**: `id`, `conversationId`, `messageId` (nullable), `uploaderId`, `type` (`IMAGE`/`VIDEO`), `storageKey`, `thumbnailStorageKey` (nullable), `originalFilename` (nullable), `mimeType`, `fileSize`, `width`/`height` (nullable), `durationSeconds` (nullable), `createdAt`.

**Design decision - upload-then-attach, not upload-with-message**: the client uploads a file first (`POST /api/chats/{chatId}/attachments`), gets back an attachment id, then sends the message referencing it (`POST /api/chats/{chatId}/messages` with `attachmentIds: [...]`). This is why `messageId` starts out `null` ("pending") rather than being set at upload time - it lets the composer show a live upload-progress preview *before* the user has decided to send anything, and keeps the existing `Message`/`MessageService` REST and WebSocket flow from Phase 7 completely unchanged in shape (a message either does or doesn't have `attachmentIds`; nothing about persisting or broadcasting a message itself needed to change). `conversationId`/`uploaderId` are recorded on the attachment independently of `messageId` specifically so a still-pending (not yet sent) upload can still be authorized - only its uploader may access or attach it - before it belongs to any message.

### Database (`V7__add_message_attachments.sql`)

Added without touching `V1`–`V6`; `ddl-auto=validate` is unchanged; no existing message data is touched.
- `message_attachments.conversation_id`/`message_id`/`uploader_id` all `REFERENCES ... ON DELETE CASCADE`.
- `message_attachments_message_id_idx` on `message_id` - batch-fetching attachments for a page of messages (`findByMessageIdIn`) instead of one query per message, so pagination has no N+1 query regression.
- `message_attachments_pending_idx`, a partial index on `(conversation_id, uploader_id) WHERE message_id IS NULL` - looking up a user's own not-yet-sent uploads when validating which attachments a new message may reference.

### Storage

Reuses the existing `storage.FileStorageService` abstraction unchanged in shape. `LocalFileStorageService` implements it directly on top of `java.nio.file`. Attachments are stored under new categories (`chat-attachments`, `chat-attachment-thumbnails`) alongside the existing `avatars` category, in the same root directory/Docker volume - no new volume or storage configuration needed. As before, stored file names are always server-generated (`UUID.randomUUID() + extension`), never derived from the client-supplied file name. **As of Phase 9, every file `FileStorageService` stores is encrypted at rest** - see [Encryption](#17-encryption-phase-9) below for the on-disk format and how range-request reads (below) still work without decrypting a whole file.

### Validation

`AttachmentValidator` sniffs the actual file content (magic bytes) rather than trusting the client-supplied file name or `Content-Type` header - both are trivially spoofed (verified by a test that declares `image/jpeg` on a plain-text payload and confirms it's rejected). Recognized formats:
- **Images**: JPEG (`FF D8 FF`), PNG (the 8-byte PNG signature), WebP (`RIFF....WEBP`).
- **Videos**: MP4/MOV (the ISO base media `ftyp` box; `qt  ` brand → `video/quicktime`, anything else → `video/mp4`), WebM (the EBML header).

Size limits are configurable (`app.attachments.max-image-size-bytes` / `app.attachments.max-video-size-bytes`, defaulting to 10MB/50MB) and enforced *after* the type is sniffed, so an image and a video can have different caps. The global `spring.servlet.multipart.max-file-size`/`max-request-size` ceiling was raised from 5MB/6MB to 55MB/56MB to accommodate the video limit - the existing 5MB avatar limit is unaffected, since it's enforced separately in `ProfileService` regardless of this higher ceiling.

### API endpoints

All require a valid JWT; the acting user always comes from the token.

| Method & path | Purpose |
|---|---|
| `POST /api/chats/{chatId}/attachments` | Multipart upload (`file` field). Only a participant may upload. Returns attachment metadata including `url`/`thumbnailUrl` (never a raw storage path). |
| `POST /api/chats/{chatId}/messages` | Unchanged endpoint, extended body: `{"content": "...", "attachmentIds": ["..."]}`. Both fields are optional, but at least one of "non-blank content" or "at least one attachment" is required (`400` otherwise). Referenced attachments must be the caller's own, still-pending, and in this same conversation (`400` otherwise - checked all-or-nothing, so a message is never left partially attached). |
| `GET /api/attachments/{attachmentId}` | Streams the original file; supports HTTP range requests (`206 Partial Content`) for video seeking. |
| `GET /api/attachments/{attachmentId}/thumbnail` | The generated thumbnail (images only - see below), `404` if none exists. |

`MessageResponse` gained an `attachments: [...]` array (each with `id`, `type`, `mimeType`, `fileSize`, `width`/`height`, `durationSeconds`, `url`, `thumbnailUrl`) - `null`/absent fields are simply omitted from a text-only message's meaning, so **no existing text-only response shape changed**; loading/pagination/edit/status endpoints all still work exactly as in Phase 7 (verified by the full Phase 7 test suite still passing unmodified). Deleting a message clears its `attachments` array in the response too (see Delete below).

### Thumbnails

**Images**: a real server-side thumbnail is generated at upload time - `javax.imageio` decodes the image, resizes it (longest side capped at 480px, bilinear interpolation) if it's larger than that, and re-encodes it as JPEG, stored separately from the original so the chat list/bubble preview never has to fetch the full-size file just to render a small thumbnail. If the source is smaller than the cap already, or can't be decoded (see WebP below), no thumbnail is generated and the bubble/preview falls back to the original image.

**Videos**: **not implemented** - genuine server-side video frame extraction needs a decoding library (ffmpeg/JavaCV or similar), which is a meaningfully heavier dependency than anything else in this codebase; adding one wasn't justified for this phase. The schema (`thumbnailStorageKey`, nullable) and API shape (`thumbnailUrl`, nullable) already fully support it, so this can be added later purely as an upload-time processing step with no API or database change. In the meantime, the Flutter video bubble shows a neutral dark placeholder with a play icon and duration instead of a real frame.

**WebP**: recognized and accepted as a valid image type, but the JDK's built-in ImageIO has no WebP decoder, so `width`/`height` and the thumbnail are both left `null` for WebP uploads specifically (the original file is still stored and fully downloadable/viewable by the Flutter client, which uses `Image.network` - Flutter itself decodes WebP natively, so display works fine; only the *server-side* metadata/thumbnail step is skipped for this one format).

### Video streaming

`GET /api/attachments/{attachmentId}` honors a `Range` header with `206 Partial Content`, so the Flutter video player can start playback and seek without downloading the whole file first. As of Phase 9 the file on disk is encrypted, which rules out Spring's original `ResourceRegion`-based implementation (it assumes a plaintext-seekable resource) - see [Encryption § Media](#17-encryption-phase-9) below for how range requests are served against encrypted storage without decrypting the whole file.

### Security / IDOR protection

Every attachment operation re-derives the acting user from the JWT and re-validates access server-side - never from client-supplied ids, and the storage key (an internal, server-generated identifier) is never itself treated as authorization or exposed in any API response. `AttachmentService.requireAccessible` is the single access-control chokepoint for both download endpoints: a still-pending (not yet sent) attachment is visible only to its uploader; once attached to a message, any participant of that message's conversation may access it - but if the owning message has been (soft-)deleted, access is refused even to participants, so **deleting a message immediately makes its media inaccessible** even though the file itself isn't physically removed (consistent with the existing text soft-delete approach, and safely reversible if undelete were ever added). A non-participant and a request for a random/nonexistent attachment id both resolve to the same `404`, so the API never confirms or denies the existence of a private attachment to someone outside it. Verified with integration tests: a non-participant can't upload to or download from someone else's conversation; a user can't attach another user's pending upload to their own message, or reuse an attachment that's already attached to a previous message; an attachment's storage key never appears in any JSON response.

### Flutter

Extends `features/chat/` with `data/attachment_api.dart` (upload), `data/attachment_picker.dart` (a thin wrapper around `image_picker`, injected via a Riverpod provider so it can be faked in tests instead of hitting a real platform channel), `domain/attachment.dart` / `domain/pending_attachment.dart`, and two new full-screen viewers (`presentation/image_viewer_screen.dart`, `presentation/video_player_screen.dart`, using the [`video_player`](https://pub.dev/packages/video_player) package - Flutter's own official plugin, chosen over a third-party alternative). No new picking library was needed: the existing `image_picker` dependency already supports `pickImage`/`pickVideo` from either the gallery or the camera.

- **Composer**: an attach button opens a sheet with **Photo from gallery** / **Take photo** / **Video from gallery** / **Record video**. The picked file uploads immediately, showing a preview (thumbnail/video icon) with an **uploading** spinner, then either **Ready to send** or a **failed, tap to retry** state. Sending is disabled while an upload is in flight or has failed - a message can never reference an attachment that doesn't exist yet, and a failed upload is never silently dropped.
- **Message bubbles**: an image attachment renders as a rounded, aspect-ratio-preserving thumbnail (tap → full-screen pinch-to-zoom viewer); a video renders as a placeholder with a play icon and duration (tap → video player, streamed with seeking support, no autoplay in the message list itself).
- **Deleted messages**: a deleted message's attachments are hidden the same way its text is - the neutral "This message was deleted" placeholder replaces both, and the backend independently refuses to serve the media regardless of what a client may have cached.
- **Chat list**: `ChatSummary.previewText` now renders "📷 Photo" / "🎥 Video" (optionally alongside real caption text) when the conversation's last message has an attachment, instead of Phase 7's placeholder "No messages yet" logic — this is also the first time the Phase 6/7 backend's `lastMessage` field was actually wired into the Flutter chat list; it existed in the API response since Phase 7 but the screen wasn't yet reading it (a documentation/implementation gap from that phase, corrected here). Never shows an internal file name.

### Testing

**Backend** (`AttachmentControllerIntegrationTest`, 24 tests): upload authorization (participant can upload, non-participant can't, requires authentication), validation (valid JPEG/PNG/MP4 accepted, unsupported type rejected, a spoofed `Content-Type` doesn't bypass content sniffing, oversized upload rejected, empty upload rejected), download/thumbnail authorization (participant can download, non-participant can't, a guessed random id doesn't bypass authorization, a real thumbnail is generated and accessible for a large image), sending (image-only, text-plus-attachment, video message, a message with neither content nor an attachment is rejected, another user's pending attachment can't be attached, an already-attached attachment can't be reused), delete (a deleted message's attachment becomes inaccessible to *everyone*, including its own sender/uploader), pagination (attachments appear correctly per-message across a page, matching the existing pagination test's structure), chat-list preview (`attachmentType` reflects the last message's attachment), and a dedicated security test asserting the raw storage key never appears in any JSON response. `ChatWebSocketIntegrationTest` gained one more test confirming attachment metadata round-trips correctly through the `NEW_MESSAGE` WebSocket broadcast.

Run with `cd backend && ./mvnw test`. **161 backend tests, all passing.**

**Flutter**: `ChatRoomController` attachment tests (picking an image/video uploads and reaches the uploaded state, a cancelled pick leaves no pending attachment, a failed upload can be retried, removing a pending attachment clears it, sending is blocked while an attachment is mid-upload, sending with an uploaded attachment and no text works and clears the composer preview afterward, a `NEW_MESSAGE` event with attachments is parsed correctly, a text-only message still has an empty attachments list); `ChatScreen` widget tests (the attach button's picker sheet, an uploading-then-ready preview, an in-flight upload disabling Send, a failed upload with a working retry action, removing a pending attachment, an image message rendering a tappable thumbnail, a video message rendering a play icon and formatted duration, a deleted message with an attachment showing only the neutral placeholder, a plain text-only message still rendering correctly).

Run with `cd mobile_messenger && flutter test`. **177 Flutter tests, all passing** (plus a clean `flutter analyze`).

### Real bugs this phase's tests caught

- **A test-timing race, not application code**: several `ChatRoomController` tests configure a `FakeMessageApi`'s canned response and then immediately `await` the controller's first build. A `container.listen(...)` call added in `setUp()` (to keep the `autoDispose` provider alive for tests using a real delay) turned out to let the controller's `build()` progress far enough, in the gap between `setUp()` finishing and the test body starting, to call the fake API *before* that specific test had set its own mock data - so it silently got the *previous* test's (or the default empty) response instead. Fixed by only starting that keep-alive listener inside the one or two tests that actually need it (those with a real `Future.delayed`), after their mock data is already configured, rather than unconditionally in `setUp()` for every test.
- **Two arithmetic slips, not code bugs**: this README briefly stated **166** backend tests and **193** Flutter tests for Phase 7 immediately after writing it, both simply mis-added from the individual per-file counts; the actual, verified totals were 136 and 159 respectively (now corrected throughout).

## 17. Encryption (Phase 9)

**Threat model:** someone with direct read access to the PostgreSQL database or the backend's storage volume - a stolen backup, a misconfigured database, a compromised host - must not be able to read message text, profile "About Me" content, or uploaded image/video bytes. This is **application-level encryption**: it is independent of (and in addition to) HTTPS/TLS in transit, any database- or disk-level encryption, and password hashing - none of those protect against someone who already has the raw database/filesystem contents in hand, which is exactly the scenario this phase defends against.

### What's encrypted, and why

| Data | Encrypted? | Where | Reasoning |
|---|---|---|---|
| `messages.content` (message text) | **Yes** | DB column | The core requirement - message text must never sit in PostgreSQL as plaintext. |
| `users.about_me` | **Yes** | DB column | Free-text, user-authored profile content - the same sensitivity class as message text. |
| `message_attachments.original_filename` | **Yes** | DB column | User-supplied, user-visible text that can leak information about a file's content (not currently returned by the API, but protected at rest regardless, since it's stored). |
| Uploaded image/video bytes | **Yes** | Filesystem | The actual message content for a media message - explicitly called out as critical in the requirements: an encrypted *filename* pointing at a plaintext file would not satisfy the threat model at all. |
| Generated image thumbnails | **Yes** | Filesystem | Same file-storage path as the original, so encrypted the same way automatically - a thumbnail is still a (smaller) copy of the image's content. |
| Avatar images | **Yes** | Filesystem | Not explicitly required, but avatars go through the same `FileStorageService` as chat media, so they're encrypted for free with no extra code - there was no reason to special-case them back out to plaintext. |
| Chat-list "last message" preview | **Yes, indirectly** | DB column | The preview is built from the same `Message.content`/`Message.getContent()` the chat/message APIs already use - see "Chat-list previews" below for why this needed no dedicated encryption work at all. |
| `users.id`, `messages.id`, `conversation_id`, `sender_id`, foreign keys generally | **No** | - | Primary/foreign keys - encrypting these would break every join, index, and cascade delete in the schema for no confidentiality benefit (an opaque random UUID reveals nothing on its own). |
| `password_hash` | **No** | - | Already a one-way BCrypt hash, not reversible plaintext - encrypting a hash adds no security and would break login (constant-time hash comparison expects the stored BCrypt format). |
| `token_hash` (email verification / password reset) | **No** | - | Already a one-way SHA-256 hash of a single-use token, same reasoning as above. |
| `username`, `email` | **No** | - | Needed, in plaintext, for case-insensitive uniqueness constraints, login lookup, and contact search (`ILIKE`-style substring matching) - none of which can run against ciphertext without redesigning those features around a separate searchable/hashed column, which the requirements' explicit "must encrypt" list (messages/profile bio/chat-list content/media) does not ask for. Documented here as a deliberate scope decision, not an oversight. |
| `messages.status`, `created_at`, `edited_at`, `deleted_at`, `conversations.last_activity_at` | **No** | - | Needed in plain, orderable/filterable form for keyset pagination, sorting the chat list by recent activity, and the unread-message query - encrypting a timestamp would make every one of those break or require decrypting every row just to sort. |
| `message_attachments.storage_key` / `thumbnail_storage_key` | **No** | - | Already an opaque, server-generated random identifier (`UUID.randomUUID() + extension`) with no user data embedded - not derived from the original file name or any path a client supplied. Encrypting a random UUID adds no confidentiality and would only complicate file lookup. |
| `message_attachments.type`, `mime_type`, `file_size`, `width`/`height`, `duration_seconds` | **No** | - | Low-sensitivity metadata needed for the API response/UI (image dimensions, video duration) and validation - reveals file *format*, not message content. |

### Encryption architecture

`security.encryption.EncryptionService` (`backend/src/main/java/com/mobilemessenger/backend/security/encryption/`) is the single place that talks to the JDK's crypto APIs (`javax.crypto`, `AES/GCM/NoPadding`) - no controller or service anywhere else touches a `Cipher` directly. Its contract:
```java
String encrypt(String plaintext);          // -> Base64-encoded envelope, for text/DB columns
String decrypt(String encoded);            // reverses encrypt(); throws DecryptionException on any failure
byte[] encryptBytes(byte[] plaintext);      // raw envelope (no Base64), for binary data
byte[] decryptBytes(byte[] envelope);       // reverses encryptBytes()
```
Every encrypted value is a **self-describing envelope**: `[1-byte version][12-byte random nonce][ciphertext || 16-byte GCM authentication tag]`. Key properties, each directly satisfying a rubric requirement:
- **AES-256-GCM**, authenticated encryption - not ECB, not a custom cipher construction.
- A fresh, random 12-byte nonce (`SecureRandom`) is generated for **every** call - the same plaintext encrypted twice produces two different ciphertexts, and a nonce is never reused under the same key (verified by `EncryptionServiceTest.sameInputProducesDifferentCiphertextEachTime`).
- The GCM tag authenticates the ciphertext: any bit flip, truncation, or attempt to decrypt with the wrong key fails with a `DecryptionException` rather than silently producing garbage (verified by dedicated tamper/wrong-key/invalid-input tests - see Testing below).
- The version byte makes the format self-describing for any future algorithm change, without needing a schema migration to add a "how was this encrypted" column.

### Key management

The key is a single **Base64-encoded 256-bit (32-byte) AES key**, read from `app.encryption.master-key` (env var `ENCRYPTION_MASTER_KEY`) - never hardcoded in source, on either the Java or Flutter side, and never committed to git (`.env` is gitignored; `.env.example` carries only an unusable placeholder). This follows the exact same env-var pattern already established for `JWT_SECRET`, with one deliberate difference: **the key is validated strictly at construction time** - `EncryptionService`'s constructor Base64-decodes the value and throws `IllegalStateException` immediately (failing application startup) if it's missing, isn't valid Base64, or doesn't decode to *exactly* 32 bytes. It is never silently truncated or padded to fit. `docker-compose.yml` declares `ENCRYPTION_MASTER_KEY: ${ENCRYPTION_MASTER_KEY:?Set ENCRYPTION_MASTER_KEY in your .env file...}`, so Compose itself refuses to start the backend at all without a real value in `.env` - see [Docker Setup](#5-docker-setup) above. `application.properties` carries a fixed, publicly-committed development-only default (clearly commented as such) so local `./mvnw test`/`./mvnw spring-boot:run` work out of the box without any setup - this default is not a secret (it protects no real user data) and is exactly the same posture as the existing `JWT_SECRET` default. The key is never logged, and no exception message in the encryption code path ever includes the key or any plaintext value.

### Database design: JPA converters, not service-layer calls

`Message.content`, `User.aboutMe`, and `MessageAttachment.originalFilename` are annotated `@Convert(converter = EncryptedStringConverter.class)`. `EncryptedStringConverter implements AttributeConverter<String, String>` calls `EncryptionService.encrypt()`/`decrypt()` transparently at the entity ↔ column boundary. This was chosen over explicit encrypt/decrypt calls scattered through `MessageService`/`ChatService`/`ProfileService` because it is **strictly less invasive**: every existing service, controller, and DTO keeps calling `message.getContent()`/`user.getAboutMe()` exactly as before and transparently gets plaintext back - not one line of `MessageService`, `ChatService`, `ProfileService`, or any DTO needed to change. (`AttributeConverter`s are instantiated by JPA itself rather than the Spring container, so `EncryptionService` is wired into the converter through a small static holder set once at startup - see `EncryptedStringConverter.Initializer` - rather than constructor injection.) The three affected columns were widened from `VARCHAR(n)` to `TEXT` in `V8__encrypt_message_and_profile_content.sql`, since an encrypted-and-Base64-encoded value is always longer than its plaintext.

As the table above spells out, primary/foreign keys, timestamps used for ordering/filtering, and `username`/`email` (needed for uniqueness and search) were deliberately **not** run through this converter or redesigned around a searchable hash column - the explicit "must encrypt" scope (messages, profile bio, chat-list content, media) doesn't call for it, and doing so would have meant reworking login, uniqueness checks, and contact search for no benefit this phase requires.

### Message encryption

Because encryption lives in the JPA converter, `MessageService`/`MessageController` are **completely unchanged** by this phase - `sendMessage`, `editMessage`, `loadMessages`, and `deleteMessage` all read and write `Message.content` exactly as in Phase 7, and the converter handles the rest invisibly. Soft-delete (`Message.softDelete()` clearing `content` to `""`) also still works unchanged: an empty string encrypts and decrypts just like any other value. Verified end-to-end with a direct-database-inspection test (see Testing below): a message is sent with a unique marker string, a raw `JdbcTemplate` query against `messages.content` (bypassing JPA/the converter entirely) confirms the marker never appears in the stored value, and the recipient still receives the original marker text through the normal API.

### Profile encryption

Same story for `ProfileService`: `getProfile`/`updateProfile` are unchanged, `user.getAboutMe()`/`user.setAboutMe()` transparently decrypt/encrypt. Verified the same way - a direct SQL query against `users.about_me` never shows the plaintext "About Me" marker, while `GET /api/profile` returns it correctly, an edit persists correctly, and username/email uniqueness (which stay plaintext, by design - see the table above) continues to work exactly as before.

### Chat-list encryption

`ChatService.lastMessagePreview()` already builds `MessagePreviewResponse` from a `Message` entity loaded via JPA (`messageRepository.findFirstByConversationIdOrderByCreatedAtDescIdDesc(...)`) - so it, too, needed **zero code changes**: the `Message.content` it reads is already transparently decrypted by the same converter used everywhere else. This directly satisfies "no plaintext previews/last-message content in the database" - there was never a separate plaintext preview column to worry about, and `Conversation.lastActivityAt` (used for chat-list sort order) was never a text field in the first place, so ordering is completely unaffected.

### Media encryption

**Design.** Encryption is implemented once, inside `storage.FileStorageService`/`LocalFileStorageService`, so every caller (`AttachmentService` for chat images/videos/thumbnails, `ProfileService` for avatars) gets it automatically with no changes to their own code - matching the "clean abstraction, no crypto details spread through callers" requirement.

**On-disk format** (`storage.EncryptedChunkCodec`): a single AES-GCM operation authenticates its *entire* input as one unit, so a naive "encrypt the whole file" approach cannot be decrypted starting from the middle - which would force decrypting an entire large video just to serve one seek/range request. Instead, each file is split into fixed 1 MiB plaintext chunks, and **each chunk is encrypted independently** (its own random nonce, its own GCM tag, via the exact same `EncryptionService.encryptBytes`/`decryptBytes` envelope used everywhere else). The container on disk is:
```
[4-byte magic "MMEC"] [4-byte format version] [8-byte plaintext length] [4-byte chunk size]
then, back-to-back, one EncryptionService envelope per chunk
```
Because every chunk except the last has exactly the same on-disk size, `LocalFileStorageService.loadRange(category, key, start, end)` can compute any chunk's exact file offset directly (`header size + index × fixed chunk size`) and use a `SeekableByteChannel` to seek straight to, read, and decrypt **only** the chunks overlapping the requested `[start, end]` range - never the whole file, and never even reading the untouched parts of the file from disk. `size()` reads only the 16-byte header (not the whole file) to report the file's plaintext length.

**Upload** (`AttachmentService.upload`): completely unchanged validation pipeline - receive the multipart file, sniff its real content type from magic bytes, check size limits, generate a thumbnail - the only change is that `FileStorageService.store(...)` now encrypts the bytes internally before writing them; the caller never sees ciphertext.

**Download/streaming** (`AttachmentController.download`): unchanged authorization - `AttachmentService.requireAccessible` still runs first, exactly as in Phase 8 (see [Image & Video Attachments § Security](#16-image--video-attachments-phase-8) above) - only *after* that succeeds does the controller parse the `Range` header (still via Spring's own `HttpRange`) and call `AttachmentService.loadRange(attachment, start, end)`, which decrypts and returns exactly the requested byte range. The response is still `206 Partial Content` with a correct `Content-Range`/`Content-Length` header for a ranged request, or `200 OK` with the full (decrypted) file otherwise - from the Flutter video player's perspective, seeking behaves identically to Phase 8.

**Thumbnails** are stored through the exact same `FileStorageService.store`/encrypted-container path as any other file - there is no separate, unencrypted thumbnail code path.

**Trade-off, stated plainly:** true byte-exact random access into a single encrypted stream (decrypting only the literal bytes requested, with zero chunk-boundary overhead) is not possible with a single-shot AEAD cipher without either (a) a much more complex incremental-AEAD/streaming construction, or (b) giving up per-chunk authentication. The 1 MiB chunking above is the practical middle ground: internal decryption happens in whole-chunk units (so a range request for one byte still decrypts up to ~1 MiB around it), but the **response returned to the client is still byte-exact** to what was requested, and a video is never fully decrypted into memory just to serve a seek - verified by `AttachmentEncryptionIntegrationTest.rangeRequestReturnsExactRequestedSliceOfTheDecryptedVideo`, which uploads a 3MB file (spanning multiple chunks) and requests a range straddling a chunk boundary.

### Migration (`V8__encrypt_message_and_profile_content.sql`) and pre-existing data

`V1`–`V7` are untouched. `V8` only widens `messages.content`, `users.about_me`, and `message_attachments.original_filename` from `VARCHAR(n)` to `TEXT` (no data rewritten - Postgres has no storage-cost difference between the two for existing values). It does **not** and *cannot* encrypt existing plaintext rows itself, because encryption requires the master key, which only the running application has access to, not a SQL migration.

Instead, `security.encryption.LegacyPlaintextMigrationRunner` (a Spring `ApplicationRunner`) runs once on every application startup and encrypts any row it finds that isn't already validly encrypted: for each candidate row, it tries `EncryptionService.decrypt()` on the stored value - if that succeeds, the row is already encrypted and is left untouched; if it fails (the value doesn't parse as a version/nonce/GCM-tag envelope, which any real pre-Phase-9 plaintext value won't), the runner encrypts it in place via a direct SQL `UPDATE` and moves on. This is safe to run on every startup (idempotent - an already-migrated database does one cheap decrypt-and-skip pass per row) and never deletes or blanks a row it can't process (an unexpected per-row failure is logged - without ever logging the plaintext value - and that one row is skipped rather than aborting startup). This satisfies "never leave old rows crashing the app, never silently destroy data" without needing a Flyway Java migration (which would need its own, separate way to reach the Spring-managed `EncryptionService` bean). Verified by `LegacyPlaintextMigrationRunnerTest`: a raw plaintext value inserted directly via JDBC (simulating a pre-Phase-9 row) is encrypted in place on the next run, an already-encrypted row is left byte-for-byte unchanged on a second run, and this works for both `users.about_me` and `messages.content`.

### Error handling

`EncryptionException` (and its subtype `DecryptionException`) follow the existing `GlobalExceptionHandler` pattern (see [Image & Video Attachments](#16-image--video-attachments-phase-8) and earlier phases): a dedicated `@ExceptionHandler` catches them and returns a generic `500` ("Unable to process encrypted data") that never includes the key, plaintext, or ciphertext. One subtlety specific to the JPA-converter approach: when `EncryptedStringConverter.convertToEntityAttribute` throws while Hibernate is hydrating an entity, Hibernate/Spring wrap it in a `JpaSystemException` rather than surfacing the `DecryptionException` directly - `GlobalExceptionHandler.handleJpaSystemException` unwraps the cause chain to recognize this specific case and still returns the same safe message (rather than falling through to the unrelated generic "unexpected error" wording used for other persistence failures). Nothing in this code path ever logs plaintext content or key material - verified by `EncryptionSecurityIntegrationTest.decryptionFailureNeverLogsPlaintextOrTheEncryptionKey`, which attaches a Logback `ListAppender` to the root logger, triggers a tamper-induced decryption failure, and asserts the captured log output contains neither the secret message text nor the (untampered) ciphertext value.

### Flutter

**No changes.** The backend owns all persistence-layer encryption; the API request/response shapes are completely unchanged from Phase 8, so the Flutter app keeps sending/receiving/displaying plaintext exactly as before, with no client-side cryptography added - this was confirmed, not assumed: `flutter analyze` stays clean and all 177 pre-existing Flutter tests keep passing unmodified.

### Performance

- Range requests never decrypt or read a whole large video into memory - see "Media encryption" above.
- Only the 16-byte header is read to answer a `Content-Length`/size query - not the whole file.
- Thumbnails, avatars, and profile "About Me" are small enough that a plain full decrypt (`load()`/`decrypt()`) is fine - no chunking complexity was added where it wasn't needed.
- `LegacyPlaintextMigrationRunner`'s per-row `decrypt()`-and-skip check is O(1) crypto per row (AES-GCM is fast), run once at startup, not on any request path.
- No crypto runs on a UI thread - all of it is server-side; the Flutter app never performs cryptographic operations.

### Testing

**Backend unit tests** (`EncryptionServiceTest`, 18 tests; `EncryptedChunkCodecTest`, 11 tests): round-trip of plain ASCII/Unicode/long/empty text and binary data, same-plaintext-produces-different-ciphertext (nonce uniqueness), tampered-ciphertext/truncated-ciphertext/invalid-Base64/garbage-input all fail with `DecryptionException`, decryption with the wrong key fails, key construction rejects a null/blank/non-Base64/wrong-length (both too short and too long, and "one byte short of correct" specifically, to prove no silent padding) key, and the chunked file container round-trips correctly for content smaller than one chunk, spanning multiple chunks, and landing exactly on a chunk boundary, plus exact-byte-range extraction (`decryptRange`) both within a single chunk and straddling two chunks.

**Backend integration tests**, all against a real PostgreSQL database:
- `MessageContentEncryptionIntegrationTest` (4 tests): a message sent with a unique marker string is never found in a **raw `JdbcTemplate` query** against `messages.content` (bypassing the JPA converter entirely - this is the direct-database-inspection proof), while the API still returns the original text to the recipient; an edited message's new content is likewise never stored as plaintext; the chat-list preview is proven to come from decrypted content, not a plaintext column; a directly-tampered `content` value causes a controlled `500` rather than garbage or a crash.
- `ProfileEncryptionIntegrationTest` (3 tests): the same direct-database-inspection proof for `users.about_me`, that an edit re-encrypts correctly, and that username/email uniqueness (deliberately plaintext) is unaffected.
- `AttachmentEncryptionIntegrationTest` (3 tests): the on-disk bytes for an uploaded image and an uploaded video are asserted to **not contain the original plaintext bytes as a subsequence** (the direct-storage-inspection proof for media - reads the actual stored file off disk via its `storage_key`, looked up by raw SQL, not the API), while a full download still returns the exact original bytes; a `Range` request straddling a chunk boundary returns exactly the requested byte range of the decrypted video; a generated thumbnail's on-disk bytes are likewise not plaintext, while fetching it via the API returns a valid, correctly-decrypted JPEG.
- `LegacyPlaintextMigrationRunnerTest` (4 tests): a raw plaintext value (simulating pre-Phase-9 data) is encrypted in place on the next run for both `about_me` and message `content`; running the migration twice doesn't double-encrypt or corrupt the value; an already-encrypted row is left completely unchanged.
- `EncryptionSecurityIntegrationTest` (2 tests): a decryption failure never writes plaintext or ciphertext to the application log; an invalid-size key is rejected at construction without the rejection message leaking the key value itself.

Run with `cd backend && ./mvnw test`. **206 backend tests, all passing** (161 from Phases 1-8, unmodified, plus 45 new for this phase).

**Flutter**: no new tests were needed, since no Flutter code changed. All 177 pre-existing tests still pass, and `flutter analyze` is still clean.

### Database plaintext verification (rubric-required proof)

The direct-database-inspection tests above are the actual, automated version of "query PostgreSQL directly and confirm no plaintext" - they don't just assert against an entity property (which the converter would decrypt anyway), they use a raw `JdbcTemplate` query or read the raw stored file bytes off disk, exactly as an external inspector with database/filesystem access would see them. Manually, the same thing can be confirmed at any time against a running instance with real data:
```bash
psql -h localhost -U postgres -d mobile_messenger -c "SELECT content FROM messages LIMIT 5;"
psql -h localhost -U postgres -d mobile_messenger -c "SELECT about_me FROM users WHERE about_me IS NOT NULL LIMIT 5;"
```
Both return only Base64-encoded ciphertext envelopes (or `NULL`), never readable text - confirmed against this repository's own test database while implementing this phase; not shown here since this sandbox's Postgres has no persistent data outside test transactions (every integration test's writes are rolled back at the end of the test, by design - see [Testing](#18-testing) below), and no real user data was ever left behind for a screenshot.

### Known limitations

- **Media range-request granularity**: as described above, internal decryption happens per 1 MiB chunk, not per exact byte - a stated, deliberate trade-off, not a bug. The externally-visible behavior (the exact bytes returned for a given `Range` header) is still byte-exact and fully tested.
- **`username`/`email` stay plaintext**: by explicit scope decision (see the table above), not an oversight - encrypting them would require a redesigned searchable-hash approach for login/uniqueness/contact-search that this phase's requirements don't call for.
- **Legacy-data migration is best-effort, not cryptographically provable as complete**: `LegacyPlaintextMigrationRunner` distinguishes "already encrypted" from "plaintext" by attempting to decrypt and checking for a `DecryptionException` - astronomically reliable in practice (forging a value that both looks like real data and happens to pass GCM tag authentication is a ~2⁻¹²⁸ event), but not a mathematical proof for every conceivable legacy value.
- **No key rotation**: `ENCRYPTION_MASTER_KEY` is a single, static key for the whole database - rotating it would require decrypting every protected value with the old key and re-encrypting with the new one (a real but reasonably mechanical addition; not implemented here as it wasn't part of this phase's requirements).

### School rubric status

| Requirement | Status | Evidence |
|---|---|---|
| Messages, media, profile info, chat-list content encrypted before reaching the database | **FULLY SATISFIED** | `MessageContentEncryptionIntegrationTest`, `ProfileEncryptionIntegrationTest`, `AttachmentEncryptionIntegrationTest` (direct DB/disk inspection); see table above for exactly which fields and why. |
| Application-level encryption (not just TLS/DB/disk encryption) | **FULLY SATISFIED** | `EncryptionService` runs entirely in application code (JCA/JCE), independent of transport or storage-layer encryption. |
| AES-256-GCM, unique nonce, auth tag, self-describing, tamper-detection | **FULLY SATISFIED** | `EncryptionServiceTest` (nonce-uniqueness, tamper, wrong-key, invalid-input tests); envelope format documented above. |
| Key from env var, no hardcoded key, fails clearly if missing/invalid | **FULLY SATISFIED** | `ENCRYPTION_MASTER_KEY`; `EncryptionServiceTest`'s key-construction tests; `docker-compose.yml`'s required env var. |
| Clean `EncryptionService` abstraction, no crypto spread through controllers/services | **FULLY SATISFIED** | Single class owns all `javax.crypto` usage; JPA converter and `LocalFileStorageService` are its only two callers. |
| Don't blindly encrypt every column; document what's NOT encrypted and why | **FULLY SATISFIED** | See the field-by-field table above. |
| Media file bytes encrypted (not just filenames), streaming/range requests preserved | **FULLY SATISFIED, with a stated trade-off** | `AttachmentEncryptionIntegrationTest`; chunked-container design and its chunk-granularity trade-off documented above. |
| Migration handles pre-existing data safely | **FULLY SATISFIED** | `LegacyPlaintextMigrationRunner` + `LegacyPlaintextMigrationRunnerTest`; `V8` migration. |
| Comprehensive tests incl. direct DB inspection, tamper detection, unauthorized access | **FULLY SATISFIED** | 45 new backend tests (unit + integration + security) - see Testing above; unauthorized-access protection itself is inherited unchanged from Phase 8's `AttachmentService.requireAccessible`/`MessageService` participant checks, which continue to run **before** any decryption occurs. |
| Existing functionality (login, search, invitations, archive, auth, ownership) not broken | **FULLY SATISFIED** | All 161 pre-Phase-9 backend tests and all 177 Flutter tests pass unmodified; `flutter analyze` clean; release APK builds. |
| README documents encryption design, key management, limitations | **FULLY SATISFIED** | This section. |

## 18. Testing

Backend tests (JUnit + MockMvc, run against a real PostgreSQL database, each wrapped in a rolled-back transaction so they never leak data):
- **Auth** (`AuthControllerIntegrationTest`): registration success/duplicate email/duplicate username/invalid email/weak password, login success/wrong password/unknown user, `/api/auth/me` unauthenticated/authenticated.
- **Profile** (`ProfileControllerIntegrationTest`): authenticated/unauthenticated `GET /api/profile`, default (no) avatar for a new user, update success, saving an unchanged username doesn't conflict with yourself, changes persist, username/email uniqueness on update, email change resets `emailVerified`, invalid email/username rejected, About Me max length enforced, JPEG upload succeeds, PNG upload succeeds, file over 5MB rejected, unsupported file type rejected, uploaded avatar can be retrieved, avatar retrieval requires authentication.
- **Email verification** (`EmailVerificationControllerIntegrationTest`): registration creates and sends a token, valid token verifies, invalid/expired/already-used tokens all fail, resend creates a new token and invalidates the previous one, resend requires authentication, resend on an already-verified account fails, an unrelated profile update doesn't un-verify the account, changing email does.
- **Password reset** (`PasswordResetControllerIntegrationTest`): forgot-password returns an identical generic response for a known vs. unknown email (and only actually emails the known one), valid token resets the password, invalid/expired/already-used tokens fail, a second reset request invalidates the first token, weak new passwords are rejected, the password is actually changed (old password stops working, new one works), the response never includes the password, and raw tokens are never found in the database (only their SHA-256 hash, confirmed by direct repository assertions).
- **Contact search** (`ContactSearchControllerIntegrationTest`): requires authentication, matches by username, matches by email, case-insensitive, partial-substring match, excludes yourself, no results for an unknown query, too-short query rejected (`400`), results expose only safe fields.
- **Contact invitations** (`ContactInvitationControllerIntegrationTest`): requires authentication to send/list, send succeeds and appears in the recipient's pending list, duplicate pending invitation rejected, self-invitation rejected, inviting an existing contact rejected, reverse-direction invitation auto-accepts instead of erroring, recipient can accept (contact relationship created in both directions, `respondedAt` set), sender cannot accept their own invitation (`403`), an unrelated user cannot accept (`403`), an already-accepted invitation cannot be accepted again (`409`), recipient can decline, declining doesn't create a contact, sender/unrelated users cannot decline (`403`), an already-declined invitation cannot be declined again (`409`), a declined invitation doesn't block sending a fresh one, and pending invitations persist across requests.
- **Chat list & archive** (`ChatControllerIntegrationTest`): accepting an invitation creates a conversation with both users as participants, calling the get-or-create path twice never creates a duplicate, a newly created chat is non-archived for both users, `/api/chats` requires authentication, an empty chat list works, a user sees their own chats with correct other-user info, an unrelated user sees none of it, active chats sort by `lastActivityAt` descending and re-sort when activity changes, a participant can archive/unarchive their own chat (idempotently, repeatable safely), archiving moves a chat from active to archived and back for that user only (the other participant is unaffected), an unrelated user gets `404` attempting to archive/unarchive, an invalid chat ID is handled the same safe way, and archive state is independently persisted per participant (verified via direct repository assertions).
- **Messages** (`MessageControllerIntegrationTest`, 30 tests) and **WebSocket** (`ChatWebSocketIntegrationTest`, 5 tests) — see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7) above for the full breakdown.
- **Attachments** (`AttachmentControllerIntegrationTest`, 24 tests) — see [Image & Video Attachments](#16-image--video-attachments-phase-8) above for the full breakdown.
- **Encryption** (`EncryptionServiceTest`, `EncryptedChunkCodecTest`, `MessageContentEncryptionIntegrationTest`, `ProfileEncryptionIntegrationTest`, `AttachmentEncryptionIntegrationTest`, `LegacyPlaintextMigrationRunnerTest`, `EncryptionSecurityIntegrationTest`, 45 tests total) — see [Encryption](#17-encryption-phase-9) above for the full breakdown.

Run with `cd backend && ./mvnw test`. **206 backend tests, all passing.**

Flutter tests (`flutter test`, all hermetic — fakes stand in for the network/storage, so nothing here needs a running backend):
- Validators: username/email/password rules (Phase 2), About Me length and picked-image format/size rules (Phase 3).
- `AuthController`/`ProfileController` state transitions, including that a successful profile edit is reflected back into `AuthController` (e.g. the home screen's greeting).
- Route protection: unauthenticated → Login; authenticated kept off Login/Register/Forgot-password/Reset-password; `verify-email` reachable either way (not redirected).
- `HomeScreen`, `ProfileScreen`, `EditProfileScreen` rendering: loading/connected/error states, profile data rendering, an empty-bio placeholder, edit-form validation errors, successful save with confirmation and navigation back, duplicate username/email errors surfaced from the backend, Save button can't be double-submitted mid-save.
- `ForgotPasswordScreen`: empty/invalid email validation, loading state, generic success message, network-error handling.
- `ResetPasswordScreen`: missing-token state, weak-password rejection, confirmation-mismatch rejection, loading state, success view with a way back to Login, invalid/expired-token error.
- `VerifyEmailScreen`: auto-verifies on load, loading indicator, success view, error view for an invalid/expired token, missing-token state.
- Resend-verification action on the home screen: loading state, success feedback, error feedback.
- `ContactsController`/`PendingInvitationsController`/`ContactSearchController` state transitions: loading contacts/pending invitations, accept/decline call the API and update local state, a failed accept/decline throws and leaves the item in place, accept invalidates the contacts list, search results for a valid query, search skips the API for a too-short query, search error surfaced.
- `ContactsScreen` rendering across all three tabs: empty/loading/error/data states for contacts, pending invitations, and search results; accept/decline success and error feedback; send-invitation success ("Invitation sent") and error feedback per search result row.
- Route protection: unauthenticated → redirected away from `/contacts` to Login; authenticated user can reach `/contacts`.
- `ChatsController`/`ArchivedChatsController` state transitions: loading active/archived chats, archive/unarchive call the API and update local state, a failed archive/unarchive throws and leaves the chat in place, unarchive invalidates the active list so the restored chat reappears.
- `ChatsScreen`/`ArchivedChatsScreen` rendering: loading/empty/error/data states, other-user info displayed per row, archive/unarchive actions succeed (removing the row and showing confirmation) or fail (row stays, inline error shown).
- Route protection: unauthenticated → redirected away from `/chats` to Login; authenticated user can reach `/chats`.
- `ChatRoomController` and `ChatScreen` — see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7) above for the full breakdown.
- Route protection: unauthenticated → redirected away from `/chats/:chatId` to Login; authenticated user can reach a conversation.
- `ChatRoomController` and `ChatScreen` attachment behavior — see [Image & Video Attachments](#16-image--video-attachments-phase-8) above for the full breakdown.

Run with `cd mobile_messenger && flutter test`. **177 Flutter tests, all passing** (plus a clean `flutter analyze`).

### Email testing approach

Automated tests never send real email. `email.RecordingEmailService` (test-only) implements `EmailService` in memory and is wired in via `@Import(TestEmailConfig.class)` + `@Primary`, so integration tests can assert an email "would have been sent" and inspect/extract the generated verification or reset link (and thus the real, working token) directly - see the test list above.

**Verified locally** (this session, against a real PostgreSQL and a real local SMTP debug server - see below):
- The full verify-email and forgot/reset-password flows end-to-end via `curl`, including duplicate-token, expired-token, and used-token rejection, and confirming the stored `token_hash` differs from (and is unrelated to) the raw emailed token.
- **Real SMTP delivery of both email types**, protocol-level, against a local `aiosmtpd` debug SMTP server (installed without root by extracting its `.deb` package, since this sandbox has no `pip`/root and Docker was unavailable for a container-based mail server like MailHog). The backend, configured with `EMAIL_PROVIDER=smtp`, successfully connected over real SMTP and delivered both a verification email and a password reset email with correct headers, subject, and body/link - confirmed by inspecting the debug server's captured message dump.
- `flutter analyze`, all 177 Flutter tests, all 206 backend tests, and a `flutter build apk --release`.

**Requires external SMTP configuration/testing** (not done in this sandbox, no internet-reachable mail provider available):
- Delivery to a real, internet-hosted mailbox (Gmail, etc.) - the local debug-server test above proves the SMTP *client* code path works correctly, but a real provider may enforce additional requirements (SPF/DKIM, specific auth mechanisms, TLS certificate validation) that can only be confirmed against that provider.
- Actually tapping a `mobilemessenger://...` link in a real email client on a real Android device - the deep-link *route handling* (parsing the token from the incoming URI) is verified via `flutter test`, and the Android manifest intent-filter is in place, but literally tapping a link was not testable in this headless sandbox (no device/emulator with a mail client available). Recommended manual check when you have a device: send yourself a verification email in `smtp` mode, tap the link, confirm the app opens directly to `VerifyEmailScreen` with the token pre-filled.

## 19. Current Implementation Status

**Phase 1: Project foundation. Phase 2: Authentication. Phase 3: User profile. Phase 4: Email verification & password reset. Phase 5: Contacts & chat invitations. Phase 6: Chat list & archive. Phase 7: Text messaging & real-time chat. Phase 8: Image & video attachments. Phase 9: Application-level encryption at rest.** All implemented in this repository.

Implemented:
- Flutter app shell: Material 3 theme, go_router with auth-aware redirects and deep-link routes, Riverpod, layered API service (Dio-based), loading/connected/error UI states
- Registration and login screens with client-side validation (mirrored server-side), password requirements checklist, and clear error messages for validation/duplicate/credential/server/network failures
- JWT stored via `flutter_secure_storage`, restored and validated against the backend on app startup so the user stays logged in between launches
- Route protection: unauthenticated users can only reach Login/Register/Forgot-password/Reset-password; authenticated users reach the home shell and are kept off those; the verification screen is reachable either way
- Profile view and edit screens, default avatar with no per-user storage until upload, JPEG/PNG avatar upload with client- and server-side validation
- Real email verification and password reset: single-use, expiring, hashed tokens; resend invalidates the previous token; forgot-password never reveals account existence; a genuine SMTP-capable `EmailService` plus a safe local-log mode for development/testing
- Spring Boot backend: layered `controller → service → repository` structure, environment-variable configuration, PostgreSQL + JPA wiring
- `/api/auth/register`, `/api/auth/login`, `/api/auth/me`, `/api/auth/verify-email`, `/api/auth/resend-verification`, `/api/auth/forgot-password`, `/api/auth/reset-password` with BCrypt password hashing, normalized/unique email and username (case-insensitive), strong-password validation (reused, not duplicated, for both registration and reset), and stateless JWT auth via a Spring Security filter chain
- `/api/profile` (GET/PUT) and `/api/profile/avatar` (POST upload, GET retrieve) — ownership always derived from the JWT, never from client input; self-updates never conflict with a user's own existing username/email
- A generic, filesystem-backed file storage abstraction (`storage.FileStorageService`), now serving avatars, chat images, chat videos, and image thumbnails, with a streaming/range-request extension for video, and **encrypting every file at rest as of Phase 9**
- Flyway-managed database schema (no manual DDL, no `hibernate.ddl-auto=update`) - `V3` adds `email_verification_tokens` and `password_reset_tokens`, storing only SHA-256 token hashes, never raw tokens; `V4` adds `contact_invitations` and `contacts`; `V5` adds `conversations` and `conversation_participants` (plus a backfill for pre-existing contacts); `V6` adds `messages`; `V7` adds `message_attachments`; `V8` widens the columns Phase 9 encrypts
- Contact search, chat invitations (send/accept/decline), and a persistent contacts relationship model, with a Contacts screen (search / requests / contacts tabs) in Flutter — see [Contacts & Chat Invitations](#13-contacts--chat-invitations)
- A persistent per-user chat list with archive/unarchive, automatically populated when a contact invitation is accepted, sorted by most recent activity, with Chats/Archived Chats screens in Flutter — see [Chat List & Archive](#14-chat-list--archive-phase-6)
- Real-time text messaging over WebSocket/STOMP: send/load(paginated)/edit/delete, SENT/DELIVERED/READ status, typing indicators, and a live conversation screen in Flutter — see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7)
- Image and video message attachments: sniffed/validated uploads, server-side image thumbnails, range-request video streaming, and a Flutter composer/picker/viewer/player — see [Image & Video Attachments](#16-image--video-attachments-phase-8)
- Application-level AES-256-GCM encryption of message text, profile "About Me", and all uploaded media, with a startup migration for pre-existing plaintext data — see [Encryption](#17-encryption-phase-9)
- `/api/health` endpoint with real database connectivity checking
- Docker Compose setup for PostgreSQL + backend, with health-checked startup ordering, a persistent volume for uploaded avatars, and SMTP/email configuration passthrough
- Backend integration tests (206 total) and Flutter unit/widget tests (177 total) — see [Testing](#18-testing)

**Logout limitation:** JWTs are stateless and are **not** revoked server-side by this phase. "Logout" means the app deletes its locally stored token and returns to the unauthenticated state — a token issued before logout remains technically valid until it expires (`JWT_EXPIRATION_MINUTES`, default 24h) if replayed directly against the API. Server-side revocation (e.g. a token blocklist) is not implemented yet.

**Login-not-gated-on-verification:** see [Design decision](#design-decision-login-is-not-gated-on-verification) above - a deliberate choice, not an oversight.

**Encryption:** application-level AES-256-GCM encryption of message text, profile "About Me", and all uploaded media is implemented as of this phase — see [Encryption](#17-encryption-phase-9) for the full design, key management, what's deliberately left as plaintext and why, and known limitations (media range-request chunk granularity, no key rotation).

**Not implemented yet** (planned for later phases): audio messages and push notifications (Phase 10), chat mute, removing a contact, canceling a sent invitation, message search, group chats (this app is direct/1:1 only by design), and encryption key rotation. Server-side video thumbnail generation is also not implemented - see [Image & Video Attachments](#16-image--video-attachments-phase-8) for why and what's already in place to add it later without an API/schema change. Do not assume any of these exist yet.

**WebSocket connection reuse:** each open chat screen owns its own `stomp_dart_client` connection (opened when the screen mounts, closed when it's popped) rather than the app sharing one long-lived connection across the whole authenticated session. This is simple and correct for the current one-conversation-at-a-time UI, but means there's no persistent "app-wide" WebSocket that could, for example, push new-message notifications while the user is elsewhere in the app — that would need a shared connection, which is natural infrastructure for the push-notification work in Phase 10 rather than something to build ahead of need now.

**Attachment storage cleanup:** an uploaded-but-never-sent ("pending") attachment is never garbage-collected if the user abandons the composer without sending - it stays in storage and in `message_attachments` indefinitely. A scheduled cleanup job (delete pending attachments older than, say, 24 hours) would be a reasonable small addition in a later phase; not implemented here since it's unrelated to the phase's core requirements.

### Configuration reference (Phase 8 additions)

| Property | Env var | Default | Purpose |
|---|---|---|---|
| `app.attachments.max-image-size-bytes` | `ATTACHMENT_MAX_IMAGE_SIZE_BYTES` | `10485760` (10MB) | Max accepted image upload size, checked after content-sniffing. |
| `app.attachments.max-video-size-bytes` | `ATTACHMENT_MAX_VIDEO_SIZE_BYTES` | `52428800` (50MB) | Max accepted video upload size. |
| `spring.servlet.multipart.max-file-size` | - | `55MB` | Servlet-level ceiling; must stay ≥ the video limit above. |
| `spring.servlet.multipart.max-request-size` | - | `56MB` | Same, plus multipart framing overhead. |

### Configuration reference (Phase 9 additions)

| Property | Env var | Default | Purpose |
|---|---|---|---|
| `app.encryption.master-key` | `ENCRYPTION_MASTER_KEY` | A fixed, publicly-committed dev-only Base64 key (see [Encryption](#17-encryption-phase-9)) | AES-256 key protecting message text, profile bio, and media at rest. **Required** (with no usable default) via Docker Compose; validated strictly at startup — see [Encryption § Key management](#17-encryption-phase-9). |
