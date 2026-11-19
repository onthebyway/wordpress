#!/bin/sh
set -eu
export LC_ALL=C

# The caller installs curl, ca-certificates and gnupg, and removes build-only
# key-inspection tools afterwards. No keys are added to APT's global trust store.
# shellcheck disable=SC1091
. /etc/os-release
case "$ID" in
    debian|ubuntu) ;;
    *) echo "Unsupported NGINX package distribution: $ID" >&2; exit 1 ;;
esac
case "$(dpkg --print-architecture)" in
    amd64|arm64) ;;
    *) echo 'Unsupported NGINX image architecture' >&2; exit 1 ;;
esac

key_dir="$(mktemp -d)"
trap 'rm -rf "$key_dir"' EXIT
install -d -m 0700 "$key_dir/gnupg"
curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 60 --retry 3 \
    https://nginx.org/keys/nginx_signing.key \
    --output "$key_dir/nginx.asc"
GNUPGHOME="$key_dir/gnupg" gpg --batch --with-colons --show-keys \
    "$key_dir/nginx.asc" > "$key_dir/details"
fingerprints="$(awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; primary = 0 }' "$key_dir/details")"
[ -n "$fingerprints" ]
for fingerprint in $fingerprints; do
    # Published vendor keys, also pinned by nginx/docker-nginx's Dockerfiles.
    case "$fingerprint" in
        573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62|\
        8540A6F18833A80E9C1653A42FD21310B49F6B46|\
        9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3) ;;
        *) echo "Unexpected NGINX signing key: $fingerprint" >&2; exit 1 ;;
    esac
done
install -d -m 0755 /usr/share/keyrings
install -m 0644 "$key_dir/nginx.asc" /usr/share/keyrings/byway-nginx.asc
printf 'deb [signed-by=/usr/share/keyrings/byway-nginx.asc] https://nginx.org/packages/%s %s nginx\n' \
    "$ID" "$VERSION_CODENAME" > /etc/apt/sources.list.d/byway-nginx.list
printf 'Package: nginx nginx-module-*\nPin: origin nginx.org\nPin-Priority: 900\n' \
    > /etc/apt/preferences.d/byway-nginx

apt-get -o APT::Update::Error-Mode=any update
candidate="$(apt-cache policy nginx | awk '/^[[:space:]]*Candidate:/ { print $2; exit }')"
byway-check-nginx-version "$candidate"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nginx
byway-check-nginx-version
