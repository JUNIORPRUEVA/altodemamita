#!/bin/sh
set -eu

envsubst '$API_BASE_URL' \
  < /etc/nginx/templates/app-config.json.template \
  > /usr/share/nginx/html/app-config.json