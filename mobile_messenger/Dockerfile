## Web Messenger - production build of the Flutter web app, served by nginx.
##
##   docker build -t web-messenger-web \
##       --build-arg API_BASE_URL=https://api.example.com .
##
## API_BASE_URL is compiled into the app (it is a Dart compile-time constant),
## so it must be the address the *browser* can reach the backend at - HTTPS if
## the web app itself is served over HTTPS. Rebuild to point at another backend.

## Build stage
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.41.9
ARG API_BASE_URL=http://localhost:8080

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pinned to the version the app is developed and tested with.
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web \
    && flutter precache --web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

## Runtime stage
FROM nginx:1.27-alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
