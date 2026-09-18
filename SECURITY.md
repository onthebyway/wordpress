# Security policy

## Supported images

Security updates are provided for the `php8.4` and `php8.5` images. The `php8.5-spx` image is an experimental, temporary diagnostic variant for authenticated non-production sites; it is not a general production runtime. The `php7.4` image uses signed `ppa:ondrej/php` packages on Ubuntu 24.04, but PHP 7.4 remains upstream end-of-life; this migration-only image is not supported for production and should be migrated away from.

## PHP-SPX access

The PHP-SPX control panel exposes application call graphs and can consume substantial resources while profiling. The image intentionally delegates user authentication to the outer ingress. Protect the entire profiling site with VPN, SSO, Basic Auth or an equivalent policy, and do not publish container port `8080` around that policy. Use bounded ephemeral storage for `/tmp/spx`, and remove the profiling deployment after the investigation.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub Security Advisories for this repository. Do not open a public issue containing exploit details, credentials or personal data.

Include the affected image tag, reproduction steps, impact and any suggested mitigation. Reports about WordPress core or bundled third-party software should also be sent to the relevant upstream security team.
