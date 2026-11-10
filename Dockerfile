# Server und fertig gebaute Web-App in einem Container.
# Vorher die Web-App bauen:  cd app && flutter build web --release --no-web-resources-cdn
# Bauen:   docker build -t content-hub .
# Starten: docker compose up -d   (siehe docker-compose.yml)
FROM dart:stable AS build
WORKDIR /src/server
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ ./
RUN dart compile exe bin/server.dart -o /src/content-hub-server

FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/content-hub-server /app/content-hub-server
COPY app/build/web /app/web
ENV WEB_DIR=/app/web STORAGE_DIR=/data/storage PORT=8080
EXPOSE 8080
CMD ["/app/content-hub-server"]
