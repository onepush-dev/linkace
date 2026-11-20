#!/bin/sh
set -e
cd /app

# Laravel wants APP_KEY as base64:<16, 24 or 32 raw bytes>.
# ${{secret(32)}} is 32 ASCII chars and encodes directly; any other length is
# hashed to a stable 32-byte key so a fresh deploy never needs user input.
case "$APP_KEY" in
  base64:*) ;;
  "")
    echo "[railway] APP_KEY is required (set it to \${{secret(32)}})"
    exit 1
    ;;
  *)
    raw_len=$(printf %s "$APP_KEY" | wc -c)
    if [ "$raw_len" -eq 16 ] || [ "$raw_len" -eq 24 ] || [ "$raw_len" -eq 32 ]; then
      APP_KEY="base64:$(printf %s "$APP_KEY" | base64 | tr -d '\n')"
    else
      APP_KEY="base64:$(printf %s "$APP_KEY" | openssl dgst -binary -sha256 | base64 | tr -d '\n')"
    fi
    ;;
esac
export APP_KEY

# TrustHosts is generated from APP_URL by default, so Railway's localhost
# healthcheck (Host: localhost / ::1) gets HTTP 400. '.*' is a documented
# regex that also covers the public domain and custom domains.
TRUSTED_HOSTS="${TRUSTED_HOSTS:-.*}"
export TRUSTED_HOSTS
TRUSTED_PROXIES="${TRUSTED_PROXIES:-*}"
export TRUSTED_PROXIES

# Render the .env upstream expects from the service variables (nothing has to be mounted).
{
  echo "APP_KEY=$APP_KEY"
  echo "APP_URL=${APP_URL:-http://localhost}"
  echo "TRUSTED_PROXIES=$TRUSTED_PROXIES"
  echo "TRUSTED_HOSTS=$TRUSTED_HOSTS"
  echo "DB_CONNECTION=${DB_CONNECTION:-pgsql}"
  echo "DB_HOST=${DB_HOST}"
  echo "DB_PORT=${DB_PORT:-5432}"
  echo "DB_DATABASE=${DB_DATABASE:-postgres}"
  echo "DB_USERNAME=${DB_USERNAME:-postgres}"
  echo "DB_PASSWORD=\"${DB_PASSWORD}\""
} > /app/.env
chown www-data:www-data /app/.env
mkdir -p /app/storage/app
chown -R www-data:www-data /app/storage/app /app/storage/logs 2>/dev/null || true

as_app() { su -s /bin/sh www-data -c "cd /app && $*"; }

echo "[railway] running migrations"
n=0
until as_app "php artisan migrate --force"; do
  n=$((n+1))
  if [ "$n" -ge 20 ]; then echo "[railway] migrations failed"; exit 1; fi
  echo "[railway] database not ready, retry $n"; sleep 3
done

as_app "php artisan setup:complete" || true

if as_app "php artisan users:list" | grep -q "No users found"; then
  if [ -n "$LINKACE_ADMIN_PASSWORD" ]; then
    echo "[railway] creating first admin ${LINKACE_ADMIN_EMAIL}"
    as_app "timeout 60 php artisan registeruser '${LINKACE_ADMIN_NAME:-admin}' '${LINKACE_ADMIN_EMAIL:-admin@example.com}' '${LINKACE_ADMIN_PASSWORD}' --admin --no-interaction" || echo "[railway] admin creation failed"
  else
    echo "[railway] LINKACE_ADMIN_PASSWORD not set; create an admin with: php artisan registeruser --admin"
  fi
fi

# Laravel scheduler (link checks every 2h, queue worker for imports) once a minute
(
  while true; do
    sleep 60
    as_app "php artisan schedule:run" >/dev/null 2>&1 || true
  done
) &

# Railway's edge is not in private_ranges, so Caddy would drop X-Forwarded-Proto
# and Laravel would redirect / to http://.../login. Trust all proxies here.
if ! grep -q 'trusted_proxies static private_ranges' /etc/caddy/Caddyfile; then
  echo "[railway] unexpected Caddyfile; cannot trust Railway proxy"
  cat /etc/caddy/Caddyfile
  exit 1
fi
sed -i 's/trusted_proxies static private_ranges/trusted_proxies static private_ranges 0.0.0.0\/0 ::\/0/' /etc/caddy/Caddyfile
echo "[railway] Caddy trusts Railway edge proxies"

exec /usr/bin/supervisord -c /etc/supervisor.d/supervisord.ini
