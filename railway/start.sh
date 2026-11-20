#!/bin/sh
set -e
cd /app

# Laravel wants APP_KEY as base64:<32 bytes>. Accept a raw 32-char secret and encode it.
case "$APP_KEY" in
  base64:*) ;;
  "") echo "[railway] APP_KEY is required"; exit 1 ;;
  *) APP_KEY="base64:$(printf %s "$APP_KEY" | base64 | tr -d '\n')" ;;
esac
export APP_KEY

# Render the .env upstream expects from the service variables (nothing has to be mounted).
{
  echo "APP_KEY=$APP_KEY"
  echo "APP_URL=${APP_URL:-http://localhost}"
  echo "TRUSTED_PROXIES=${TRUSTED_PROXIES:-*}"
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

exec /usr/bin/supervisord -c /etc/supervisor.d/supervisord.ini
