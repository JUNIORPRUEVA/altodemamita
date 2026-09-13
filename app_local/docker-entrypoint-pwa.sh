#!/bin/sh
set -eu

config_file="/usr/share/nginx/html/runtime-config.js"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_string() {
  key="$1"
  value="$2"
  escaped="$(json_escape "$value")"
  printf '  %s: "%s",\n' "$key" "$escaped" >> "$config_file"
}

write_bool() {
  key="$1"
  value="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|1|yes|y|on) normalized="true" ;;
    false|0|no|n|off) normalized="false" ;;
    *) normalized="false" ;;
  esac
  printf '  %s: %s,\n' "$key" "$normalized" >> "$config_file"
}

{
  printf 'window.__SISTEMA_SOLARES_CONFIG__ = {\n'
} > "$config_file"

write_string SYNC_API_BASE_URL "${SYNC_API_BASE_URL:-}"
write_string CLOUD_CUTOVER_MODE "${CLOUD_CUTOVER_MODE:-}"
write_bool ALLOW_CLOUD_PULL "${ALLOW_CLOUD_PULL:-false}"
write_bool ALLOW_LEGACY_MIGRATION "${ALLOW_LEGACY_MIGRATION:-false}"
write_bool ALLOW_AUTH_BOOTSTRAP "${ALLOW_AUTH_BOOTSTRAP:-false}"
write_bool ALLOW_MANUAL_CLOUD_RESTORE "${ALLOW_MANUAL_CLOUD_RESTORE:-false}"
write_bool MANUAL_CLOUD_SYNC_ONLY "${MANUAL_CLOUD_SYNC_ONLY:-false}"
write_bool PRODUCTION_MODE "${PRODUCTION_MODE:-true}"
write_bool PWA_RUNTIME_DIAGNOSTIC "${PWA_RUNTIME_DIAGNOSTIC:-false}"

printf '};\n' >> "$config_file"
