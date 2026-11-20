# LinkAce on Railway: the official linkace/linkace:v2.6.3 image (GPL-3.0), application code unmodified.
# Railway layer: no mounted .env needed. A start script renders /app/.env from the service variables, runs the migrations,
# marks the web setup as completed, creates the first admin from LINKACE_ADMIN_* on first boot, runs Laravel's scheduler
# every minute (link checks, queue worker) and then starts the upstream supervisord (php-fpm + Caddy) on 8080.
FROM docker.io/linkace/linkace:v2.6.3
LABEL org.opencontainers.image.source="https://github.com/onepush-dev/linkace"
USER root
COPY railway/start.sh /railway-start.sh
RUN chmod +x /railway-start.sh
ENV PORT=8080 \
    DB_CONNECTION=pgsql \
    DB_PORT=5432 \
    DB_DATABASE=postgres \
    DB_USERNAME=postgres \
    TRUSTED_PROXIES='*' \
    TRUSTED_HOSTS='.*' \
    LINKACE_ADMIN_NAME=admin \
    LINKACE_ADMIN_EMAIL=admin@example.com
EXPOSE 8080
CMD ["/railway-start.sh"]
