FROM ghcr.io/cirruslabs/flutter:3.41.6 AS builder

ARG API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api
ARG CANONICAL_HOST=altodemamita.com
ARG CANONICAL_SCHEME=https

WORKDIR /app

COPY pubspec.* ./
RUN flutter pub get

COPY . .

RUN flutter build web --release --base-href / --dart-define=API_BASE_URL=${API_BASE_URL}
RUN printf "self.addEventListener('install', function () { self.skipWaiting(); });\nself.addEventListener('activate', function (event) { event.waitUntil(self.clients.claim()); });\n" > build/web/flutter_service_worker.js

FROM nginx:alpine AS production

ARG API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/api
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