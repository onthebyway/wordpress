#!/usr/bin/env bash
set -Eeuo pipefail

policy="$(dirname "$0")/../docker/bin/byway-check-nginx-version"

for version in \
    1.30.7 \
    '1.30.7-1~trixie' \
    '1.30.8-1~noble' \
    1.32.0 \
    '1:1.34.2-1~trixie'; do
    sh "$policy" "$version" >/dev/null
done

for version in \
    '1.24.0-2ubuntu7.19' \
    '1.26.3-3+deb13u10' \
    1.30.6 \
    1.31.8 \
    1.31.9 \
    2.0.0 \
    1.030.7 \
    malformed; do
    if sh "$policy" "$version" >/dev/null 2>&1; then
        echo "NGINX policy unexpectedly accepted $version" >&2
        exit 1
    fi
done

echo 'NGINX version policy tests passed'
