FROM ghcr.io/cirruslabs/flutter:3.41.6 AS builder

ARG API_BASE_URL=https://altodemanita-altodemamita-backend.onqyr1.easypanel.host/api
ARG CANONICAL_HOST=altodemamita.com
ARG CANONICAL_SCHEME=https

WORKDIR /app

COPY pubspec.* ./
RUN flutter pub get

COPY . .

RUN flutter build web --release --base-href / --dart-define=API_BASE_URL=${API_BASE_URL}

# Write a build-specific version.json so the runtime bootstrap can detect deploy changes
# and aggressively clear caches/service workers when needed.
RUN set -eux; \
	APP_VERSION="$(grep '^version:' pubspec.yaml | head -n 1 | awk '{print $2}' | tr -d '\r')"; \
	BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)"; \
	printf '{"version":"%s","build":"%s"}\n' "$APP_VERSION" "$BUILD_ID" > build/web/version.json
RUN printf "self.addEventListener('install', function () { self.skipWaiting(); });\nself.addEventListener('activate', function (event) { event.waitUntil((async function () { const cacheKeys = await caches.keys(); await Promise.all(cacheKeys.map(function (cacheKey) { return caches.delete(cacheKey); })); await self.registration.unregister(); if (self.clients && self.clients.claim) { await self.clients.claim(); } })()); });\nself.addEventListener('fetch', function () {});\n" > build/web/flutter_service_worker.js

FROM nginx:alpine AS production

ARG API_BASE_URL=https://altodemanita-altodemamita-backend.onqyr1.easypanel.host/api
ARG CANONICAL_HOST=altodemamita.com
ARG CANONICAL_SCHEME=https

COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY deploy/app-config.json.template /etc/nginx/templates/app-config.json.template
COPY deploy/40-env-config.sh /docker-entrypoint.d/40-env-config.sh
COPY --from=builder /app/build/web /usr/share/nginx/html

RUN chmod +x /docker-entrypoint.d/40-env-config.sh

ENV API_BASE_URL=${API_BASE_URL}
ENV CANONICAL_HOST=${CANONICAL_HOST}
ENV CANONICAL_SCHEME=${CANONICAL_SCHEME}

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]