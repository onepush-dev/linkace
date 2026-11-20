# LinkAce on Railway

[LinkAce](https://github.com/Kovah/LinkAce) (GPL-3.0) — a self-hosted bookmark archive: tags, lists, notes, automatic link monitoring, Wayback Machine backups, import/export and a REST API. Deploy it on Railway with one click.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/PLACEHOLDER)

## What this template runs

- **linkace**: `ghcr.io/onepush-dev/linkace:v2.6.3`, the official `linkace/linkace:v2.6.3` image (code unmodified). Upstream expects a mounted `.env`; this wrapper renders it from service variables, runs migrations, creates the first admin and runs Laravel's scheduler every minute. Caddy + PHP-FPM listen on 8080. A volume at `/app/storage/app` keeps local files (backups).
- **postgres**: `postgres:17-alpine` with a volume, private network only.

## Variables

| Service | Variable | Value | Notes |
|---|---|---|---|
| linkace | `APP_KEY` | generated secret | Laravel encryption key (`${{secret(32)}}`, encoded to a valid `base64:` key at boot). Keep it stable. |
| linkace | `APP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL used in links and notifications. |
| linkace | `DB_HOST` | `${{postgres.RAILWAY_PRIVATE_DOMAIN}}` | Postgres host on the private network. |
| linkace | `DB_PASSWORD` | `${{postgres.POSTGRES_PASSWORD}}` | Postgres password. |
| linkace | `LINKACE_ADMIN_PASSWORD` | generated secret | Password of the first admin (`admin@example.com`). |
| postgres | `POSTGRES_PASSWORD` | generated secret | Postgres superuser password. |

`TRUSTED_HOSTS=.*` and `TRUSTED_PROXIES=*` are baked into the image so Railway healthchecks (which call `/login` as localhost) and the public domain both succeed. The wrapper also trusts Railway's edge in Caddy so `X-Forwarded-Proto` is honoured and redirects stay on HTTPS.

## How to use

1. Deploy, open the domain and sign in as `admin@example.com` with `LINKACE_ADMIN_PASSWORD`.
2. Change the email and password under your profile, then import bookmarks or add links.

Not affiliated with LinkAce.
