#!/bin/sh
set -eu

APP_BUILD_ID="${APP_BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"

envsubst '$API_BASE_URL' \
  < /etc/nginx/templates/app-config.json.template \
  > /usr/share/nginx/html/app-config.json

if [ -f /usr/share/nginx/html/version.json ]; then
  VERSION_JSON_TMP="/usr/share/nginx/html/version.json.tmp"
  if grep -q '"build"' /usr/share/nginx/html/version.json; then
    sed "s/\"build\":\"[^\"]*\"/\"build\":\"${APP_BUILD_ID}\"/" \
      /usr/share/nginx/html/version.json > "$VERSION_JSON_TMP"
  else
    sed "s/}$/,\"build\":\"${APP_BUILD_ID}\"}/" \
      /usr/share/nginx/html/version.json > "$VERSION_JSON_TMP"
  fi
  mv "$VERSION_JSON_TMP" /usr/share/nginx/html/version.json
fi