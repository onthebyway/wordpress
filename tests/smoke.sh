#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:?usage: smoke.sh IMAGE EXPECTED_PHP_PREFIX}"
expected_php="${2:?usage: smoke.sh IMAGE EXPECTED_PHP_PREFIX}"
name="wordpress-smoke-${RANDOM}-${RANDOM}"

cleanup() {
    docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d \
    --name "$name" \
    --network none \
    --memory 768m \
    --memory-swap 768m \
    --pids-limit 128 \
    -e WORDPRESS_DB_HOST=database:3306 \
    -e WORDPRESS_DB_NAME=wordpress \
    -e WORDPRESS_DB_USER=wordpress \
    -e WORDPRESS_DB_PASSWORD=smoke-test-only \
    "$image" >/dev/null

for _ in $(seq 1 60); do
    if [[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name")" == healthy ]]; then
        break
    fi
    if [[ "$(docker inspect --format '{{.State.Status}}' "$name")" != running ]]; then
        docker logs "$name"
        exit 1
    fi
    sleep 2
done

[[ "$(docker inspect --format '{{.State.Health.Status}}' "$name")" == healthy ]]
[[ "$(docker exec "$name" curl -fsS http://127.0.0.1:8080/.byway-health)" == pong ]]
[[ "$(docker exec "$name" curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/wp-config-docker.php)" == 403 ]]

docker exec "$name" php -r \
    'exit(strpos(PHP_VERSION, $argv[1]) === 0 ? 0 : 1);' -- "$expected_php"
docker exec "$name" php --ri redis >/dev/null
docker exec "$name" php --ri imagick >/dev/null
docker exec "$name" php -l /var/www/html/wp-config.php >/dev/null
docker exec "$name" sh -eu -c '! grep -q "put your unique phrase here" /var/www/html/wp-config.php'
docker exec --user www-data "$name" wp core version --skip-plugins --skip-themes >/dev/null
docker exec "$name" nginx -t
docker exec "$name" php-fpm --test

docker stop --time 30 "$name" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$name")" == 0 ]]
