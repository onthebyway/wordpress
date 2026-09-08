<?php
/**
 * Environment-driven WordPress configuration used when a persistent document
 * root does not already contain wp-config.php.
 */

if (!function_exists('getenv_docker')) {
    function getenv_docker($environmentVariable, $default)
    {
        $file = getenv($environmentVariable . '_FILE');
        if ($file !== false && $file !== '') {
            return rtrim(file_get_contents($file), "\r\n");
        }

        $value = getenv($environmentVariable);
        return $value !== false ? $value : $default;
    }
}

if (!function_exists('byway_env_bool')) {
    function byway_env_bool($environmentVariable, bool $default): bool
    {
        $value = getenv_docker($environmentVariable, null);
        if ($value === null || $value === '') {
            return $default;
        }

        $parsed = filter_var($value, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
        return $parsed ?? $default;
    }
}

if (!function_exists('byway_env_bool_or_string')) {
    function byway_env_bool_or_string($environmentVariable, $default)
    {
        $value = getenv_docker($environmentVariable, null);
        if ($value === null || $value === '') {
            return $default;
        }

        $normalized = strtolower(trim((string) $value));
        if (in_array($normalized, ['1', 'true', 'yes', 'on'], true)) {
            return true;
        }
        if (in_array($normalized, ['0', 'false', 'no', 'off'], true)) {
            return false;
        }

        return $value;
    }
}

define('DB_NAME', getenv_docker('WORDPRESS_DB_NAME', 'wordpress'));
define('DB_USER', getenv_docker('WORDPRESS_DB_USER', 'wordpress'));
define('DB_PASSWORD', getenv_docker('WORDPRESS_DB_PASSWORD', ''));
define('DB_HOST', getenv_docker('WORDPRESS_DB_HOST', 'database:3306'));
define('DB_CHARSET', getenv_docker('WORDPRESS_DB_CHARSET', 'utf8mb4'));
define('DB_COLLATE', getenv_docker('WORDPRESS_DB_COLLATE', ''));

define('AUTH_KEY', getenv_docker('WORDPRESS_AUTH_KEY', 'put your unique phrase here'));
define('SECURE_AUTH_KEY', getenv_docker('WORDPRESS_SECURE_AUTH_KEY', 'put your unique phrase here'));
define('LOGGED_IN_KEY', getenv_docker('WORDPRESS_LOGGED_IN_KEY', 'put your unique phrase here'));
define('NONCE_KEY', getenv_docker('WORDPRESS_NONCE_KEY', 'put your unique phrase here'));
define('AUTH_SALT', getenv_docker('WORDPRESS_AUTH_SALT', 'put your unique phrase here'));
define('SECURE_AUTH_SALT', getenv_docker('WORDPRESS_SECURE_AUTH_SALT', 'put your unique phrase here'));
define('LOGGED_IN_SALT', getenv_docker('WORDPRESS_LOGGED_IN_SALT', 'put your unique phrase here'));
define('NONCE_SALT', getenv_docker('WORDPRESS_NONCE_SALT', 'put your unique phrase here'));

$table_prefix = getenv_docker('WORDPRESS_TABLE_PREFIX', 'wp_');

$legacyDebugDefault = byway_env_bool('WORDPRESS_DEBUG', false);
define('WP_DEBUG', byway_env_bool('WP_DEBUG', $legacyDebugDefault));
define('WP_DEBUG_LOG', byway_env_bool_or_string('WP_DEBUG_LOG', false));
define('WP_DEBUG_DISPLAY', byway_env_bool('WP_DEBUG_DISPLAY', false));
define('SCRIPT_DEBUG', byway_env_bool('WP_SCRIPT_DEBUG', false));

$wpMemoryLimit = getenv_docker('WP_MEMORY_LIMIT', '');
if ($wpMemoryLimit !== '') {
    define('WP_MEMORY_LIMIT', $wpMemoryLimit);
}

$wpMaxMemoryLimit = getenv_docker('WP_MAX_MEMORY_LIMIT', '');
if ($wpMaxMemoryLimit !== '') {
    define('WP_MAX_MEMORY_LIMIT', $wpMaxMemoryLimit);
}

$wpHome = getenv_docker('WP_HOME', '');
if ($wpHome !== '') {
    define('WP_HOME', $wpHome);
}

$wpSiteUrl = getenv_docker('WP_SITEURL', '');
if ($wpSiteUrl !== '') {
    define('WP_SITEURL', $wpSiteUrl);
}

$wpRedisHost = getenv_docker('WP_REDIS_HOST', '');
if ($wpRedisHost !== '') {
    define('WP_REDIS_HOST', $wpRedisHost);
    define('WP_REDIS_PORT', (int) getenv_docker('WP_REDIS_PORT', '6379'));
    define('WP_REDIS_DATABASE', (int) getenv_docker('WP_REDIS_DATABASE', '0'));
    define('WP_REDIS_TIMEOUT', (float) getenv_docker('WP_REDIS_TIMEOUT', '1'));
    define('WP_REDIS_READ_TIMEOUT', (float) getenv_docker('WP_REDIS_READ_TIMEOUT', '1'));

    $wpRedisPrefix = getenv_docker('WP_REDIS_PREFIX', '');
    if ($wpRedisPrefix !== '') {
        define('WP_REDIS_PREFIX', $wpRedisPrefix);
    }
}

define('FS_METHOD', getenv_docker('WP_FS_METHOD', 'direct'));
define('DISALLOW_FILE_EDIT', byway_env_bool('WP_DISALLOW_FILE_EDIT', true));
define('DISABLE_WP_CRON', byway_env_bool('DISABLE_WP_CRON', false));
define('WP_ENVIRONMENT_TYPE', getenv_docker('WP_ENVIRONMENT_TYPE', 'production'));

$wpAutoUpdateCore = byway_env_bool_or_string('WP_AUTO_UPDATE_CORE', 'minor');
define('WP_AUTO_UPDATE_CORE', $wpAutoUpdateCore);

if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
    $_SERVER['HTTPS'] = 'on';
}

$configExtra = getenv_docker('WORDPRESS_CONFIG_EXTRA', '');
if ($configExtra !== '') {
    eval($configExtra);
}

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
