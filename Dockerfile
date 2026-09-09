# syntax=docker/dockerfile:1.7

ARG WORDPRESS_IMAGE=wordpress:php8.4-fpm
ARG WP_CLI_IMAGE=wordpress:cli-2.12.0-php8.4
ARG PHP_REDIS_VERSION=6.3.0
ARG PHP_IMAGICK_VERSION=3.8.0

FROM ${WP_CLI_IMAGE} AS wp-cli

FROM ${WORDPRESS_IMAGE}

ARG PHP_REDIS_VERSION
ARG PHP_IMAGICK_VERSION

LABEL org.opencontainers.image.title="Byway WordPress" \
    org.opencontainers.image.description="WordPress with Nginx, PHP-FPM, WP-CLI, Redis and Imagick" \
    org.opencontainers.image.source="https://github.com/onthebyway/wordpress" \
    org.opencontainers.image.url="https://github.com/onthebyway/wordpress" \
    org.opencontainers.image.vendor="Byway" \
    org.opencontainers.image.licenses="GPL-2.0-or-later"

# Some security-package URLs intermittently return 404 on Debian CDN endpoints.
# APT's mirror method retries official endpoints, retaining verification.
# OS packages intentionally float so scheduled rebuilds receive security updates.
# hadolint ignore=DL3008
RUN mkdir -p /etc/apt/mirrors \
    && printf '%s\n' 'https://security.debian.org' 'https://security.debian.org/debian-security' 'https://deb.debian.org/debian-security' > /etc/apt/mirrors/byway-security.list \
    && find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) ! -path '/etc/apt/mirrors/*' \
        -exec sed -i 's|http://deb.debian.org/debian-security|mirror+file:/etc/apt/mirrors/byway-security.list|g; s|https://deb.debian.org/debian-security|mirror+file:/etc/apt/mirrors/byway-security.list|g' {} + \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gettext-base \
        gosu \
        nginx \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

# Extension build-package expansion and the library-discovery pipeline are
# intentional; runtime libraries are retained before temporary dependencies go.
# hadolint ignore=DL3008,DL4006,SC2086
RUN set -eux; \
    if ! php -m | grep -Fqi redis || ! php -m | grep -Fqi imagick; then \
        savedAptMark="$(apt-mark showmanual)"; \
        apt-get update; \
        buildPackages="$PHPIZE_DEPS"; \
        if ! php -m | grep -Fqi imagick; then \
            buildPackages="$buildPackages libmagickwand-dev"; \
        fi; \
        apt-get install -y --no-install-recommends $buildPackages; \
        if ! php -m | grep -Fqi redis; then \
            pecl install "redis-$PHP_REDIS_VERSION"; \
            docker-php-ext-enable redis; \
        fi; \
        if ! php -m | grep -Fqi imagick; then \
            pecl install "imagick-$PHP_IMAGICK_VERSION"; \
            docker-php-ext-enable imagick; \
        fi; \
        apt-mark auto '.*' > /dev/null; \
        if [ -n "$savedAptMark" ]; then apt-mark manual $savedAptMark; fi; \
        find "$(php -r 'echo ini_get("extension_dir");')" -type f \( -name 'redis.so' -o -name 'imagick.so' \) -exec ldd '{}' ';' \
            | awk '/=>/ { print $(NF-1) }' \
            | sort -u \
            | xargs -r dpkg-query --search \
            | cut -d: -f1 \
            | sort -u \
            | xargs -r apt-mark manual; \
        apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
        rm -rf /var/lib/apt/lists/* /tmp/pear ~/.pearrc; \
    fi; \
    php --ri redis > /dev/null; \
    php --ri imagick > /dev/null

COPY --from=wp-cli /usr/local/bin/wp /usr/local/bin/wp
COPY docker/nginx/nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY docker/nginx/wordpress.conf.template /etc/nginx/templates/wordpress.conf.template
COPY docker/php/zz-byway.ini.template /usr/local/etc/php/templates/zz-byway.ini.template
COPY docker/php-fpm/zzz-byway.conf.template /usr/local/etc/php-fpm.d/templates/zzz-byway.conf.template
COPY docker/wordpress/wp-config-docker.php /usr/src/wordpress/wp-config-docker.php
COPY docker/wordpress/byway-nginx-cache.php /usr/local/share/byway-wordpress/mu-plugins/byway-nginx-cache.php
COPY --chmod=0755 docker/bin/byway-cache-purge /usr/local/bin/byway-cache-purge
COPY --chmod=0755 docker/bin/byway-wordpress-cron /usr/local/bin/byway-wordpress-cron
COPY --chmod=0755 docker/bin/byway-wordpress-entrypoint /usr/local/bin/byway-wordpress-entrypoint

RUN mkdir -p \
        /etc/nginx/templates \
        /usr/local/etc/php/templates \
        /usr/local/etc/php-fpm.d/templates \
        /usr/local/share/byway-wordpress/mu-plugins \
        /var/cache/nginx/wordpress \
        /var/www/.wp-cli/cache \
        /run/nginx \
    && chown -R www-data:www-data /var/cache/nginx /var/www/.wp-cli /run/nginx

ENV PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=64M \
    PHP_POST_MAX_SIZE=70M \
    PHP_MAX_EXECUTION_TIME=120 \
    PHP_MAX_INPUT_VARS=3000 \
    PHP_FPM_MAX_CHILDREN=5 \
    PHP_FPM_START_SERVERS=1 \
    PHP_FPM_MIN_SPARE_SERVERS=1 \
    PHP_FPM_MAX_SPARE_SERVERS=3 \
    NGINX_CLIENT_MAX_BODY_SIZE=70M \
    NGINX_FASTCGI_CACHE_VALID=1h \
    NGINX_FASTCGI_CACHE_INACTIVE=24h \
    NGINX_FASTCGI_CACHE_MAX_SIZE=1g \
    NGINX_TRUSTED_PROXY_CIDRS=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,::1/128,fc00::/7 \
    BYWAY_NGINX_CACHE_DIR=/var/cache/nginx/wordpress \
    WP_CLI_CACHE_DIR=/var/www/.wp-cli/cache \
    WP_CRON_RUNNER_ENABLED=true \
    WP_CRON_INTERVAL_SECONDS=300 \
    DISABLE_WP_CRON=true

WORKDIR /var/www/html

EXPOSE 8080
VOLUME ["/var/www/html", "/var/cache/nginx"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["curl", "--fail", "--silent", "--show-error", "http://127.0.0.1:8080/.byway-health"]

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/byway-wordpress-entrypoint"]
CMD ["serve"]
