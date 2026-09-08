#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:?usage: cron.sh IMAGE}"
suffix="${RANDOM}-${RANDOM}"
network="wordpress-cron-${suffix}"
database="wordpress-cron-db-${suffix}"
wordpress="wordpress-cron-app-${suffix}"
wordpress_data="wordpress-cron-data-${suffix}"

cleanup() {
    local status="$?"
    if (( status != 0 )); then
        docker logs "$wordpress" 2>/dev/null || true
        docker logs "$database" 2>/dev/null || true
    fi
    docker rm -f "$wordpress" "$database" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    docker volume rm "$wordpress_data" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_wordpress() {
    for _ in $(seq 1 60); do
        if [[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$wordpress")" == healthy ]]; then
            return
        fi
        if [[ "$(docker inspect --format '{{.State.Status}}' "$wordpress")" != running ]]; then
            return 1
        fi
        sleep 2
    done
    return 1
}

docker network create "$network" >/dev/null
docker volume create "$wordpress_data" >/dev/null
docker run -d \
    --name "$database" \
    --network "$network" \
    -e MARIADB_DATABASE=wordpress \
    -e MARIADB_USER=wordpress \
    -e MARIADB_PASSWORD=cron-test-only \
    -e MARIADB_ROOT_PASSWORD=cron-root-test-only \
    mariadb:10.11 >/dev/null

for _ in $(seq 1 60); do
    if docker exec "$database" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
docker exec "$database" healthcheck.sh --connect --innodb_initialized >/dev/null

wordpress_args=(
    --name "$wordpress"
    --network "$network"
    --memory 768m
    --memory-swap 768m
    --pids-limit 128
    -v "$wordpress_data:/var/www/html"
    -e "WORDPRESS_DB_HOST=$database:3306"
    -e WORDPRESS_DB_NAME=wordpress
    -e WORDPRESS_DB_USER=wordpress
    -e WORDPRESS_DB_PASSWORD=cron-test-only
    -e WP_HOME=http://wordpress
    -e WP_SITEURL=http://wordpress
)

docker run -d \
    "${wordpress_args[@]}" \
    -e WP_CRON_RUNNER_ENABLED=false \
    "$image" >/dev/null
wait_for_wordpress

docker exec --user www-data "$wordpress" wp core install \
    --url=http://wordpress \
    --title='Cron integration test' \
    --admin_user=cron-test-admin \
    --admin_password=cron-admin-test-only \
    --admin_email=cron@example.invalid \
    --skip-email \
    --path=/var/www/html >/dev/null

docker exec -i "$wordpress" sh -eu -c \
    'cat > /var/www/html/wp-content/mu-plugins/byway-cron-test.php; chown www-data:www-data /var/www/html/wp-content/mu-plugins/byway-cron-test.php' <<'PHP'
<?php
add_action('byway_cron_test', static function (): void {
    file_put_contents('/tmp/byway-cron-test-uid', (string) posix_geteuid());
});

add_action('byway_cron_shutdown_test', static function (): void {
    file_put_contents('/tmp/byway-cron-shutdown-started', '1');
    sleep(60);
});
PHP

docker exec --user www-data "$wordpress" wp cron event schedule \
    byway_cron_test now \
    --path=/var/www/html >/dev/null

docker stop --time 30 "$wordpress" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$wordpress")" == 0 ]]
docker rm "$wordpress" >/dev/null

docker run -d \
    "${wordpress_args[@]}" \
    -e WP_CRON_INTERVAL_SECONDS=1 \
    "$image" >/dev/null
wait_for_wordpress

cron_uid=""
for _ in $(seq 1 30); do
    cron_uid="$(docker exec "$wordpress" sh -c \
        'test ! -s /tmp/byway-cron-test-uid || cat /tmp/byway-cron-test-uid')"
    [[ -z "$cron_uid" ]] || break
    sleep 1
done

if [[ "$cron_uid" != "33" ]]; then
    docker exec --user www-data "$wordpress" wp cron event list --path=/var/www/html || true
    echo "Expected cron callback UID 33, got: ${cron_uid:-unset}" >&2
    exit 1
fi
[[ "$(docker inspect --format '{{.State.Status}}' "$wordpress")" == running ]]

docker exec --user www-data "$wordpress" wp cron event schedule \
    byway_cron_shutdown_test now \
    --path=/var/www/html >/dev/null

for _ in $(seq 1 30); do
    if docker exec "$wordpress" test -s /tmp/byway-cron-shutdown-started; then
        break
    fi
    sleep 1
done
docker exec "$wordpress" test -s /tmp/byway-cron-shutdown-started

docker stop --time 10 "$wordpress" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$wordpress")" == 0 ]]
