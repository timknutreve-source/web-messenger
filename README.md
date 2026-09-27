# Web Messenger

One Flutter codebase, one Spring Boot backend, one PostgreSQL database — serving both the original Android app and a full desktop-capable web client, signed into the same account on both at once if you like. Everything in this document that describes "Mobile Messenger" still applies unchanged to the Android app; this revision folds the web client in alongside it rather than describing two separate projects. New, web-specific material lives in [§18](#18-sessions--multi-device) through [§23](#23-deployment) below; everything before that is unchanged from the mobile-only phases and applies equally to both clients.

## Quick Start — How to Run

This section is for anyone who just wants to **run** the app (reviewer, tester, grader) without installing the full Flutter/Android/Java development toolchain beyond what's needed to build a single APK — or, for the web client, without installing anything beyond a browser. Clone the repository, start the backend with one command, then launch the app one of four ways (Android emulator, physical Android device, browser, or a production web build) — no pre-built artifact is required, everything is built from this repo.

### 1. Backend (one command)

**Prerequisite: Docker Desktop** (the one unavoidable dependency — install it and make sure it's running; no other manual setup is required).

```bash
cd ~/mobile-messenger
./start.sh
```

That single command builds the backend image, starts PostgreSQL and the backend via Docker Compose, waits for the health check to pass, and prints every URL you need for the launch methods below (the Android emulator's fixed address, and — if reachable — this machine's current LAN IP for a physical device). No `.env` file, manual database setup, or manual network configuration is required.

The containers run **detached** (in the background), so `./start.sh` finishing and returning you to the terminal prompt is expected and normal — it does not mean the backend stopped. Use `docker compose logs backend` to watch its logs, and `docker compose down` to stop it.

This has been tested and confirmed working after a full Windows restart: `./start.sh` alone brings PostgreSQL and the backend up, the health check passes, and a physical Android phone can connect — with **no manual `netsh` portproxy configuration, no manual WSL IP lookup, and no manual Windows Firewall rule needed**. See [Docker Setup](#5-docker-setup) below for what the script wraps, and why.

### 2. Android emulator

With the backend running ([§1 above](#1-backend-one-command)):
1. Build the release APK:
   ```bash
   cd mobile_messenger
   flutter build apk --release
   ```
   The APK is written to `mobile_messenger/build/app/outputs/flutter-apk/app-release.apk` (see [§10](#10-how-to-build-the-android-apk)).
2. Start an Android emulator (Android Studio → Device Manager → create/start a virtual device — a one-time setup if you don't already have one; no Flutter SDK needed just to run the emulator itself).
3. Install the APK onto it:
   ```bash
   adb install mobile_messenger/build/app/outputs/flutter-apk/app-release.apk
   ```
   (or drag-and-drop the `.apk` file onto the running emulator window)
4. Open **Mobile Messenger** from the emulator's app drawer.

The emulator automatically reaches the backend at `http://10.0.2.2:8080` (its built-in alias for the host machine) — the plain `flutter build apk --release` command above already points there by default, so no `--dart-define` override is needed for the emulator specifically, and **no manual portproxy or WSL networking configuration of any kind** is required.

### 3. Physical Android device

Your phone and the computer running the backend must be on the **same Wi-Fi network** (or the same mobile hotspot).

1. Run `./start.sh` (see [§1 above](#1-backend-one-command)) — its output includes this computer's current LAN IP, for example:
   ```
   Physical Android device (same Wi-Fi/hotspot) should use: http://<COMPUTER_IP>:8080
   ```
2. Build the APK pointed at that exact address:
   ```bash
   cd mobile_messenger
   flutter build apk --release --dart-define=API_BASE_URL=http://<COMPUTER_IP>:8080
   ```
   replacing `<COMPUTER_IP>` with the address `./start.sh` printed for you.
3. Copy the resulting `mobile_messenger/build/app/outputs/flutter-apk/app-release.apk` to your phone (USB cable, or any file-sharing method) and install it (open the file, tap **Install**, allowing "Install from this source" if prompted — a normal Android prompt, not a project-specific step).
4. Open **Mobile Messenger** on the phone.

The IP address is only known once you're actually on a network, so it is never hardcoded here — always use the value `./start.sh` prints for your current setup. If you change networks later, re-run `./start.sh` and rebuild the APK with the new address it reports.

### 4. Browser (no Android tooling at all)

1. Make sure the backend is running (`./start.sh`, see [§1 above](#1-backend-one-command)).
2. Run the web app:
   ```bash
   cd mobile_messenger
   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
   ```
   This compiles the app and opens it directly in a Chrome window. On Linux, if only Chromium (not Google Chrome) is installed, first run `export CHROME_EXECUTABLE=/usr/bin/chromium-browser` (or wherever your Chromium binary is) in the same terminal.

This is entirely local — nothing is deployed or made accessible outside your machine. The web build compiles and serves successfully; note that browser permission prompts (camera/microphone/file picker) look and behave like the browser's own dialogs rather than Android's native ones, since those are OS-level UI, not something this app controls.

Once open, widen the browser window past roughly 900px and the app switches from the phone's single-screen layout to a three-pane desktop layout automatically (left: profile/search/chats/contacts/invitations; centre: the active chat, or two side by side; right: chat info/search results/members) — see [§22](#22-web-responsive-layout--two-chat-desktop-view) for details. Narrow the window back down and it returns to the phone layout with no reload needed.

### 5. Production web build (a static bundle you can host anywhere)

To build the same app as a deployable static bundle instead of running it live in a dev session:
```bash
cd mobile_messenger
flutter build web --release --dart-define=API_BASE_URL=https://<your-backend-address>
```
The output lands in `mobile_messenger/build/web/` — a plain static site (`index.html`, JS, assets) servable by any static file host or web server; there is no server-side rendering step. `API_BASE_URL` is compiled into the JavaScript at build time (it is a Dart compile-time constant, not read at runtime), so it must already be the address a *browser* on the public internet can reach your backend at, over HTTPS if the web app itself is served over HTTPS — browsers block a secure page from calling an insecure (`http://`) API. Rebuild (this step) whenever that address changes.

A `Dockerfile` at `mobile_messenger/Dockerfile` builds exactly this bundle and serves it with nginx — see [§25 Deployment](#23-deployment) for how to build and run it, and for this repository's actual, honestly-reported deployment status.

### 6. Basic usage

Once the backend is running (`./start.sh`) and you have the app open (any of the ways above):
1. **Register** a new account (username, email, password).
2. **Verify your email**: by default the backend logs the 6-digit verification code to its own console instead of emailing it (`EMAIL_PROVIDER=log` — see `docker compose logs backend`); if real SMTP credentials are configured (`EMAIL_PROVIDER=smtp` in `.env`), a real email is sent instead. Either way, enter the code on the **Verify your email** screen the app shows automatically.
3. **Log in** (or you're already logged in straight after registering).
4. **Find contacts**: open Contacts and search by username or email.
5. **Send an invitation** to a search result, then — from a second account — **accept it** from the Pending Invitations tab to become contacts.
6. **Start a chat** with that contact and **send messages**: text, images, videos, and audio, sent and received live over WebSocket.
7. **Forgot password** on the login screen works the same way as verification — request a reset code, enter it, then choose a new password.
8. **Profile**: tap the profile icon (or, on the desktop layout, your name in the top-left) to view/edit your username, email, About Me, and profile picture.
9. **Create a group**: tap **New group** (Chats screen app bar on the phone layout, or the same icon in the desktop left pane), name it, and tick which contacts to invite; each invitee sees it under their **Invites** tab and can **Join** or decline.
10. **Group chats** behave like individual chats for sending text/images/videos/audio, plus a poll button in the composer (group chats only): **Create poll**, add 2–10 options, optionally toggle **Anonymous poll**, then tap an option in the resulting card to vote (tap it again, or **Retract vote**, to take it back).
11. **Search inside a chat**: tap the search icon in a chat's header, type a query, and use the up/down arrows to step through matches (highlighted inline) — works the same in an individual or a group chat.
12. **Manage your sessions**: the same account can be logged in on the phone and in a browser (or two browsers) at once; each **Log out** button only ends *that* device's session, and (once the sessions endpoints have a settings UI wired to them — currently reachable via `GET /api/auth/sessions`) another session can be revoked remotely without touching the others.
13. **Two chats at once (desktop/wide-browser only)**: widen the browser window past ~900px to get the three-pane layout, then use a chat row's **Open side by side** button to view and use a second chat next to the first — each has its own composer, search, and live updates, entirely independent of the other.

### 7. Easy Launch summary

The whole project is meant to be tested straight from this repository — no pre-built artifact is needed or provided:
1. Clone the repository.
2. Run `./start.sh` (Docker Desktop required — the only prerequisite for the backend).
3. Launch the app one of four ways: install a self-built APK on an Android emulator, build an APK for your own network and install it on a physical Android device, run it directly in a browser via `flutter run -d chrome`, or build the production web bundle and serve it (locally, or via the provided `Dockerfile`).

No manual multi-service setup, no manual database configuration, and no manual networking configuration (portproxy, WSL IP lookup, firewall rules) is ever required.

### 8. Web ↔ Mobile Synchronization

This is the single walkthrough for proving the Web and Android clients share one live account, one chat, and one backend — the core claim of this whole project. It's the same behavior [§24 Testing](#24-testing) verifies automatically (both in fake-backed unit tests and in the real-browser Playwright suite), spelled out here as manual steps.

1. **Start the backend** — `./start.sh` from the repo root (see [§1](#1-backend-one-command)). Note the address it prints for your situation (see step 4).
2. **Start Web Messenger** — from `mobile_messenger/`:
   ```bash
   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
   ```
   (Replace the URL with whatever address applies to your setup — see step 4.)
3. **Start the Android app**, built from the *same* repository, pointed at the *same* backend address — see step 4 for which address to use, then either:
   ```bash
   cd mobile_messenger
   flutter build apk --release --dart-define=API_BASE_URL=<the same address as step 2>
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```
   or, if a device/emulator is already connected, `flutter run -d <device-id> --dart-define=API_BASE_URL=<the same address>` for a faster edit-and-reload loop instead of a full release build.
4. **Both clients must point at the same backend.** Which address that is depends entirely on where the backend and the Android client actually are relative to each other:
   - **Android emulator + backend on the same machine**: `http://10.0.2.2:8080` — the emulator's fixed alias for the host. This is already the Flutter app's own default on Android, so it needs no explicit override.
   - **Physical Android phone + backend on your computer**: your computer's current LAN IP (e.g. `http://192.168.1.23:8080`) — printed by `./start.sh`, since it changes between networks. The phone and computer must be on the same Wi-Fi/hotspot.
   - **Production (Railway or any other public deployment)**: the backend's public **HTTPS** URL, e.g. `https://<YOUR-BACKEND-DOMAIN>` — see [§23 Railway Deployment](#23-deployment). A browser refuses to call a plain `http://` API from a page it loaded over `https://`, so this must be HTTPS once anything is actually deployed.

   The web client in step 2 always uses `http://localhost:8080` (or the production HTTPS URL) since a browser on the same machine as the backend reaches it directly — it never needs the `10.0.2.2` emulator alias, which is Android-only.
5. **Log in with the same account on Web.** Register once (through either client) if you haven't already.
6. **Log in with the same account on Mobile.** The same JWT-based session works identically on both — see [§18 Sessions & Multi-Device](#18-sessions--multi-device); logging in on Android does not sign the web session out, and vice versa.
7. **Open the same chat on both** — a direct chat with a contact, or a group both accounts belong to.
8. **Send a message Web → Mobile.** Type it in the browser and send.
9. **Confirm it appears on Mobile in real time** — no manual refresh, typically well under 2 seconds (this is the exact latency the automated `CrossPlatformSyncIntegrationTest` and the Playwright e2e suite both assert on, over the same WebSocket/STOMP path described in [§15](#15-text-messaging--real-time-chat-phase-7)).
10. **Send a message Mobile → Web** and confirm the reverse direction the same way.
11. **Check delivery/read status**: opening the chat on the recipient's side should flip the sender's copy from a single check (sent) to a double check (delivered), then to a filled/colored double check (read) — see [§15 § Message status flow](#15-text-messaging--real-time-chat-phase-7).
12. **Confirm both sessions stay independent**: log out on one device (or revoke it from `GET /api/auth/sessions` on the other) and confirm the other device's session, and its open chat, keeps working untouched — see [§18](#18-sessions--multi-device).

### 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| App shows a network/connection error immediately on login or chat load | Wrong `API_BASE_URL` for where the client is actually running | See step 4 of [§8 Web ↔ Mobile Synchronization](#8-web--mobile-synchronization) above — Android emulator, physical phone, and production each need a *different* address. Rebuild/re-run with the right `--dart-define=API_BASE_URL=...`; remember it's compiled in, not read at runtime. |
| Android **emulator** can't reach the backend | Using `localhost` instead of the emulator's host alias | The emulator must use `http://10.0.2.2:8080`, not `http://localhost:8080` — `localhost` inside the emulator means the emulator itself, not your computer. This is already the Flutter app's own Android default, so only an explicit `--dart-define` override could break it. |
| **Physical** Android phone can't reach the backend | Wrong/stale LAN IP, or phone and computer on different networks | Re-run `./start.sh` to get the *current* LAN IP (it can change between networks or router restarts) and rebuild the APK with that address; confirm the phone and computer are on the same Wi-Fi/hotspot. |
| `docker compose up` fails immediately, or the backend never becomes healthy | Postgres isn't reachable yet, or a port is already in use | Check `docker compose logs backend` and `docker compose logs postgres`; make sure nothing else on the host is already using 5432/8080, and that the `postgres` service shows `healthy` (`docker compose ps`) before the backend starts serving. |
| Browser blocks API calls, or the WebSocket never connects, once deployed publicly | CORS origin mismatch, or the WebSocket URL doesn't match the page's own scheme | `CORS_ALLOWED_ORIGINS` must be exactly the origin the web app is served from (scheme + host, no trailing slash) — see [§23](#23-deployment). A page served over `https://` must talk to the backend over `wss://`/`https://`, never `ws://`/`http://` — browsers block the mixed-content combination outright. |
| `500 Unable to process encrypted data` on an existing chat/profile | `ENCRYPTION_MASTER_KEY` doesn't match the key the data was originally encrypted with | This is by design — AES-GCM deliberately can't tell "wrong key" apart from "tampered data" (see [§17](#17-encryption-phase-9)). There is no way to recover data encrypted under a lost key; make sure the *exact same* `ENCRYPTION_MASTER_KEY` is used every time the same database is reused, and never regenerate it once real data exists. |
| No verification/reset email arrives | `EMAIL_PROVIDER` is still `log` (the default), or SMTP credentials are wrong | With the default `EMAIL_PROVIDER=log`, the code is never emailed — read it from `docker compose logs backend` (grep for `DEV EMAIL`) instead. To send real email, set `EMAIL_PROVIDER=smtp` plus real `SMTP_*` values (see [§12](#12-email-verification--password-reset)) and check the backend log for an SMTP send failure warning. |
| A chat/profile picture, video, or voice message won't load or play | Backend can't reach its storage volume, or the file predates a changed `ENCRYPTION_MASTER_KEY` | Confirm `STORAGE_ROOT_DIR` (`/app/storage` in Docker) is backed by a *persistent* volume that survived container recreation (see [§23](#23-deployment)) — an ephemeral filesystem loses every uploaded file on redeploy, which looks identical to a permissions problem from the client's point of view. |

## 1. Project Overview

Web Messenger (built on top of what began as Mobile Messenger) is a full-stack messaging application with **one Flutter codebase, one Spring Boot backend, and one PostgreSQL database serving both an Android app and a browser-based web client** — the same account, the same contacts, the same chats, either at once, kept in sync in real time over the same WebSocket infrastructure. **This repository contains Phase 1 (project foundation) through Phase 9 (application-level encryption at rest) unchanged from the mobile-only phases, plus Phase 10 (multi-device sessions), Phase 11 (group chats & invitations), Phase 12 (in-chat message search), Phase 13 (polls), and Phase 14 (the web-responsive desktop layout, including two chats open side by side).**

Functional today:
- A backend health check the Flutter app calls to display whether the backend (and its database connection) is reachable.
- Full registration and login with JWT-based authentication, a protected `/api/auth/me` endpoint, and a Flutter app that persists the session between launches and protects its authenticated screens.
- A user profile: username, email, About Me, and a JPEG/PNG avatar, viewable and editable from the app, with the picture stored on the backend filesystem and referenced (not embedded) in PostgreSQL.
- Real email verification and password reset, with a genuine (configurable SMTP or safe local-log) email-sending abstraction, single-use expiring tokens, and matching Flutter screens reachable via deep link or in-app navigation.
- Contact search, individual **and group** chat invitations (send/accept/decline), and a persistent contacts list — see [Contacts & Chat Invitations](#13-contacts--chat-invitations) and [Group Chats & Group Invitations](#19-group-chats--group-invitations) below.
- A per-user chat list (individual chats and groups together, sorted by latest activity) with archive/unarchive, and real-time text messaging over WebSocket/STOMP with sent/delivered/read status, edit, delete, and typing indicators — see [Chat List & Archive](#14-chat-list--archive-phase-6) and [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7) below.
- Image, video, and voice-message attachments on messages, with server-side validation/thumbnails and range-request video streaming — see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8) below.
- Message text, profile "About Me", chat-list previews, and uploaded media are encrypted at rest with AES-256-GCM before they ever reach PostgreSQL or disk — see [Encryption](#17-encryption-phase-9) below.
- The same account signed in on several devices at once (e.g. Android and a browser, or two browser tabs), each an independently listed and individually revocable session, with selective logout — see [Sessions & Multi-Device](#18-sessions--multi-device) below.
- Group chats: create a group, invite contacts to it, accept/decline, per-group membership and roles, group message delivery/read aggregation, and a members/invitees panel — see [Group Chats & Group Invitations](#19-group-chats--group-invitations) below.
- Text search inside any individual or group chat, with match highlighting, next/previous navigation, and jump-to-message — see [Message Search](#20-message-search) below.
- Polls in group chats — public or anonymous, change/retract your vote, persisted and synced live — see [Polls](#21-polls) below.
- A responsive desktop web layout (navigation + chat list on the left, the active chat in the centre, chat info/search/members on the right) that supports **two chats open side by side**, alongside the unchanged single-screen phone layout — see [Web Responsive Layout & Two-Chat Desktop View](#22-web-responsive-layout--two-chat-desktop-view) below.

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
- [video_player](https://pub.dev/packages/video_player) (Flutter's official plugin) for chat video playback (see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8))
- [record](https://pub.dev/packages/record) / [audioplayers](https://pub.dev/packages/audioplayers) for recording and playing back voice messages, on both native platforms and the web
- [scrollable_positioned_list](https://pub.dev/packages/scrollable_positioned_list) for the message list's programmatic jump-to-message (search results) alongside its normal scroll behavior
- The `web` package (`package:web`) for the small set of genuinely browser-only concerns — building a blob URL for a picked file/video, resolving the platform label used for a session's device name — kept behind conditional imports so native builds never reference it
- A single `LayoutBuilder`-driven breakpoint (`kIsWeb` is irrelevant here — a desktop-sized *window* is what matters, not the platform) chooses between the original phone layout and a new desktop shell at runtime, with no separate build/target per form factor (see [Web Responsive Layout & Two-Chat Desktop View](#22-web-responsive-layout--two-chat-desktop-view))

### Backend
- Java 21, Spring Boot 4, Spring Security
- Spring Web (MVC), Spring Data JPA
- Spring WebSocket (STOMP over WebSocket) for real-time chat events (see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7)); a browser client authenticates its handshake via a `?access_token=` query parameter instead of a header, since a browser WebSocket cannot set one (see [Sessions & Multi-Device](#18-sessions--multi-device))
- PostgreSQL, with Flyway-managed schema migrations
- JWT (jjwt) for stateless authentication (now with per-session server-side revocation - see [Sessions & Multi-Device](#18-sessions--multi-device)), BCrypt for password hashing
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
│   │   │   ├── chat/            # Chat list, archive, conversation panel/screen, messages, search, polls, WebSocket client
│   │   │   ├── group/           # Group create/invite dialogs, group domain model, group providers
│   │   │   ├── shell/           # Desktop three-pane layout + the two-chat workspace controller
│   │   │   └── health/          # Backend connectivity check + authenticated home shell (phone layout)
│   │   ├── routing/              # go_router configuration (auth-aware redirects, deep links)
│   │   ├── app.dart               # MaterialApp.router root widget
│   │   └── main.dart              # Entry point
│   ├── android/                   # Android project (custom URL scheme deep-link intent-filter)
│   ├── web/                       # Web app shell (index.html, manifest.json) - Flutter's compiled output for `flutter build web`
│   ├── test/                      # Unit + widget tests (fakes only, no real network)
│   ├── integration_test/          # Real end-to-end test against a live backend
│   ├── Dockerfile                 # Builds the web app and serves it with nginx - see Deployment
│   └── pubspec.yaml
│
├── backend/                      # Spring Boot app
│   ├── src/main/java/com/mobilemessenger/backend/
│   │   ├── auth/                  # controller / service / DTOs / JWT / Spring Security config
│   │   │   ├── token/              # Email-verification & password-reset token entities/repos/generator
│   │   │   └── session/             # AuthSession entity/repository/service - multi-device sessions
│   │   ├── email/                  # EmailService abstraction (SMTP + local-log implementations)
│   │   ├── user/                  # User entity + repository + shared safe-view DTO
│   │   ├── profile/                # controller / service / DTOs for viewing/editing the profile
│   │   ├── contact/                 # Contact search, invitations, contacts (entities/services/controllers/DTOs)
│   │   ├── chat/                    # Conversations, chat list/archive, messages, search, WebSocket/STOMP config
│   │   │   ├── group/                # Group creation, group invitations
│   │   │   ├── poll/                 # Polls, poll options, votes
│   │   │   └── websocket/            # STOMP config, event payloads, subscription auth, after-commit dispatch
│   │   ├── storage/                 # Generic file storage abstraction (avatars, chat media)
│   │   ├── health/                # controller / service / repository for health checks
│   │   └── common/                # Shared error/message response + exception handling
│   ├── src/main/resources/
│   │   ├── application.properties
│   │   └── db/migration/          # Flyway SQL migrations (schema of record)
│   ├── src/test/java/...
│   ├── Dockerfile
│   └── pom.xml
│
├── e2e/                           # Real-browser Playwright suite against the built web app - see Testing
├── docker-compose.yml
├── start.sh                      # One-command backend startup (see Quick Start above)
├── .env.example
├── .gitignore
└── README.md
```

## 4. Requirements

- **Docker Desktop** (recommended path — no local PostgreSQL/Java install needed; see [Quick Start](#1-backend-one-command) above for the single-command `./start.sh`), with **Docker Compose v2.24 or newer** (`docker compose version` to check — only strictly required for the production/Railway-style multi-file Compose invocations in [§23](#23-deployment); the plain local `./start.sh`/`docker compose up` path works with any reasonably recent Compose).
- For local (non-Docker) backend development: **Java 21** (the project is built and tested against Eclipse Temurin 21) and Maven (or the bundled `./mvnw`).
- **Flutter 3.41.9** (bundles **Dart 3.11.5** — this is the exact version the app is developed and CI-tested with, and the same version `mobile_messenger/Dockerfile` pins for the production web build; a newer stable release will very likely also work, but hasn't been verified here) — needed to build the app for any launch method (Android emulator, physical device, browser, or iOS), since no pre-built binary is provided; see [Quick Start](#quick-start--how-to-run).
- For an Android build: the Android SDK/toolchain (`flutter doctor` should show it as ✓) and either a running emulator or a physical device.
- For an iOS build: a Mac with Xcode (the repo includes an `ios/` Flutter project, but **iOS was not the primary test target in this environment** — no Mac was available to verify it; treat it as "should work, same codebase, not verified here" rather than "confirmed").
- **A modern desktop browser** (Chrome, Firefox, or Edge, current release) to run/test the web client — the app is Flutter Web compiled with the CanvasKit renderer, which needs WebGL support that every mainstream evergreen browser already provides.
- **Camera and/or microphone permission**, granted when the browser or OS prompts for it, if you want to test taking a photo/video or recording a voice message directly from the app rather than picking an existing file.
- Real SMTP credentials are **only** needed if you want to send real emails (`EMAIL_PROVIDER=smtp`) — everything works, and is fully testable, without them (see below).
- *(Optional, only for the `e2e/` Playwright suite — not needed to build or run the app itself)* Node.js, to `npm install` and drive a real headless browser against the compiled web build; see [§24 Testing](#24-testing).

### Environment Variables Reference

Every environment variable the backend and the web build actually read, in one place. "Local default" is what applies with no `.env` file at all (plain `docker compose up` / `./start.sh`); "Production" is what [§23 Railway Deployment](#23-deployment) and the VPS runbook both require you to set explicitly.

| Variable | Required? | Local default | Production | Purpose |
|---|---|---|---|---|
| `SERVER_PORT` | Optional | `8080` | Usually left unset | Explicit backend port override. See also `PORT` below — `server.port=${SERVER_PORT:${PORT:8080}}`, so `SERVER_PORT` always wins if both are set. |
| `PORT` | Optional (platform-injected) | *(unused locally)* | Set automatically by Railway/Render/Heroku-style platforms | Fallback backend port, read only if `SERVER_PORT` isn't set — this is what makes the backend work unmodified on Railway, which assigns and injects this itself. |
| `WEB_PORT` | Optional | `8090` | Not used on Railway (each service gets its own Railway-assigned port) | Host port for `docker compose --profile web`'s nginx container, local/VPS only. |
| `DB_HOST` | Required in production | `postgres` (Docker Compose service name) / `localhost` (no Docker) | The database host — on Railway, a reference to the Postgres service | PostgreSQL connection. |
| `DB_PORT` | Optional | `5432` | Usually `5432` (or Railway's reference value) | PostgreSQL connection. |
| `DB_NAME` | Optional | `mobile_messenger` | Your choice / Railway's default database name | PostgreSQL connection. |
| `DB_USERNAME` | Optional | `postgres` | Set by whoever provisions the database | PostgreSQL connection. |
| `DB_PASSWORD` | **Required** in production | `postgres` (dev-only, publicly committed) | A real, unique password | PostgreSQL connection. |
| `JWT_SECRET` | **Required** in production | A fixed, publicly-committed dev-only value | `openssl rand -base64 48` | Signs/validates session JWTs. Changing it in production signs every user out. |
| `JWT_EXPIRATION_MINUTES` | Optional | `1440` (24h) | Your choice | How long an issued JWT stays valid before needing a fresh login. |
| `ENCRYPTION_MASTER_KEY` | **Required** in production | A fixed, publicly-committed dev-only value | `openssl rand -base64 32` | AES-256 key protecting message text, profile bio, group names, poll options, and all media at rest — see [§17](#17-encryption-phase-9). **Never change it once real data exists** — data written under the old key becomes unreadable. |
| `CORS_ALLOWED_ORIGINS` | **Required** in production | `*` (any origin — fine only because nothing but this machine calls it locally) | The exact browser origin(s) allowed to call the API / open `/ws`, e.g. the Railway web service's public URL | Browser CORS + WebSocket handshake origin check. |
| `STORAGE_ROOT_DIR` | Optional | `/app/storage` (Docker) / `./data/storage` (no Docker) | `/app/storage`, backed by a **persistent volume** (see [§23](#23-deployment)) | Where uploaded avatars/attachments (encrypted) are written. |
| `ATTACHMENT_MAX_IMAGE_SIZE_BYTES` | Optional | `10485760` (10MB) | Your choice | Max accepted image upload size. |
| `ATTACHMENT_MAX_VIDEO_SIZE_BYTES` | Optional | `52428800` (50MB) | Your choice | Max accepted video upload size. |
| `ATTACHMENT_MAX_AUDIO_SIZE_BYTES` | Optional | `15728640` (15MB) | Your choice | Max accepted voice-message upload size. |
| `EMAIL_PROVIDER` | Optional | `log` | `log` (demo) or `smtp` (real signups) | Selects the verification/reset email backend — see [§12](#12-email-verification--password-reset). |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_FROM_EMAIL` / `SMTP_AUTH` / `SMTP_STARTTLS` | Only if `EMAIL_PROVIDER=smtp` | *(empty / provider placeholders)* | Your real mail provider's values | Real email delivery — see [§12](#12-email-verification--password-reset). |
| `API_BASE_URL` | **Required** (build-time, not runtime) | `http://localhost:8080` (`http://10.0.2.2:8080` on the Android emulator) | `https://<your-backend's-public-domain>` | Compiled into the Flutter app at build time (`--dart-define=API_BASE_URL=...` or the web `Dockerfile`'s `--build-arg`) — it is **not** read at runtime, so changing it always means rebuilding. See [Quick Start §2-3](#2-android-emulator), [§10](#10-how-to-build-the-android-apk), and [§23](#23-deployment). |
| `WEB_API_BASE_URL` | Used by `docker compose --profile web` only | `http://localhost:8080` | Same value as `API_BASE_URL` above, passed through as the web image's build arg | Local/VPS Docker Compose's name for the same setting as `API_BASE_URL`. |

None of these are hardcoded in source; every one above is read from an environment variable with an explicit (and, for the two crypto secrets, clearly-marked *insecure*) local default. See `.env.example` for the authoritative, commented list.

## 5. Docker Setup

The simplest way to start the backend is `./start.sh` from the repo root (see [Quick Start](#1-backend-one-command)) — it wraps exactly the steps below and also prints the right URL for the Android emulator and, if reachable, a physical device.

1. **(Optional)** copy the environment template if you want to customize anything (a different port, real SMTP credentials, etc.):
   ```bash
   cp .env.example .env
   ```
   This step can be skipped entirely — `docker-compose.yml` falls back to the same fixed, publicly-committed development-only `JWT_SECRET`/`ENCRYPTION_MASTER_KEY` that `application.properties` itself uses when nothing else is configured (safe for local review/testing, since no real user data is ever protected by them), so `docker compose up` works with no `.env` file at all. Generate and set your own values in `.env` instead for any shared or production use (see [Encryption](#17-encryption-phase-9) for exactly what `ENCRYPTION_MASTER_KEY` protects and its required format).
2. Start PostgreSQL and the backend:
   ```bash
   docker compose up --build
   ```
   The backend waits for PostgreSQL to report healthy (via `depends_on: condition: service_healthy` plus a Hikari connection retry) before it starts serving traffic, and retries the database connection automatically if it isn't immediately ready. On startup it runs Flyway migrations to create/update the schema.
3. The backend is now available at `http://localhost:8080`.

No manual installation of PostgreSQL is required — it runs entirely inside the `postgres` container, and its data persists in the `postgres_data` Docker volume. Uploaded profile pictures persist in the `profile_storage` Docker volume, mounted at `/app/storage` inside the backend container — both volumes survive `docker compose down` / container recreation (only `docker compose down -v` removes them).

By default `EMAIL_PROVIDER` is `log`, so Compose works out of the box without any SMTP setup — verification/reset codes are printed to `docker compose logs backend` instead of emailed. Set `EMAIL_PROVIDER=smtp` plus the `SMTP_*` variables in `.env` to send real email instead.

**On Windows/WSL2**, running the backend via Docker Compose (as above, or via `./start.sh`) also sidesteps a networking problem that running it directly inside WSL2 does not: WSL2's own internal IP address can change on every Windows/WSL restart, so a Windows-side port forward (`netsh interface portproxy`) aimed at that IP would otherwise need re-creating by hand each time to let a physical Android phone reach it. Docker Desktop instead publishes the container's port directly on the Windows host's own network interfaces, so there is no WSL IP involved in reaching it from another device at all — nothing to reconfigure, ever, after a restart.

**Optional: the web client too.** `docker-compose.yml` also defines a `web` service (Flutter's web build served by nginx) behind a Compose *profile*, so it's never built/started unless asked for:
```bash
docker compose --profile web up -d --build
```
Then open `http://localhost:${WEB_PORT:-8090}`. `WEB_API_BASE_URL` (default `http://localhost:8080`) is compiled into that build and must be an address a *browser* on your machine can reach the backend at — see [Deployment](#23-deployment) for the full explanation and for taking this beyond `localhost`.

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

The app opens on a **Login** screen if no session is stored, or straight into the **home shell** if a valid session was previously saved. From Login you can register a new account or tap **Forgot password?**.

**On a phone-width window** (below 900 logical pixels), the home shell is a hub screen: a top bar with the brand mark, a dark/light theme toggle, a profile avatar button, and **Log out**; below that, a welcome message, an unverified-email notice with a **resend** action if applicable, two navigation cards (**Chats**, with an unread-count badge, and **Contacts**, with a pending-invitation badge), and a short **Recent chats** preview list. **At 900 logical pixels or wider**, the same account instead gets the three-pane `DesktopShell` — see [§22](#22-web-responsive-layout--two-chat-desktop-view).

Note what this screen deliberately does **not** show: there is no "Connected"/"Connection failed" backend-status indicator anywhere in the UI. An earlier phase's health check (`GET /api/health`, still implemented server-side — see [§7](#7-how-to-start-the-backend)) is intentionally not surfaced to the end user as connectivity text; a real widget test (`home_screen_test.dart`, *"never shows backend/server/technical status in the UI"*) asserts exactly that. If the backend is unreachable, the screens that actually need data (chats, contacts, profile, ...) show their own error state with a **Retry** button instead of a generic global banner.

## 9. How to Run Tests

Backend tests (health, auth, profile, email verification, password reset, and contacts/invitations integration tests — see [Testing](#24-testing) below) run against a real PostgreSQL database:
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

Verification and password reset are both **code-based**, not link-based: the user is emailed a short-lived 6-digit numeric code and types it directly into the app. There is no clickable link to tap, so there's nothing that depends on an email client recognizing a custom URL scheme.

- **On registration**, the backend generates a single-use 6-digit verification code, stores only its SHA-256 hash (never the raw code), and emails it. The code is valid for 24 hours.
- **A newly registered (or logged-in) account cannot use the app until its email is verified.** `EmailVerificationGateFilter` blocks every authenticated request from an unverified account except the auth endpoints themselves (`/api/auth/me`, `/verify-email`, `/resend-verification`, plus the public ones) with a `403`; the Flutter app's router mirrors this by redirecting an unverified user straight to the code-entry screen, so in practice the block is never actually hit through the UI.
- `POST /api/auth/verify-email` (authenticated - the code alone isn't enough to identify whose it is) checks the submitted code against the account's pending one and marks the account verified on a match. A wrong code, an expired (24h) code, an already-used code, or exceeding 5 wrong attempts on the same code all return the same generic "invalid or expired" error - and a wrong guess counts against that attempt limit, so the code can't be brute-forced.
- **Forgot password** (`POST /api/auth/forgot-password`) always returns the same generic message ("If that email is registered...") whether or not the address exists, and only actually sends an email for a real account - so the endpoint never reveals account existence.
- `POST /api/auth/reset-password` takes the account's email plus the 6-digit code plus the new password; the same "invalid or expired" response (and 5-attempt limit) covers a wrong code, an expired/used code, *and* an unregistered email, so this step stays enumeration-safe too. Re-validates the new password server-side with the same strong-password rule as registration.
- Requesting a new verification or reset code invalidates any previous unused code of that kind for the account (and resets the attempt count).

### Email sending: `EmailService`

`email.EmailService` is a two-method interface (`sendVerificationEmail`, `sendPasswordResetEmail`) with two implementations, selected by `EMAIL_PROVIDER`:
- **`log`** (default) — `LoggingEmailService` logs the generated code at INFO level instead of sending anything. Safe for local development and for reviewers without SMTP credentials; grep the backend's console output (or `docker compose logs backend`) for `[DEV EMAIL` to find the code.
- **`smtp`** — `SmtpEmailService` sends a real email via `JavaMailSender`/SMTP, configured entirely through environment variables (see below). It deliberately never logs the code itself, only that a message was sent and to which masked address, so a live code can never leak into production logs.

Registration/resend/forgot-password never fail just because the email provider is temporarily unreachable - the code is still created (and can be resent later); the send failure is only logged as a warning.

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

None of these are hardcoded anywhere in source; see `.env.example` and `application.properties`.

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

Conversations now carry real text messages, sent and received live over WebSocket/STOMP, with sent/delivered/read status, edit, delete, and typing indicators. Images/video are Phase 8, end-to-end/at-rest encryption is Phase 9, and push notifications are not implemented — none of that is implemented here. (Voice messages did ship later, alongside images/video — see [§16](#16-image-video--voice-attachments-phase-8).)

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

## 16. Image, Video & Voice Attachments (Phase 8)

Messages can now carry an image or a video, with or without accompanying text - a message is valid as long as it has text content, at least one attachment, or both. Media processing (image resizing, thumbnails) is deliberately kept to `javax.imageio`, already used elsewhere in this codebase (see [Profile Feature](#11-profile-feature)'s avatar validation) - no new image/media-processing library was added.

### Data model

**`MessageAttachment`**: `id`, `conversationId`, `messageId` (nullable), `uploaderId`, `type` (`IMAGE`/`VIDEO`/`AUDIO`), `storageKey`, `thumbnailStorageKey` (nullable), `originalFilename` (nullable), `mimeType`, `fileSize`, `width`/`height` (nullable), `durationSeconds` (nullable), `createdAt`.

> **Note on phasing:** the `AUDIO` attachment type (voice messages) was added after this phase was originally written, reusing the exact same upload/storage/security pipeline described below with no structural change - see [Voice messages](#voice-messages) further down for what's specific to it. Older text in this section that only mentions "image or video" predates that addition.

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
- **Audio (voice messages)**: WAV/RIFF only (`RIFF....WAVE`) - specifically mono, 16kHz, the exact format the Flutter app's recorder is configured to produce (`AudioEncoder.wav`), chosen because its magic bytes are unambiguous against the video formats above (unlike an AAC-in-MP4 `.m4a`, which would collide with the video detection).

Size limits are configurable (`app.attachments.max-image-size-bytes` / `app.attachments.max-video-size-bytes` / `app.attachments.max-audio-size-bytes`, defaulting to 10MB/50MB/15MB) and enforced *after* the type is sniffed, so each media kind can have its own cap. The global `spring.servlet.multipart.max-file-size`/`max-request-size` ceiling was raised from 5MB/6MB to 55MB/56MB to accommodate the video limit - the existing 5MB avatar limit is unaffected, since it's enforced separately in `ProfileService` regardless of this higher ceiling.

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

### Voice messages

A voice message is an `AUDIO` attachment sent the same way as an image or video (upload-then-attach, above) - no separate endpoint or message type.

- **Format**: WAV, mono, 16kHz (`record` package, `AudioEncoder.wav`) - see [Validation](#validation) above for exactly why this format was chosen.
- **Recording (Flutter)**: tapping the composer's mic button (`ChatRoomController.startRecordingAudio`) replaces the composer with a live recording row - a per-second elapsed-time counter, a pulsing "recording" indicator, and explicit **cancel** (discards the recording) and **stop-and-send** actions; stopping uploads the recorded file through the same attachment pipeline as any other media, then sends it as the message's only attachment.
- **Size limit**: 15MB by default (`app.attachments.max-audio-size-bytes` / `ATTACHMENT_MAX_AUDIO_SIZE_BYTES`), enforced the same way as image/video limits above. There is no separate recording-duration cap enforced client-side; at mono 16kHz WAV's roughly 32KB/s, the size limit is the practical ceiling (a little over 7 minutes).
- **Playback**: a voice message renders as a compact inline player in the message bubble (`audioplayers` package) with a play/pause button and its duration - no waveform.
- **Thumbnails**: not applicable - `thumbnailStorageKey`/`thumbnailUrl` are simply absent for an audio attachment, exactly like a video without server-side frame extraction (see [Thumbnails](#thumbnails) above).
- **Encryption/security**: identical to every other attachment - the file bytes are encrypted at rest by the same `FileStorageService` (see [Encryption § Media](#17-encryption-phase-9)), and the same `AttachmentService.requireAccessible` participant/deletion checks apply (see "Security / IDOR protection" immediately below).

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

The key is a single **Base64-encoded 256-bit (32-byte) AES key**, read from `app.encryption.master-key` (env var `ENCRYPTION_MASTER_KEY`) - never hardcoded in source, on either the Java or Flutter side, and never committed to git (`.env` is gitignored). This follows the exact same env-var pattern already established for `JWT_SECRET`, with one deliberate difference: **the key is validated strictly at construction time** - `EncryptionService`'s constructor Base64-decodes the value and throws `IllegalStateException` immediately (failing application startup) if it's missing, isn't valid Base64, or doesn't decode to *exactly* 32 bytes. It is never silently truncated or padded to fit. Both `application.properties` and `docker-compose.yml`/`.env.example` carry the same fixed, publicly-committed development-only default (clearly commented as such everywhere it appears) so `./mvnw test`/`./mvnw spring-boot:run` and `docker compose up` (see [Docker Setup](#5-docker-setup) above) all work out of the box with zero setup - this default is not a secret (it protects no real user data) and is exactly the same posture as the existing `JWT_SECRET` default. **Always generate and set a real value in `.env` for any shared or production use** (`openssl rand -base64 32`). The key is never logged, and no exception message in the encryption code path ever includes the key or any plaintext value.

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

**Download/streaming** (`AttachmentController.download`): unchanged authorization - `AttachmentService.requireAccessible` still runs first, exactly as in Phase 8 (see [Image, Video & Voice Attachments § Security](#16-image-video--voice-attachments-phase-8) above) - only *after* that succeeds does the controller parse the `Range` header (still via Spring's own `HttpRange`) and call `AttachmentService.loadRange(attachment, start, end)`, which decrypts and returns exactly the requested byte range. The response is still `206 Partial Content` with a correct `Content-Range`/`Content-Length` header for a ranged request, or `200 OK` with the full (decrypted) file otherwise - from the Flutter video player's perspective, seeking behaves identically to Phase 8.

**Thumbnails** are stored through the exact same `FileStorageService.store`/encrypted-container path as any other file - there is no separate, unencrypted thumbnail code path.

**Trade-off, stated plainly:** true byte-exact random access into a single encrypted stream (decrypting only the literal bytes requested, with zero chunk-boundary overhead) is not possible with a single-shot AEAD cipher without either (a) a much more complex incremental-AEAD/streaming construction, or (b) giving up per-chunk authentication. The 1 MiB chunking above is the practical middle ground: internal decryption happens in whole-chunk units (so a range request for one byte still decrypts up to ~1 MiB around it), but the **response returned to the client is still byte-exact** to what was requested, and a video is never fully decrypted into memory just to serve a seek - verified by `AttachmentEncryptionIntegrationTest.rangeRequestReturnsExactRequestedSliceOfTheDecryptedVideo`, which uploads a 3MB file (spanning multiple chunks) and requests a range straddling a chunk boundary.

### Migration (`V8__encrypt_message_and_profile_content.sql`) and pre-existing data

`V1`–`V7` are untouched. `V8` only widens `messages.content`, `users.about_me`, and `message_attachments.original_filename` from `VARCHAR(n)` to `TEXT` (no data rewritten - Postgres has no storage-cost difference between the two for existing values). It does **not** and *cannot* encrypt existing plaintext rows itself, because encryption requires the master key, which only the running application has access to, not a SQL migration.

Instead, `security.encryption.LegacyPlaintextMigrationRunner` (a Spring `ApplicationRunner`) runs once on every application startup and encrypts any row it finds that isn't already validly encrypted: for each candidate row, it tries `EncryptionService.decrypt()` on the stored value - if that succeeds, the row is already encrypted and is left untouched; if it fails (the value doesn't parse as a version/nonce/GCM-tag envelope, which any real pre-Phase-9 plaintext value won't), the runner encrypts it in place via a direct SQL `UPDATE` and moves on. This is safe to run on every startup (idempotent - an already-migrated database does one cheap decrypt-and-skip pass per row) and never deletes or blanks a row it can't process (an unexpected per-row failure is logged - without ever logging the plaintext value - and that one row is skipped rather than aborting startup). This satisfies "never leave old rows crashing the app, never silently destroy data" without needing a Flyway Java migration (which would need its own, separate way to reach the Spring-managed `EncryptionService` bean). Verified by `LegacyPlaintextMigrationRunnerTest`: a raw plaintext value inserted directly via JDBC (simulating a pre-Phase-9 row) is encrypted in place on the next run, an already-encrypted row is left byte-for-byte unchanged on a second run, and this works for both `users.about_me` and `messages.content`.

### Error handling

`EncryptionException` (and its subtype `DecryptionException`) follow the existing `GlobalExceptionHandler` pattern (see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8) and earlier phases): a dedicated `@ExceptionHandler` catches them and returns a generic `500` ("Unable to process encrypted data") that never includes the key, plaintext, or ciphertext. One subtlety specific to the JPA-converter approach: when `EncryptedStringConverter.convertToEntityAttribute` throws while Hibernate is hydrating an entity, Hibernate/Spring wrap it in a `JpaSystemException` rather than surfacing the `DecryptionException` directly - `GlobalExceptionHandler.handleJpaSystemException` unwraps the cause chain to recognize this specific case and still returns the same safe message (rather than falling through to the unrelated generic "unexpected error" wording used for other persistence failures). Nothing in this code path ever logs plaintext content or key material - verified by `EncryptionSecurityIntegrationTest.decryptionFailureNeverLogsPlaintextOrTheEncryptionKey`, which attaches a Logback `ListAppender` to the root logger, triggers a tamper-induced decryption failure, and asserts the captured log output contains neither the secret message text nor the (untampered) ciphertext value.

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
Both return only Base64-encoded ciphertext envelopes (or `NULL`), never readable text - confirmed against this repository's own test database while implementing this phase; not shown here since this sandbox's Postgres has no persistent data outside test transactions (every integration test's writes are rolled back at the end of the test, by design - see [Testing](#24-testing) below), and no real user data was ever left behind for a screenshot.

### Known limitations

- **Media range-request granularity**: as described above, internal decryption happens per 1 MiB chunk, not per exact byte - a stated, deliberate trade-off, not a bug. The externally-visible behavior (the exact bytes returned for a given `Range` header) is still byte-exact and fully tested.
- **`username`/`email` stay plaintext**: by explicit scope decision (see the table above), not an oversight - encrypting them would require a redesigned searchable-hash approach for login/uniqueness/contact-search that this phase's requirements don't call for.
- **Legacy-data migration is best-effort, not cryptographically provable as complete**: `LegacyPlaintextMigrationRunner` distinguishes "already encrypted" from "plaintext" by attempting to decrypt and checking for a `DecryptionException` - astronomically reliable in practice (forging a value that both looks like real data and happens to pass GCM tag authentication is a ~2⁻¹²⁸ event), but not a mathematical proof for every conceivable legacy value.
- **No key rotation**: `ENCRYPTION_MASTER_KEY` is a single, static key for the whole database - rotating it would require decrypting every protected value with the old key and re-encrypting with the new one (a real but reasonably mechanical addition; not implemented here as it wasn't part of this phase's requirements).

### School rubric status

| Requirement | Status | Evidence |
|---|---|---|
| Messages, media, chat-list content encrypted before reaching the database | **FULLY SATISFIED** | `MessageContentEncryptionIntegrationTest`, `AttachmentEncryptionIntegrationTest` (direct DB/disk inspection); see table above for exactly which fields and why. |
| Profile information encrypted before reaching the database | **PARTIALLY SATISFIED, precisely scoped** | `ProfileEncryptionIntegrationTest` proves `about_me` (free-text profile content) and the profile picture's bytes are encrypted, exactly like message text. **`username` and `email` are deliberately plaintext** — see the field-by-field table above for why (login lookup, uniqueness constraints, contact search all need to run against them as plaintext). If "profile information" is read to include login identifiers, this line is not fully satisfied; if it's read as "user-authored profile content," it is. Stated here explicitly rather than assumed either way. |
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

## 18. Sessions & Multi-Device

Every login (`POST /api/auth/login` or `/register`) creates an `AuthSession` row (`id`, `userId`, `deviceLabel`, `createdAt`, `revokedAt`) and stamps its id into the JWT as a `sid` claim, alongside the usual subject/expiry. `JwtAuthenticationFilter` looks the session up on every request and rejects the token (`401`) the moment `revokedAt` is set — logging out (or a session being revoked from elsewhere) takes effect immediately, server-side, not just by the client forgetting its token. A JWT issued before this phase (no `sid` claim) is still honored until it naturally expires, so no one is logged out by the upgrade itself.

- **`deviceName`** is an optional field on login/register (`"Android"`, `"Web"`, `"iOS"`, ...); the Flutter app fills it in automatically (`core/platform/device_label.dart`) so a user never has to name their own device.
- `GET /api/auth/sessions` lists the caller's own sessions (`id`, `deviceLabel`, `createdAt`, `current` — whether it's the one making this very request), for a "manage your sessions" view.
- `DELETE /api/auth/sessions/{id}` revokes one of the caller's *own* sessions (including the current one — that's just "log out this device" from another session's point of view); it never accepts another user's session id (`404`).
- `POST /api/auth/logout` revokes the session belonging to the token making the request (Flutter's own logout button uses this, not the delete-by-id endpoint, since it only ever needs to end its own session).

**Selective logout, concretely:** the same account can be signed in on a phone and in a browser (or two browser tabs under two different device names) at once; ending one session — via its own logout button, or by deleting it from another session's list — leaves every other session's token valid and its WebSocket connection open. Verified end-to-end in `AuthSessionControllerIntegrationTest` and in `CrossPlatformSyncIntegrationTest` (a phone-style and a browser-style connection held open simultaneously by the same account, with one ended while the other keeps working).

**Client-side:** ending the *current* session from within the app itself (`AuthController.logout()`) clears the stored token and returns to the login screen immediately — it does not wait for the server round trip, which happens in the background. If a session is ended *from elsewhere* while the app is still open with that now-dead token, the very next API call gets `401`; `dio_provider.dart`'s response interceptor catches that specific case (an `Authorization` header was present and the server said `401`) and calls `AuthController.handleSessionExpired()`, which signs the app out and shows *"Your session has expired. Please log in again."* on the login screen — a real, user-visible distinction from a plain login failure, not a silent redirect.

**WebSocket authentication, both ways:** a native (Android/iOS) socket connection sends the JWT as a normal `Authorization: Bearer <token>` header on the handshake, exactly like every REST call. A **browser** WebSocket cannot set arbitrary headers on its handshake at all — the token instead travels as a `?access_token=` query parameter, accepted by `JwtAuthenticationFilter` **only** for the `/ws` handshake path; an ordinary REST call carrying the same query parameter is still rejected (verified in `AuthSessionControllerIntegrationTest.theQueryStringTokenIsNotAcceptedOutsideTheWebSocketHandshake` and `GroupWebSocketIntegrationTest.aHandshakeWithAnInvalidQueryTokenIsRefused`), so this is not a general query-token bypass. `ChatWebSocketClient` picks whichever transport its platform actually needs — `kIsWeb ? websocketUrlWithToken(token) : websocketUrl` with the header set only on native — so the rest of the app's WebSocket-handling code is identical on both platforms.

## 19. Group Chats & Group Invitations

Group chats reuse the existing `conversations`/`conversation_participants` tables rather than a parallel schema: `Conversation.type` is `DIRECT` or `GROUP` (a database `CHECK` constraint enforces the right columns are null/non-null for each — a direct chat's pair columns are null for a group and vice versa), and a group additionally has an encrypted `name`, a `createdBy`, and each participant a `role` (`ADMIN`/`MEMBER`). The group's creator is its one admin; there is currently no promote/demote or ownership-transfer action.

- **`POST /api/groups`** — `{name, memberIds}`. Creates the group (creator as `ADMIN`, already a member) and a `GroupInvitation` per listed id. Every id must be one of the creator's own *accepted* contacts (`400` otherwise, `"You can only invite your own contacts"`) — you cannot add a stranger straight into a group any more than you could message one directly.
- **`GET /api/groups/{id}`** — the group's members, roles, and pending invitees; `404` for anyone not a current member (never leaks a group's existence or membership to an outsider).
- **`POST /api/groups/{id}/invitations`** — any current member can invite more of *their own* contacts; already-a-member and already-invited ids are silently no-ops rather than errors, so re-submitting a selection is harmless.
- **`GET /api/groups/invitations/pending`** / **`.../accept`** / **`.../decline`** — an invitation is per-invitee and independent of every other invitee's; accepting adds you as a `MEMBER` and broadcasts `MEMBER_JOINED` to the group's live topic; declining leaves no trace of membership and does not block being invited again later (same reasoning as the individual-invitation reverse-direction design in [§13](#13-contacts--chat-invitations)).
- A message sent to a group fans out to every current member; **delivered/read status is aggregated per group message** via `message_receipts` (one row per non-sender member) rather than the single `status` column a direct message uses: the message only becomes `DELIVERED` once every member who was already in the group when it was sent has acknowledged it, and `READ` once all of them have — a member who joins *after* a message was sent is simply not counted for it, so a late joiner can never hold a group's read receipts back forever.
- Unread counts differ for the same reason: a direct chat counts messages not yet `READ`; a group chat counts, per member, messages that member specifically hasn't read (`GroupReceiptService`/`MessageRepository.countUnreadInGroups`).
- **Real-time events** on `/topic/chats/{id}` gain `MEMBER_JOINED` (broadcast to the group) and `POLL_UPDATED` (see [§21](#21-polls)); a member's own personal `/topic/users/{id}/invitations` feed gains `NEW_GROUP_INVITATION` and a shared `INVITATION_RESOLVED` event (kind `CONTACT` or `GROUP`) sent to **both** parties of an individual or group invitation the moment it's accepted or declined — so a second open session (another tab, another device) drops it from "pending" and, if accepted, picks up the new contact/chat without polling. Every event that changes visible state is emitted only **after** its transaction commits (`AfterCommit.run`), so a fast client that reacts to the event can never race ahead of the very data the event is about.
- The Flutter chat list, chat screen, chat-info panel, "New group" dialog, and pending-invitations tab all treat groups and individual chats through the same `ChatSummary`/`Message` models (`type`, nullable `otherUser` vs. `name`/`memberCount`) rather than a parallel group-specific UI stack — see [`chat_summary.dart`](mobile_messenger/lib/features/chat/domain/chat_summary.dart) and [`group_providers.dart`](mobile_messenger/lib/features/group/group_providers.dart).

## 20. Message Search

`GET /api/chats/{id}/messages/search?q=...` searches one chat's (individual or group) message text, case-insensitively, and returns matches oldest-first plus a `truncated` flag.

**Why this can't be a SQL `LIKE`:** message text is encrypted at rest with AES-256-GCM using a fresh random nonce on every write (see [§17](#17-encryption-phase-9)) — the same plaintext never produces the same ciphertext twice, so there is no ciphertext pattern the database could ever match against without either storing a separate searchable-but-weaker index (defeating the point of the encryption) or decrypting server-side. `MessageService.searchMessages` instead reads the chat's history in batches of 500 (newest first), decrypting each batch via the same JPA converter every other read already uses, and matches in memory; it stops as soon as it has the 200 most recent matches (`MAX_SEARCH_RESULTS`), setting `truncated` if there was more. This is linear in the chat's length, which is an accepted trade-off at this scale rather than a design meant to scale to enormous histories — a real search index would need genuinely different (searchable) encryption, out of scope here.
- A blank or over-length (>100 char) query is rejected (`400`); search is scoped strictly to participants of that one chat (`404` for anyone else, exactly like every other chat endpoint); a deleted message is never returned even if its since-overwritten content would have matched; editing a message makes it findable by its *new* text and not its old text, immediately.
- Search never mutates the chat: no read receipts are affected, no messages are (re)loaded into the chat's own paginated history, and the chat-list preview/unread count are untouched — confirmed in `MessageSearchIntegrationTest.searchDoesNotChangeTheChatItself`.
- **Flutter (`chat_search_providers.dart` / `ChatSearchController`):** a per-chat, `autoDispose.family` search state entirely separate from the chat's own message state — opening, searching, and closing search never reloads or otherwise touches the conversation. Typing debounces (350ms) before calling the API; results start on the **most recent** match; **Previous**/**Next** step through matches and **wrap around** at both ends; selecting a result scrolls the chat there, transparently loading older history first if the match isn't in the currently-loaded page (`ChatRoomController.ensureMessageLoaded`); matched text is highlighted inline (`HighlightedText`) wherever it appears, including in the chat-info panel's result list on the desktop layout. Handles zero matches, one match, many matches, and clearing back to no query, all without losing the chat's own scroll position or state.

## 21. Polls

A poll lives inside a group chat as an ordinary message whose content is the poll's question (`polls`/`poll_options`/`poll_votes` tables, `PollService`) — it sorts the chat list, appears in the timeline, is found by search, and is deleted like any other message; deleting its message also deletes the poll (`ON DELETE CASCADE`) and permanently blocks further votes.

- **`POST /api/chats/{id}/polls`** — `{question, options: [2..10 strings], anonymous}`; group chats only (`400` in a direct chat). Options must be non-empty, ≤200 characters, and pairwise different (case-insensitive).
- **`PUT /.../vote`** — `{optionId}`; **`DELETE /.../vote`** retracts it. One vote per user per poll (`UNIQUE(poll_id, user_id)`); voting again with a different option *changes* the existing vote rather than adding a second one — a poll's total vote count can never exceed its member count. Both actions work identically for an anonymous poll: even an anonymous poll must remember *who* voted, in order to let that person change or retract their own vote later — anonymity is about what *other* users can see, never about the voter losing control of their own vote.
- **Public vs. anonymous**, precisely: a public poll's `PollOptionResponse.voters` lists everyone who chose that option; an anonymous poll's is `null` (never an empty list, which would be indistinguishable from "nobody voted yet") for every viewer, including the poll's own creator — vote *counts* are always visible either way, only *who* is withheld.
- **Personal, not broadcast, results:** a poll response's `myOptionId` is specific to whoever asked — the `POLL_UPDATED` WebSocket event itself carries only `{pollId, messageId}`, nothing about the vote or the tally (confirmed in `GroupWebSocketIntegrationTest.aPollUpdateReachesTheWholeGroupWithoutRevealingAnyVote`), so each connected client refetches the poll for its own personal view rather than the server ever broadcasting one client's vote to everyone else's screen.
- Option text is encrypted at rest the same way message text is (`EncryptedStringConverter`) — confirmed in `PollControllerIntegrationTest.optionTextIsEncryptedAtRestButReadableThroughTheApi` by reading the raw `poll_options.text` column directly.
- **Flutter:** `CreatePollDialog` (question, 2–10 dynamically add/removable options, an anonymous toggle) is reachable from the composer only in a group chat; each poll renders as a `PollBubbleContent` inside the message bubble — tap an option to vote for it (or, tapping your own current choice, to retract it instead), see live per-option progress bars and counts, and (public polls only) who chose what; a `POLL_UPDATED` event silently refreshes just that poll's card in place.

## 22. Web Responsive Layout & Two-Chat Desktop View

The phone layout (a `Scaffold` per screen, pushed on go_router's stack — Login, Chats, a chat, Contacts, Profile, ...) is completely unchanged; nothing in it was rewritten to build the desktop layout, and every phone-specific widget test in the existing suite still passes against it untouched. A new `DesktopShell` (`lib/features/shell/presentation/desktop_shell.dart`) is offered *alongside* it, and `AppRoot` — the widget shown at `/` once logged in — chooses between them with a single `LayoutBuilder`: **at or above 900 logical pixels wide** (`desktopBreakpoint`), `DesktopShell`; below it, the original `HomeScreen`. Resizing the browser window crosses that line live, no reload, no lost state on either side of the switch.

`DesktopShell` is a three-region `Row`:
- **Left** (fixed 340px) — your profile/avatar, **New group**, **Archived chats**, and **Log out**, then four tabs: **Chats** (the same chat list, filterable by a search box, each row offering "open" and "open side by side"), **Contacts**, **Invites** (contact *and* group invitations together, each unread-badge-counted), and **Find** (the contact search tab). Everything here is the same `ChatListView`/`ContactsTab`/`PendingInvitationsTab`/`FindPeopleTab` widgets the phone layout's screens already used, parameterized for embedding rather than duplicated.
- **Centre** — the active chat (`ChatPanel`, the same conversation UI factored out of the old full-screen `ChatScreen`, which is now just `ChatPanel` plus an `AppBar` for the phone case), or **two chats side by side** when the window is wide enough (`WorkspaceController`, capped at two panels — opening a third replaces the *primary* one, matching a predictable "most recent replaces the oldest" rule) and empty otherwise, with a placeholder inviting you to pick a chat.
- **Right** — a `ChatInfoPanel` (a direct chat's other-user details, a group's member/invitee list with an **Invite contacts** action, and/or the current in-chat search's result list) shown when there's room next to however many chat panels are already open; on a narrower-but-still-desktop window where it wouldn't fit, the same panel opens in a dialog instead of being silently dropped.

Each open chat panel keeps its **own independent** `ChatRoomController` — its own WebSocket subscription, its own typing state, its own search state — so a message, a typing indicator, or a poll vote in one panel's chat is confirmed (via `FakeBroker`-backed tests simulating the real per-destination STOMP fan-out) to never leak into the other panel showing a different chat. Sending, editing, deleting, searching, and voting all work identically and independently in either panel.

### Visual design system

The UI follows one centralized design system in `mobile_messenger/lib/core/theme/` (nothing about behaviour, the API, auth or encryption is affected by it):

- **`app_colors.dart`** — `AppColors`, a `ThemeExtension` read anywhere as `context.colors`: semantic roles (`background`, `surface`, `surfaceElevated`, `surfaceHover`, `surfaceSelected`, `primary`/`primarySoft`/`primaryStrong`, `accentYellow`/`accentRed`/`accentGreen`, `success`/`warning`/`error`/`info`, `textPrimary`/`textSecondary`/`textMuted`/`textOnPrimary`, `border`, `divider`, bubble colours) for a dark theme (default) and a light theme. The direction is a deep green-tinted graphite foundation with a warm gold action colour; **gold** = primary action/active/selected, **red** = unread, failed and destructive, **green** = alive/success/delivered/read. Status is always paired with an icon or a label, never colour alone. The palette is checked for WCAG AA text contrast in `test/core/theme/app_theme_test.dart`.
- **`app_tokens.dart`** (spacing, radii, durations, layout widths, shadows), **`app_typography.dart`** (the Inter type scale — the font is bundled under `assets/fonts/`, SIL OFL licence included — no font package needed), **`app_theme.dart`** (builds a complete `ThemeData` from the palette so every stock Material widget already inherits the brand) and **`theme_mode_provider.dart`** (dark/light toggle in the desktop rail and on the phone home screen).
- Shared building blocks in `lib/core/widgets/`: `AppSurface`, `CountBadge`/`StatusPill`, `AppEmptyState`/`AppErrorState`/`AppBanner`, `AppSectionHeader`, skeleton loaders (`ListSkeleton`, `MessagesSkeleton`, `ProfileSkeleton`), `HoverReveal` (secondary actions appear on hover/focus for mouse users and are always visible on touch), `BrandMark`, `AmbientBackground`.

The desktop shell is a slim navigation rail plus floating rounded panes over one ambient backdrop; on a phone, home is a hub with recent chats and Chats/Contacts entry cards. No new pub dependencies were added.

## 23. Deployment

### Status (read this first)

| | |
|---|---|
| **Current deployment target: Railway** (see "Railway Deployment" immediately below) | The three services (PostgreSQL, backend, web) map directly onto Railway's model — a managed Postgres plugin plus two Dockerfile-built services, each already present unmodified in this repository (`backend/Dockerfile`, `mobile_messenger/Dockerfile`). |
| The application reachable from the public Internet | **NOT YET DONE from this environment.** Creating and configuring the actual Railway project needs a Railway account, which only you can create. Nothing here should be read as "deployed" until the project is created on Railway and the verification checklist passes from a different network. |
| Self-hosted VPS (Caddy + `docker-compose.prod.yml`) | Kept as a documented **alternative** below — fully prepared and verified locally in an earlier pass, but not the current target. |

### Railway Deployment

**Architecture** — three separate Railway services in one Railway project, each independently deployed and independently scaled:

```
Railway project
├── PostgreSQL        (Railway's managed plugin — private/internal only, no public networking)
├── Backend            (built from backend/Dockerfile — gets its own public HTTPS domain)
└── Web                (built from mobile_messenger/Dockerfile, nginx — gets its own public HTTPS domain)
```

This is a genuine change from the VPS/Caddy layout further below: there, one Caddy instance gives the backend and the web app *one shared* public origin. On Railway, **Backend and Web are two separate services with two separate public domains** — there is no single shared origin, and no Caddy (or any other reverse proxy) is needed or used, because Railway itself terminates HTTPS and assigns a certificate to each service's public domain automatically.

- **PostgreSQL is private/internal**: Railway's Postgres plugin is reachable only from other services in the same Railway project over its private network, never from the public Internet — matching this repo's existing assumption that the database is never directly exposed (the local/VPS setups never publish 5432 outside their own Docker network either).
- **Backend connects to that Postgres** using Railway's own **reference variables** — Railway lets one service's environment variable read another service's value with `${{ServiceName.VARIABLE}}` syntax. Conceptually (substitute your actual Postgres service's name if it isn't `Postgres`):
  ```
  DB_HOST=${{Postgres.PGHOST}}
  DB_PORT=${{Postgres.PGPORT}}
  DB_NAME=${{Postgres.PGDATABASE}}
  DB_USERNAME=${{Postgres.PGUSER}}
  DB_PASSWORD=${{Postgres.PGPASSWORD}}
  ```
  This works because `spring.datasource.url` is built from the discrete `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USERNAME`/`DB_PASSWORD` variables (`application.properties`), **not** a single `DATABASE_URL` connection string — Railway's Postgres plugin exposes both forms, but this backend needs the discrete ones wired up as above, not just `DATABASE_URL` pasted in as-is.
- **Backend's own port**: no configuration needed. `server.port=${SERVER_PORT:${PORT:8080}}` already falls back to Railway's automatically-injected `PORT` variable if `SERVER_PORT` isn't set — this is existing, already-tested code, not something added for Railway.
- **Web uses Backend's public domain.** The web service is a **static build**, not a server that reads environment variables at runtime — `API_BASE_URL` is a Dart *compile-time* constant, baked into the JavaScript when the image is built (see `mobile_messenger/Dockerfile`'s `ARG API_BASE_URL` / `--build-arg`). On Railway this means setting `API_BASE_URL` as a **build-time** variable/argument for the Web service, pointed at the Backend service's own public Railway domain, e.g. `https://<backend-service>.up.railway.app` (or a custom domain, if one is attached) — never the Web service's own domain, and always `https://`, never `http://`, since a page served over HTTPS cannot call an insecure API. **Any time the backend's public URL changes, Web must be rebuilt**, not just restarted.
- **CORS**: because Backend and Web are on two different domains, this is a genuinely cross-origin setup (unlike the VPS's single-Caddy-origin design). `CORS_ALLOWED_ORIGINS` on the **Backend** service must be set to the **Web** service's exact public HTTPS origin (scheme + host, e.g. `https://<web-service>.up.railway.app`, no trailing slash). This one variable covers both plain REST CORS (`SecurityConfig`) and the WebSocket handshake's origin check (`WebSocketConfig`) — both read the same `app.cors.allowed-origins` property, so there is nothing else to configure for either.
- **WebSocket over HTTPS/WSS**: the Flutter client always derives the WebSocket URL from `API_BASE_URL` itself (`wss://<backend-domain>/ws?access_token=...` on the web, an `Authorization` header on native — see [§18](#18-sessions--multi-device)) — it connects **directly to the Backend service's own domain**, not through the Web service/nginx at all. Railway upgrades a WebSocket connection over HTTPS transparently on the Backend service's assigned domain, the same as any other HTTPS request to it; no separate configuration is needed beyond Backend actually being reachable at that domain.
- **Caddy is not used on Railway** — it exists in this repository specifically for the single-origin VPS layout below, where one process needs to terminate HTTPS for two backend containers sharing one hostname. Railway does that job itself, per service, so `Caddyfile`/`docker-compose.prod.yml` simply aren't part of the Railway path.
- **nginx stays exactly where it already is**: the Web service's Dockerfile still builds the Flutter web bundle and serves it with nginx (`mobile_messenger/Dockerfile`'s runtime stage) — nothing about how the static site itself is served changes on Railway; only *what fronts it with HTTPS* differs (Railway itself, instead of Caddy).
- **Persistent storage for the Backend service**: `STORAGE_ROOT_DIR` (`/app/storage` by default — see `backend/Dockerfile`) is where uploaded avatars and chat attachments are written, **encrypted**, to disk (see [§17 § Media encryption](#17-encryption-phase-9)) — PostgreSQL only ever stores a generated file name for them, never the file bytes themselves. Railway's containers do not persist a local filesystem across redeploys by default, so the Backend service needs a **Railway Volume** mounted at `/app/storage`; without one, every uploaded image/video/voice message is lost the next time the service redeploys or restarts.

#### Backend environment variables (Railway service: Backend)

| Variable | Set to |
|---|---|
| `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USERNAME` / `DB_PASSWORD` | Reference variables from the Postgres service, e.g. `${{Postgres.PGHOST}}` etc. — see above. |
| `JWT_SECRET` | A real random value — generate with `openssl rand -base64 48`. **Never** the publicly-committed local dev default. |
| `ENCRYPTION_MASTER_KEY` | A real random value — generate with `openssl rand -base64 32`. **Never** the publicly-committed local dev default, and **never changed once real data exists** — see [§17](#17-encryption-phase-9); data written under an old key becomes permanently unreadable under a new one. |
| `CORS_ALLOWED_ORIGINS` | The Web service's exact public HTTPS origin (see above). |
| `STORAGE_ROOT_DIR` | `/app/storage` (the default already baked into `backend/Dockerfile`) — just make sure a Railway Volume is mounted there. |
| `ATTACHMENT_MAX_IMAGE_SIZE_BYTES` / `ATTACHMENT_MAX_VIDEO_SIZE_BYTES` / `ATTACHMENT_MAX_AUDIO_SIZE_BYTES` | Optional — only set these to override the defaults (10MB/50MB/15MB). |
| `PORT` | **Don't set this yourself** — Railway injects it automatically, and `server.port` already falls back to it. |
| `EMAIL_PROVIDER` (+ `SMTP_*` if `smtp`) | Same as local/VPS — see [§12](#12-email-verification--password-reset) and the [Environment Variables Reference](#environment-variables-reference). |

*(No real secret values are written here — generate your own for every `openssl rand` line above; never commit the values Railway stores for you.)*

#### Web environment (Railway service: Web, build-time)

| Variable | Set to |
|---|---|
| `API_BASE_URL` | `https://<backend-domain>` — the Backend service's own public Railway domain, HTTPS, no trailing path. Must be set as a **build**-time variable (it is compiled into the static JavaScript bundle), and Web must be rebuilt whenever this changes. |

#### Verifying a Railway deployment

Once both services are up, from a device on a different network:
1. `curl -sS https://<backend-domain>/api/health` → `{"status":"ok"}` — confirms Backend is reachable, has a valid Railway-issued certificate, and can reach Postgres.
2. Open `https://<web-domain>/` in a browser: the login page loads with a padlock, tab title "Web Messenger".
3. Register an account, verify it (read the code from the Backend service's Railway logs if `EMAIL_PROVIDER=log`), log in.
4. Register a second account, make them contacts, exchange a message — it should arrive on the other side within ~2 seconds without a refresh (proves `wss://<backend-domain>/ws` works, and that `CORS_ALLOWED_ORIGINS` is set correctly, since Web and Backend are on different domains).
5. Widen the window past ~900px for the two-chat desktop layout; send a photo, then reload — it should still be there (proves the Backend service's Railway Volume is actually mounted and persisting).
6. Follow [§8 Web ↔ Mobile Synchronization](#8-web--mobile-synchronization) above with `API_BASE_URL` set to the Backend service's domain for the Android build, to confirm mobile↔web sync against the live deployment too.

### Alternative: Self-hosted VPS running the existing Docker Compose stack

Kept here as a documented alternative to Railway above, verified locally in an earlier pass. It reuses the repository's Dockerfiles and `docker-compose.yml`/`docker-compose.prod.yml` unchanged, gives real persistent disks by default, and has no platform-specific config to get subtly wrong — worth considering if Railway's managed-platform constraints (build-time env vars, per-service volumes, its own pricing model) ever stop being a good fit. Any ordinary VPS works the same way — DigitalOcean (Droplet), Hetzner Cloud, Linode/Akamai, AWS Lightsail, Vultr. A **1 vCPU / 2 GB RAM, Ubuntu 24.04** instance (about US$5–12/month) is enough; **2 GB is recommended** because the backend is a JVM and the Flutter build below is memory-hungry.

**How the pieces fit** — one public hostname, one HTTPS certificate, no CORS:

```
Browser ──HTTPS──▶ Caddy (ports 80/443, automatic Let's Encrypt certificate)
                     ├─ /api/*  ──▶ backend:8080  (Spring Boot)  ──▶ postgres:5432
                     ├─ /ws*    ──▶ backend:8080  (WebSocket, upgraded transparently)
                     └─ /*      ──▶ web:80        (nginx serving the compiled Flutter web app)
```

Only Caddy is reachable from the network. Postgres, the backend and the web container have no published ports in production (`docker-compose.prod.yml`) — this matters because Docker publishes ports by editing iptables directly, which bypasses `ufw`, so a firewall alone would *not* have hidden them.

**How the deployed web app connects to the backend:** the web bundle is built with `API_BASE_URL=https://<PUBLIC_DOMAIN>` — the *same* origin it is served from. Every REST call goes to `https://<PUBLIC_DOMAIN>/api/...` and the WebSocket to `wss://<PUBLIC_DOMAIN>/ws?access_token=...` (a browser WebSocket cannot send an `Authorization` header, see [§18](#18-sessions--multi-device)); Caddy routes those paths to the backend container. Because API and page share an origin, the browser sends no cross-origin requests at all. `API_BASE_URL` is compiled into the JavaScript, so if the hostname ever changes you must rebuild (`docker compose ... up -d --build web`).

### Accounts and credentials you need

1. **A VPS provider account** (any of the above). This needs your identity and a payment method; nobody else can create it for you.
2. **Nothing else is required.** You do **not** need to buy a domain: `<server-ip>.sslip.io` is a free public DNS name that resolves to that IP (e.g. `203.0.113.10.sslip.io` → `203.0.113.10`), and Caddy obtains a real, browser-trusted Let's Encrypt certificate for it exactly as it would for a purchased domain. If you *do* own a domain, create an `A` record pointing at the server's IP and use that name instead.
3. *(Optional, for real e-mail)* SMTP credentials — see "E-mail" below.

### Manual steps (yours)

1. Create the VPS (Ubuntu 24.04, 2 GB RAM). Add your SSH key. Note its **public IPv4 address**.
2. In the provider's firewall/security-group panel (or with `ufw`, below), allow inbound **TCP 22, 80 and 443** only. **Port 80 must be open** — Let's Encrypt validates the certificate over it.
3. Run the commands below over SSH.

### Commands (run on the server)

```bash
# 0. Once: connect and install Docker (official script; includes the Compose plugin, need >= 2.24)
ssh root@<SERVER_IP>
curl -fsSL https://get.docker.com | sh
docker compose version            # must print v2.24 or newer

# 1. Optional but recommended: host firewall (SSH, HTTP, HTTPS only)
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable

# 2. Get the code
git clone <YOUR_REPOSITORY_URL> web-messenger && cd web-messenger

# 3. Create the production configuration
cp .env.example .env
nano .env        # set the values in the table below, then save

# 4. Build and start everything (first build takes ~5-10 minutes: it compiles Flutter web and the backend)
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile prod up -d --build

# 5. Check it came up
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile prod ps
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile prod logs -f caddy   # look for: certificate obtained
```

To update later: `git pull` then repeat step 4. Data lives in the named volumes `postgres_data`, `profile_storage`, `caddy_data` and survives this. **Never** run `docker compose down -v` on the server — it deletes them.

### Environment variables (`.env` on the server; never commit this file)

Generate the secrets on the server with `openssl rand -base64 48` / `openssl rand -base64 32`.

| Variable | Set to | Notes |
|---|---|---|
| `PUBLIC_DOMAIN` | `203.0.113.10.sslip.io` (use your real IP) or your own domain | Hostname only: no `https://`, no path. **Required.** |
| `WEB_API_BASE_URL` | `https://` + `PUBLIC_DOMAIN` | Compiled into the web app. **Required.** |
| `CORS_ALLOWED_ORIGINS` | `https://` + `PUBLIC_DOMAIN` | The only browser origin allowed to call the API / open `/ws`. **Required.** |
| `DB_PASSWORD` | long random value | **Required.** Postgres and the backend both use it. Set it *before* the first start: the database is initialised with it, and changing it later needs a manual `ALTER USER`. |
| `JWT_SECRET` | `openssl rand -base64 48` | **Required.** Changing it signs every user out. |
| `ENCRYPTION_MASTER_KEY` | `openssl rand -base64 32` | **Required. Back it up. Never change it once users have data**: it encrypts messages, profile text, group names, poll options and media at rest, and data written under an old key becomes unreadable. |
| `EMAIL_PROVIDER` | `log` (default) or `smtp` | See "E-mail". |
| `SMTP_HOST` `SMTP_PORT` `SMTP_USERNAME` `SMTP_PASSWORD` `SMTP_FROM_EMAIL` `SMTP_AUTH` `SMTP_STARTTLS` | your mail provider's values | Only when `EMAIL_PROVIDER=smtp`. |

`docker-compose.prod.yml` refuses to start if any of the required ones are missing, so the stack can never silently run on the publicly-committed development defaults.

### E-mail (decide this before inviting other people)

Registration requires a 6-digit e-mail verification code. With the default `EMAIL_PROVIDER=log` the code is **not e-mailed**; it is written to the backend log, so only *you* can read it (`docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile prod logs backend | grep "DEV EMAIL"`). That is fine for a demo where you register the test accounts yourself. For anyone else to sign up on their own, set `EMAIL_PROVIDER=smtp` with real SMTP credentials (any transactional-mail provider or a Gmail app password), then `docker compose ... up -d`.

### Verify it from another computer

Do this from a device on a **different network** (your phone on mobile data, or another person's computer) — testing from the server or your own LAN proves nothing about public reachability. `<HOST>` is your `PUBLIC_DOMAIN`.

1. `curl -sS https://<HOST>/api/health` → `{"status":"ok"}`. Success also proves the certificate is valid (curl verifies it) and that Caddy → backend → database works.
2. `curl -sSI http://<HOST>/` → a `308` redirect to `https://<HOST>/` (automatic HTTP→HTTPS).
3. Open `https://<HOST>/` in a browser: the login page loads with a padlock (valid certificate), and the tab title is "Web Messenger".
4. Register an account, read its code from the log (or your inbox with SMTP), verify, log in.
5. Register a second account in a second browser / device, make them contacts, exchange messages: a message must appear on the other side **within ~2 seconds without a refresh** (this proves the `wss://` WebSocket route works through Caddy).
6. Widen the window past ~900 px: the three-pane desktop layout appears; open two chats side by side.
7. Send a photo, then reload the page: it is still there (proves the persistent volume and encrypted storage).
8. `curl -sS -m 5 http://<SERVER_IP>:8080/api/health` and `nc -zv <SERVER_IP> 5432` **must fail** (closed/timeout): only 80/443 are meant to be reachable.

When 1–8 pass, the deployment is done. Until you have run them, it is not.

### What was verified locally (no Internet server was available to me)

- `docker-compose.yml`'s default configuration is unchanged for local use (`./start.sh`, `--profile web` still validate; backend 8080 and Postgres 5432 still published).
- The production overlay: fails to start without each required variable; with them, publishes **only** ports 80 and 443 (Caddy) and none for Postgres/backend/web.
- `Caddyfile` is accepted by the real Caddy binary (`caddy validate`) and configures automatic HTTPS with an HTTP→HTTPS redirect.
- The web image builds from the repository's `Dockerfile` and nginx serves it (`index.html`, `main.dart.js`, `Cache-Control: no-cache` on the entry point).
- **The whole production stack, containerised, behind Caddy** (Postgres + backend + web + Caddy from `docker-compose.yml` + `docker-compose.prod.yml`, in an isolated Compose project, the same `Caddyfile` routes on a plain-HTTP local port): `/api/health`, the web app, `main.dart.js`, SPA deep links, `/api/*` (401 without a token) and the `/ws` path all reach the right container, only Caddy publishes a port, and the **full 29-step real-browser suite passes through it (29/29)** — same-origin REST, live WebSocket delivery under 2 s through the proxy, group chats, polls, search, two side-by-side chats, image/video/voice upload, offline failure and retry, reload persistence, and independent/revoked sessions.

**Not verifiable without a public server:** the Let's Encrypt certificate issuance itself, DNS resolution of `<ip>.sslip.io`, and reachability through your provider's network. Those are exactly what verification steps 1–3 above test.

### Notes and limitations

- The Android app can use the same server: build it with `--dart-define=API_BASE_URL=https://<PUBLIC_DOMAIN>`.
- The JWT travels in the `/ws` query string for browser sockets. Caddy does not log requests unless you enable an access log; if you add one, redact `access_token`.
- One VPS is a single point of failure and there are no automatic backups. Back up the `postgres_data` and `profile_storage` volumes and the `.env` file (in particular `ENCRYPTION_MASTER_KEY`) if the data matters.
- Other PaaS hosts (Render, Fly.io, ...) can run the same Dockerfiles the same way Railway does, but this repository was not specifically configured or tested against them.

## 24. Testing

Backend tests (JUnit + MockMvc, run against a real PostgreSQL database, each wrapped in a rolled-back transaction so they never leak data):
- **Auth** (`AuthControllerIntegrationTest`): registration success/duplicate email/duplicate username/invalid email/weak password, login success/wrong password/unknown user, `/api/auth/me` unauthenticated/authenticated.
- **Profile** (`ProfileControllerIntegrationTest`): authenticated/unauthenticated `GET /api/profile`, default (no) avatar for a new user, update success, saving an unchanged username doesn't conflict with yourself, changes persist, username/email uniqueness on update, email change resets `emailVerified`, invalid email/username rejected, About Me max length enforced, JPEG upload succeeds, PNG upload succeeds, file over 5MB rejected, unsupported file type rejected, uploaded avatar can be retrieved, avatar retrieval requires authentication.
- **Email verification** (`EmailVerificationControllerIntegrationTest`): registration creates and sends a token, valid token verifies, invalid/expired/already-used tokens all fail, resend creates a new token and invalidates the previous one, resend requires authentication, resend on an already-verified account fails, an unrelated profile update doesn't un-verify the account, changing email does.
- **Password reset** (`PasswordResetControllerIntegrationTest`): forgot-password returns an identical generic response for a known vs. unknown email (and only actually emails the known one), valid token resets the password, invalid/expired/already-used tokens fail, a second reset request invalidates the first token, weak new passwords are rejected, the password is actually changed (old password stops working, new one works), the response never includes the password, and raw tokens are never found in the database (only their SHA-256 hash, confirmed by direct repository assertions).
- **Contact search** (`ContactSearchControllerIntegrationTest`): requires authentication, matches by username, matches by email, case-insensitive, partial-substring match, excludes yourself, no results for an unknown query, too-short query rejected (`400`), results expose only safe fields.
- **Contact invitations** (`ContactInvitationControllerIntegrationTest`): requires authentication to send/list, send succeeds and appears in the recipient's pending list, duplicate pending invitation rejected, self-invitation rejected, inviting an existing contact rejected, reverse-direction invitation auto-accepts instead of erroring, recipient can accept (contact relationship created in both directions, `respondedAt` set), sender cannot accept their own invitation (`403`), an unrelated user cannot accept (`403`), an already-accepted invitation cannot be accepted again (`409`), recipient can decline, declining doesn't create a contact, sender/unrelated users cannot decline (`403`), an already-declined invitation cannot be declined again (`409`), a declined invitation doesn't block sending a fresh one, and pending invitations persist across requests.
- **Chat list & archive** (`ChatControllerIntegrationTest`): accepting an invitation creates a conversation with both users as participants, calling the get-or-create path twice never creates a duplicate, a newly created chat is non-archived for both users, `/api/chats` requires authentication, an empty chat list works, a user sees their own chats with correct other-user info, an unrelated user sees none of it, active chats sort by `lastActivityAt` descending and re-sort when activity changes, a participant can archive/unarchive their own chat (idempotently, repeatable safely), archiving moves a chat from active to archived and back for that user only (the other participant is unaffected), an unrelated user gets `404` attempting to archive/unarchive, an invalid chat ID is handled the same safe way, and archive state is independently persisted per participant (verified via direct repository assertions).
- **Messages** (`MessageControllerIntegrationTest`, 30 tests) and **WebSocket** (`ChatWebSocketIntegrationTest`, 5 tests) — see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7) above for the full breakdown.
- **Attachments** (`AttachmentControllerIntegrationTest`, 24 tests) — see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8) above for the full breakdown.
- **Encryption** (`EncryptionServiceTest`, `EncryptedChunkCodecTest`, `MessageContentEncryptionIntegrationTest`, `ProfileEncryptionIntegrationTest`, `AttachmentEncryptionIntegrationTest`, `LegacyPlaintextMigrationRunnerTest`, `EncryptionSecurityIntegrationTest`, 45 tests total) — see [Encryption](#17-encryption-phase-9) above for the full breakdown.
- **Sessions** (`AuthSessionControllerIntegrationTest`, 8 tests): the same account signed in on several devices at once, logging out one leaves the others signed in, the sessions list marks the caller's own session and shows device labels, a session can be revoked remotely from another session, a user cannot revoke someone else's session, an unverified account can still log out, the WebSocket-only `?access_token=` query parameter is rejected on an ordinary REST call, and logging out without a valid token is itself rejected — see [Sessions & Multi-Device](#18-sessions--multi-device) above.
- **Groups** (`GroupControllerIntegrationTest`, 18 tests): creating a group makes the creator its admin and invites the others, a new group appears in the creator's chat list as a group, only your own contacts can be invited, you can't invite yourself or create a group with no invitees, a group needs a name, creating a group requires authentication, an invitee sees the pending invitation and can accept it, declining doesn't make someone a member and they can be invited again, only the invitee can respond and only once, a member can invite more of their own contacts (duplicates/already-members are skipped, not errors), a non-member can't invite to or view a group, every member can send and receive group messages, a non-member and a still-pending invitee can't read or post to a group, the chat list sorts by latest message across direct chats and groups together, a group message is delivered/read only once every member has it, unread counts are tracked per member, someone who joins later doesn't hold back or see old messages as unread, and the group name is encrypted at rest but readable through the API — see [Group Chats & Group Invitations](#19-group-chats--group-invitations) above.
- **Group WebSocket events** (`GroupWebSocketIntegrationTest`, 8 tests) and **cross-platform sync** (`CrossPlatformSyncIntegrationTest`, 6 tests): an invitee is told about a group invitation immediately, every member receives group messages and joins in real time, a poll update reaches the whole group without revealing any vote, accepting/declining an invitation notifies the other party, a non-member never receives a group's events, a browser-style handshake (token in the URL) authenticates and an invalid one is refused; separately, a message sent from a browser-style session reaches a phone-style session (and the reverse) inside the 2-second live-sync requirement, the same account holds a phone and a browser socket open at once, and ending one session's socket never affects the other's.
- **Message search** (`MessageSearchIntegrationTest`, 11 tests): no match, a single match, many matches (oldest-first, case-insensitive), search works the same in a group chat, search is scoped to the requested chat only, deleted messages are never found, an edited message is found by its new text not its old text, search never changes the chat itself (unread counts, history), a blank or too-long query is rejected, a non-participant can't search, and an almost-unbounded number of matches is capped and flagged truncated — see [Message Search](#20-message-search) above.
- **Polls** (`PollControllerIntegrationTest`, 16 tests): a group member can create a poll and it shows up as a message for everyone, polls are only allowed in group chats, poll input is validated (question required, 2–10 options, no duplicates), a non-member can't create/view/vote, voting counts the vote and remembers it per viewer, a vote can be changed but counts only once, a vote can be retracted and cast again, an option from another poll can't be voted for, a public poll shows who voted for what, an anonymous poll shows totals but never who voted for what (even to its creator), an anonymous vote can still be changed/retracted by its own voter, vote state is persisted and survives a fresh reload, a deleted poll can't be voted in, a poll's question can't be edited, poll questions are searchable, and option text is encrypted at rest but readable through the API — see [Polls](#21-polls) above.
- **Message status race safety** (`MessageStatusRaceIntegrationTest`): 25 rounds of genuinely concurrent "delivered" and "read" requests (real threads, no shared transaction) for the same message always end on `READ`, never regressed back to `DELIVERED` — the fix behind the atomic conditional-`UPDATE` repository methods described in [§15](#15-text-messaging--real-time-chat-phase-7)'s status handling.
- **CORS configuration** (`CorsConfigurationIntegrationTest`, 3 tests): the configured web origin passes the CORS preflight and the WebSocket handshake, any other origin is rejected by both — see [Deployment](#23-deployment) above.

Run with `cd backend && ./mvnw test`. **296 backend tests, all passing.**

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
- `ChatRoomController` and `ChatScreen` attachment behavior — see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8) above for the full breakdown.
- `ChatSearchController` and the in-chat search UI: no query searched yet, finding several matches selects the most recent first, previous/next step through matches and wrap around at both ends (including a single-match chat), no matches is reported rather than treated as an error, a blank query clears results without calling the server, a failed search shows an error with no stale results, a slow search superseded by a newer one is discarded, closing forgets the query and results, the truncated flag is kept, the search bar opens/closes from the header, matches are highlighted with correct case preserved, previous/next jump to off-screen matches and wrap around, clearing removes the highlight, typing debounces before searching, and searching/closing never reloads or otherwise disturbs the conversation — see [Message Search](#20-message-search) above.
- Poll rendering and interaction: question/options/vote counts render, an unvoted poll shows "0 votes" with no retract option, a public poll is labelled and names voters per option, an anonymous poll is labelled and never shows voters (but still shows totals), the viewer's own vote is marked and survives reopening the chat, tapping an option votes/changes/retracts correctly, a failed vote shows an error and leaves the poll unchanged, a live `POLL_UPDATED` event refreshes the tally without disturbing other message state, a new poll from someone else appears live, creating a poll (public and anonymous) end-to-end from the composer dialog, validation (question required, 2–10 options, no duplicates, add/remove options), cancelling creates nothing, a server rejection is shown, and a poll message can be deleted but not edited — see [Polls](#21-polls) above.
- Group chats: parsing a group vs. a direct `ChatSummary` (title, preview with sender prefix, member count), groups and direct chats listed together sorted by activity with a distinct group icon, a new message re-sorts and updates the preview/unread badge, a member joining live updates the member count, the chat list can be filtered by name, creating a group (contact picker, validation, server-error handling, cancelling, chat-list reload, navigating straight to the new group), pending contact and group invitations listed in their own sections, accepting/declining a group invitation (success, failure leaves it in place), a group invitation arriving live with no refresh needed, an invitation answered elsewhere removing it here too, the combined invitations badge count, listing a group's members/invitees and inviting more contacts (excluding those already in/invited), and an error loading a group's details offering a retry — see [Group Chats & Group Invitations](#19-group-chats--group-invitations) above.
- The `WorkspaceController` powering the desktop two-chat layout: opening/replacing the primary chat, opening a second chat beside it (never more than two, oldest replaced), closing either panel (promoting the other), and the info pane opening/closing/following/detaching from its chat correctly.
- The desktop shell (`DesktopShell`) end-to-end: a wide window gets the desktop layout and a narrow one keeps the phone layout, the left pane's profile/tabs/chat-list/search render and the four tabs switch correctly, an invitation arriving live updates the badge and list, choosing a contact opens the right chat, the centre panel opens/replaces/highlights/closes a chat and can send a message, **two chats open side by side** each keep independent state (a live message, typing, and a sent message from one panel never appear in the other), narrowing the window below the two-panel threshold collapses back to one (and restores the second when there's room again), the info pane shows group members or a direct chat's details, updates live on `MEMBER_JOINED`, lists and jumps to in-chat search results, falls back to a dialog when there's no room for it, and logging out closes every open chat and ends that device's session on the server — see [Web Responsive Layout & Two-Chat Desktop View](#22-web-responsive-layout--two-chat-desktop-view) above.
- A message arriving in a chat that's open on screen is never counted as unread by the chat list (a second, independent WebSocket subscription), and correctly resumes counting once that chat is closed again.

Run with `cd mobile_messenger && flutter test`. **356 Flutter tests, all passing** (plus a clean `flutter analyze`).

### Real-browser end-to-end tests (`e2e/`)

Everything above runs against fakes (Flutter) or MockMvc (backend) — neither one actually renders the web app in a browser. `e2e/` is a separate Playwright-based suite that does: it builds the real Flutter web bundle, serves it, and drives an actual headless Chromium against a real running backend, covering exactly the cross-cutting behaviors that can only be observed that way — desktop layout, live sync latency, and genuine file/microphone upload through browser APIs. It requires the backend and the built web app running locally; it is not part of `flutter test` or `mvnw test` and is not run in CI here.

```bash
cd backend && (set -a && source ../.env 2>/dev/null; set +a; SERVER_PORT=8081 EMAIL_PROVIDER=log DB_HOST=localhost ./mvnw spring-boot:run) &   # tee its output to a file and set BACKEND_LOG to that file
cd mobile_messenger && flutter build web --release --dart-define=API_BASE_URL=http://localhost:8081
cd mobile_messenger/build/web && python3 -m http.server 8090 &
cd e2e && npm install && npm test         # e2e_full.js: the full desktop scenario below
cd e2e && npm run test:phone              # e2e_mobile_layout.js: confirms the phone layout is untouched
```
`CHROMIUM_PATH` points Playwright at a system Chromium if you don't want to install its own; `FIXTURE_DIR` controls where the small PNG/MP4 test files it generates and uploads are written (a sandboxed/snap-packaged browser may only be able to read files under your home directory — point it there if uploads mysteriously read as empty).

**Verified passing in this environment, in a real headless browser, end-to-end (29/29 steps):** the desktop three-pane layout after login; a mobile→web message arriving live in under 2 seconds and the reverse (web→mobile) with the recipient's read receipt reflected back within 2 seconds; editing and deleting your own message from the web; creating a group from the web and inviting contacts; a mobile-side accept updating the web's member list live; group messaging both directions within 2 seconds; group delivered/read aggregation requiring every member; creating a public poll from the web, a mobile vote appearing live, changing and retracting a vote from the web; an anonymous poll hiding voters from every party including its creator; in-chat search (count, next/previous, no-matches, clearing, closing) in both a group and an individual chat, with the chat's own state provably untouched afterward; **two chats open side by side**, each receiving only its own chat's live messages, each able to send independently; incoming group and individual contact invitations appearing live and being accepted from the web; finding a person and sending them an invitation; sending an image, a video, and a recorded voice message (a fake microphone device) from the web, each confirmed present on the server and visible to the other client; a mobile-sent image arriving on the web live; a message sent while offline showing "Failed, tap to retry" and succeeding once retried after reconnecting; a page reload preserving the session, chat list, and full history; two simultaneous web sessions plus a mobile session under the same account, with logging out one leaving the others signed in and working; and a session revoked from another device signing the affected one out with the expected "session has expired" message. Also separately verified: the phone-width layout renders its original single-pane UI (no desktop chrome at any width below the breakpoint) and search still works correctly there.

### Email testing approach

Automated tests never send real email. `email.RecordingEmailService` (test-only) implements `EmailService` in memory and is wired in via `@Import(TestEmailConfig.class)` + `@Primary`, so integration tests can assert an email "would have been sent" and inspect/extract the generated verification or reset link (and thus the real, working token) directly - see the test list above.

**Verified locally** (this session, against a real PostgreSQL and a real local SMTP debug server - see below):
- The full verify-email and forgot/reset-password flows end-to-end via `curl`, including duplicate-token, expired-token, and used-token rejection, and confirming the stored `token_hash` differs from (and is unrelated to) the raw emailed token.
- **Real SMTP delivery of both email types**, protocol-level, against a local `aiosmtpd` debug SMTP server (installed without root by extracting its `.deb` package, since this sandbox has no `pip`/root and Docker was unavailable for a container-based mail server like MailHog). The backend, configured with `EMAIL_PROVIDER=smtp`, successfully connected over real SMTP and delivered both a verification email and a password reset email with correct headers, subject, and body/link - confirmed by inspecting the debug server's captured message dump.
- `flutter analyze`, all 356 Flutter tests, all 296 backend tests, and a `flutter build apk --release`.

**Requires external SMTP configuration/testing** (not done in this sandbox, no internet-reachable mail provider available):
- Delivery to a real, internet-hosted mailbox (Gmail, etc.) - the local debug-server test above proves the SMTP *client* code path works correctly, but a real provider may enforce additional requirements (SPF/DKIM, specific auth mechanisms, TLS certificate validation) that can only be confirmed against that provider.
- Actually tapping a `mobilemessenger://...` link in a real email client on a real Android device - the deep-link *route handling* (parsing the token from the incoming URI) is verified via `flutter test`, and the Android manifest intent-filter is in place, but literally tapping a link was not testable in this headless sandbox (no device/emulator with a mail client available). Recommended manual check when you have a device: send yourself a verification email in `smtp` mode, tap the link, confirm the app opens directly to `VerifyEmailScreen` with the token pre-filled.

## 25. Current Implementation Status

**Phase 1: Project foundation. Phase 2: Authentication. Phase 3: User profile. Phase 4: Email verification & password reset. Phase 5: Contacts & chat invitations. Phase 6: Chat list & archive. Phase 7: Text messaging & real-time chat. Phase 8: Image & video attachments. Phase 9: Application-level encryption at rest. Phase 10: Multi-device sessions. Phase 11: Group chats & group invitations. Phase 12: In-chat message search. Phase 13: Polls. Phase 14: Web-responsive desktop layout & two-chat view.** All implemented in this repository.

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
- Flyway-managed database schema (no manual DDL, no `hibernate.ddl-auto=update`) - `V3` adds `email_verification_tokens` and `password_reset_tokens`, storing only SHA-256 token hashes, never raw tokens; `V4` adds `contact_invitations` and `contacts`; `V5` adds `conversations` and `conversation_participants` (plus a backfill for pre-existing contacts); `V6` adds `messages`; `V7` adds `message_attachments`; `V8` widens the columns Phase 9 encrypts; `V9` is the legacy-plaintext migration runner's own bookkeeping; `V10` adds `auth_sessions`; `V11` adds `conversations.type`/`name`/`created_by`, `conversation_participants.role`, `group_invitations`, and `message_receipts`; `V12` adds `polls`, `poll_options`, and `poll_votes`
- `/api/auth/sessions` (list), `/api/auth/sessions/{id}` (DELETE, revoke), and `/api/auth/logout` for multi-device session management, plus the `?access_token=` query-parameter path accepted only on the `/ws` handshake for browser clients — see [Sessions & Multi-Device](#18-sessions--multi-device)
- `/api/groups` (create/get), `/api/groups/{id}/invitations` (invite), `/api/groups/invitations/pending|{id}/accept|{id}/decline` for group chats and their invitations — see [Group Chats & Group Invitations](#19-group-chats--group-invitations)
- `GET /api/chats/{id}/messages/search?q=...` for in-chat text search, and `/api/chats/{id}/polls*` (create/get/vote/retract) for polls — see [Message Search](#20-message-search) and [Polls](#21-polls)
- Contact search, chat invitations (send/accept/decline), and a persistent contacts relationship model, with a Contacts screen (search / requests / contacts tabs) in Flutter — see [Contacts & Chat Invitations](#13-contacts--chat-invitations)
- A persistent per-user chat list with archive/unarchive, automatically populated when a contact invitation is accepted, sorted by most recent activity, with Chats/Archived Chats screens in Flutter — see [Chat List & Archive](#14-chat-list--archive-phase-6)
- Real-time text messaging over WebSocket/STOMP: send/load(paginated)/edit/delete, SENT/DELIVERED/READ status, typing indicators, and a live conversation screen in Flutter — see [Text Messaging & Real-Time Chat](#15-text-messaging--real-time-chat-phase-7)
- Image and video message attachments: sniffed/validated uploads, server-side image thumbnails, range-request video streaming, and a Flutter composer/picker/viewer/player — see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8)
- Application-level AES-256-GCM encryption of message text, profile "About Me", and all uploaded media, with a startup migration for pre-existing plaintext data — see [Encryption](#17-encryption-phase-9)
- `/api/health` endpoint with real database connectivity checking
- Docker Compose setup for PostgreSQL + backend, with health-checked startup ordering, a persistent volume for uploaded avatars, and SMTP/email configuration passthrough
- Multi-device sessions: per-login `AuthSession` rows keyed into the JWT, an authenticated sessions list, remote/self revocation, and selective logout that leaves other devices signed in — see [Sessions & Multi-Device](#18-sessions--multi-device)
- Group chats and group invitations, reusing the direct-chat schema/UI wherever the two are the same shape, with per-member delivered/read aggregation — see [Group Chats & Group Invitations](#19-group-chats--group-invitations)
- In-chat text search (individual and group), decrypting and matching in application code since the stored text is randomly-nonced ciphertext, with highlighting, next/previous, and jump-to-message in Flutter — see [Message Search](#20-message-search)
- Polls in group chats, public or anonymous, with per-viewer vote state and a broadcast that never itself carries a tally or a vote — see [Polls](#21-polls)
- A responsive desktop web layout with up to two independent chat panels open at once, built by extracting the phone UI into embeddable widgets rather than duplicating it — see [Web Responsive Layout & Two-Chat Desktop View](#22-web-responsive-layout--two-chat-desktop-view)
- Backend integration tests (296 total), Flutter unit/widget tests (356 total), and a separate real-browser Playwright suite (29 end-to-end scenarios) — see [Testing](#24-testing)

**Logout is now server-side, not just local.** As of Phase 10, logging out (or having a session revoked from elsewhere) immediately invalidates that specific JWT server-side via its `sid` claim and the corresponding `AuthSession.revokedAt` — a logged-out token is rejected on its very next use, not merely forgotten by the client. This supersedes the earlier "logout limitation" note from Phase 2; see [Sessions & Multi-Device](#18-sessions--multi-device) for the full design.

**Login-not-gated-on-verification:** an unverified account can still log in and use most of the app - see [§12 Email Verification & Password Reset](#12-email-verification--password-reset) above for exactly what an unverified session can and can't do (`EmailVerificationGateFilter`). A deliberate choice, not an oversight.

**Encryption:** application-level AES-256-GCM encryption of message text, profile "About Me", chat-list previews, poll option text, group names, and all uploaded media is implemented — see [Encryption](#17-encryption-phase-9) for the full design, key management, what's deliberately left as plaintext and why, and known limitations (media range-request chunk granularity, no key rotation).

**Not implemented yet:** push notifications, chat mute, removing a contact, canceling a sent invitation, promoting/demoting a group member or transferring group ownership, leaving a group, and encryption key rotation. Server-side video thumbnail generation is also not implemented - see [Image, Video & Voice Attachments](#16-image-video--voice-attachments-phase-8) for why and what's already in place to add it later without an API/schema change. Do not assume any of these exist yet.

**WebSocket connection reuse:** each open chat screen/panel owns its own `stomp_dart_client` connection (opened when it mounts, closed when it's popped/closed) rather than the app sharing one long-lived connection across the whole authenticated session — including on the desktop layout, where two simultaneously open chat panels genuinely hold two independent connections. This is simple and correct for the current UI and was specifically verified not to leak one chat's events into another's panel, but there is still no persistent "app-wide" WebSocket that could, for example, push new-message notifications while the user is elsewhere in the app — that would need a shared connection, which is natural infrastructure for push notifications rather than something to build ahead of need now.

**Attachment storage cleanup:** an uploaded-but-never-sent ("pending") attachment is never garbage-collected if the user abandons the composer without sending - it stays in storage and in `message_attachments` indefinitely. A scheduled cleanup job (delete pending attachments older than, say, 24 hours) would be a reasonable small addition in a later phase; not implemented here since it's unrelated to the phase's core requirements.

### Configuration reference (Phase 8 additions)

| Property | Env var | Default | Purpose |
|---|---|---|---|
| `app.attachments.max-image-size-bytes` | `ATTACHMENT_MAX_IMAGE_SIZE_BYTES` | `10485760` (10MB) | Max accepted image upload size, checked after content-sniffing. |
| `app.attachments.max-video-size-bytes` | `ATTACHMENT_MAX_VIDEO_SIZE_BYTES` | `52428800` (50MB) | Max accepted video upload size. |
| `app.attachments.max-audio-size-bytes` | `ATTACHMENT_MAX_AUDIO_SIZE_BYTES` | `15728640` (15MB) | Max accepted voice-message (WAV) upload size - added after Phase 8 was originally written, alongside image/video, so it's listed here rather than under its own phase. |
| `spring.servlet.multipart.max-file-size` | - | `55MB` | Servlet-level ceiling; must stay ≥ the video limit above. |
| `spring.servlet.multipart.max-request-size` | - | `56MB` | Same, plus multipart framing overhead. |

### Configuration reference (Phase 9 additions)

| Property | Env var | Default | Purpose |
|---|---|---|---|
| `app.encryption.master-key` | `ENCRYPTION_MASTER_KEY` | A fixed, publicly-committed dev-only Base64 key (see [Encryption](#17-encryption-phase-9)) | AES-256 key protecting message text, profile bio, and media at rest. **Required** (with no usable default) via Docker Compose; validated strictly at startup — see [Encryption § Key management](#17-encryption-phase-9). |
