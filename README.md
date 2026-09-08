# Byway WordPress

A WordPress runtime combining Nginx, PHP-FPM, WP-CLI, Redis support and Imagick in one application image. Run MariaDB and, optionally, Redis as separate containers.

```text
reverse proxy -> Nginx :8080 -> FastCGI cache -> PHP-FPM :9000
```

## Images

| Image | Purpose |
| --- | --- |
| `ghcr.io/onthebyway/wordpress:php8.4` | Supported runtime based on the official WordPress PHP 8.4 image |
| `ghcr.io/onthebyway/wordpress:php7.4` | Migration-only runtime using PHP 7.4 packages from `ppa:ondrej/php` on Ubuntu 24.04 LTS |

PHP 7.4 is end-of-life and receives no upstream security support. Its image exists only to import legacy sites, update their code and move them to a supported PHP version; do not use it for production or new sites. The signed third-party PPA keeps PHP 7.4 installable on a supported operating-system base but does not restore upstream PHP support. Neither image is published as `latest`.

## Features

- Current WordPress seed from the official PHP 8.4 image
- Nginx FastCGI page cache with safe bypasses for authenticated and dynamic requests
- PHP-FPM managed with Nginx under `tini`
- WP-CLI 2.12.0, PhpRedis and Imagick support
- PHP-FPM health endpoint at `/.byway-health`
- Persistent browser-based WordPress, plugin and theme updates
- Built-in five-minute WP-CLI cron runner executing as `www-data`
- Automatic full-page cache purging after content and extension changes
- Graceful container shutdown

## Quick start

```bash
cp .env.example .env
# Replace the example credentials and set the public URL.
docker network create caddy
docker compose -f compose.example.yaml up -d
```

The example expects an external `caddy` network. Any reverse proxy can be used if it can reach the WordPress container on port `8080`.

Run WP-CLI as the web user:

```bash
docker compose -f compose.example.yaml exec -T --user www-data wordpress \
  wp core version
```

## Build

Build both variants:

```bash
docker buildx bake --load
```

Build one variant:

```bash
docker buildx bake --load php84
docker buildx bake --load php74
```

Override `IMAGE_NAME` to change the output repository:

```bash
IMAGE_NAME=ghcr.io/example/wordpress docker buildx bake --push
```

### Legacy migration workflow

Use the PHP 7.4 image only on a disposable clone without production credentials or private-network access:

1. Import and inspect the legacy site under PHP 7.4.
2. Update WordPress core, plugins and themes.
3. Back up the database and document root.
4. Switch the clone to the PHP 8.4 image and resolve remaining compatibility errors.
5. Deploy only after the site works on the supported image.

Unknown or compromised sites require stronger isolation than a container on a shared host; prefer a disposable VM.

## Configuration

See [`.env.example`](.env.example) for all commonly used settings.

Important defaults:

| Variable | Default |
| --- | --- |
| `PHP_MEMORY_LIMIT` | `256M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `64M` |
| `PHP_POST_MAX_SIZE` | `70M` |
| `PHP_FPM_MAX_CHILDREN` | `5` |
| `WP_DISALLOW_FILE_EDIT` | `true` |
| `WP_AUTO_UPDATE_CORE` | `minor` |
| `DISABLE_WP_CRON` | `true` |
| `WP_CRON_RUNNER_ENABLED` | `true` |
| `WP_CRON_INTERVAL_SECONDS` | `300` |
| `NGINX_CLIENT_MAX_BODY_SIZE` | `70M` |
| `NGINX_FASTCGI_CACHE_MAX_SIZE` | `1g` |

Keep `PHP_POST_MAX_SIZE` and `NGINX_CLIENT_MAX_BODY_SIZE` larger than `PHP_UPLOAD_MAX_FILESIZE`.

The standard official-image `WORDPRESS_*` settings are supported, including `*_FILE` secret variables. On first initialization, the official WordPress entrypoint generates random authentication salts unless explicit values are supplied. Existing document roots and `wp-config.php` files are never replaced.

Set `NGINX_TRUSTED_PROXY_CIDRS` to the exact reverse-proxy network. Never use `0.0.0.0/0` in production.

## Persistent data

| Path | Purpose | Back up |
| --- | --- | ---: |
| `/var/www/html` | WordPress core and content | Yes |
| MariaDB `/var/lib/mysql` | Database | Use `mariadb-dump` or `mariadb-backup` |
| `/var/cache/nginx` | Disposable page cache | No |

Imported files must be writable by `www-data`. Do not run imported plugin or theme code as root.

## Cron and cache

The image installs the bundled `Byway Nginx Cache Purger` as a WordPress MU plugin. It clears the complete Nginx FastCGI page cache after content, menu, comment, theme, plugin or upgrader changes so visitors do not receive stale pages. Full-cache purging is intentional for the small sites this image targets.

The built-in cron runner executes the following command as `www-data` every five minutes without overlapping runs:

```bash
wp cron event run --due-now --quiet --path=/var/www/html
```

It is enabled by default with `WP_CRON_RUNNER_ENABLED=true`. WordPress's request-triggered cron defaults to disabled with `DISABLE_WP_CRON=true`, preventing duplicate execution. A failed run is logged and retried after the next interval.

Set `WP_CRON_RUNNER_ENABLED=false` when an external scheduler already runs WordPress cron. `WP_CRON_INTERVAL_SECONDS` defaults to `300`; lower values are primarily useful for testing.

Purge the page cache manually with:

```bash
docker compose -f compose.example.yaml exec wordpress byway-cache-purge
```

## Security

- Keep the image, WordPress core, plugins and themes updated.
- Use unique database credentials and do not commit `.env` files.
- Back up both the database and `/var/www/html` before upgrades.
- Treat the PHP 7.4 variant as a temporary migration bridge.
- Report vulnerabilities according to [SECURITY.md](SECURITY.md).

## License

The custom source in this repository is licensed under GPL-2.0-or-later. WordPress and other included software retain their respective licenses.
