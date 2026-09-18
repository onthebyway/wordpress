#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:?usage: spx.sh IMAGE}"
name="wordpress-spx-${RANDOM}-${RANDOM}"

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
    --tmpfs /tmp/spx:rw,noexec,nosuid,nodev,size=64m,uid=33,gid=33,mode=0700 \
    -e WORDPRESS_DB_HOST=database:3306 \
    -e WORDPRESS_DB_NAME=wordpress \
    -e WORDPRESS_DB_USER=wordpress \
    -e WORDPRESS_DB_PASSWORD=spx-test-only \
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
docker exec "$name" php --ri spx >/dev/null
docker exec "$name" php -r 'exit(
    ini_get("spx.http_enabled") === "1"
    && ini_get("spx.http_profiling_enabled") === "0"
    && strlen(ini_get("spx.http_key")) === 64
    ? 0 : 1
);'
docker exec "$name" sh -eu -c '[ "$(stat -c %u:%g:%a /tmp/spx)" = "33:33:700" ]'

[[ "$(docker exec "$name" curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/_spx)" == 308 ]]
docker exec "$name" curl -fsS http://127.0.0.1:8080/_spx/ \
    | grep -F '<title>SPX Control Panel</title>' >/dev/null
docker exec "$name" curl -fsS 'http://127.0.0.1:8080/_spx/?SPX_UI_URI=/css/main.css' \
    | grep -F 'body' >/dev/null

docker exec -i "$name" sh -c 'cat > /var/www/html/byway-spx-profile-test.php' <<'PHP'
<?php
usleep(1000);
echo "profile target";
PHP

reports_before="$(docker exec "$name" find /tmp/spx -type f | wc -l)"
docker exec "$name" curl -fsS http://127.0.0.1:8080/byway-spx-profile-test.php >/dev/null
reports_without_cookie="$(docker exec "$name" find /tmp/spx -type f | wc -l)"
[[ "$reports_without_cookie" == "$reports_before" ]]

docker exec "$name" curl -fsS -D /tmp/spx-profile.headers \
    -H 'Cookie: SPX_ENABLED=1' \
    http://127.0.0.1:8080/byway-spx-profile-test.php >/dev/null
docker exec "$name" sh -c "tr -d '\\r' < /tmp/spx-profile.headers" | grep -Fq 'X-Cache: BYPASS'

reports_after="$(docker exec "$name" find /tmp/spx -type f | wc -l)"
(( reports_after > reports_without_cookie ))
docker exec "$name" find /tmp/spx -type f -exec sh -c '[ "$(stat -c %u "$1")" = 33 ]' _ {} \;
docker exec "$name" curl -fsS \
    'http://127.0.0.1:8080/_spx/?SPX_UI_URI=/data/reports/metadata' >/dev/null

cli_report="$(docker exec --user www-data -e SPX_ENABLED=1 "$name" php -r 'usleep(1000);' 2>&1)"
grep -Fq '*** SPX Report ***' <<< "$cli_report"

docker exec "$name" rm /var/www/html/byway-spx-profile-test.php /tmp/spx-profile.headers
docker stop --time 30 "$name" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$name")" == 0 ]]
