<?php
/**
 * Plugin Name: Byway Nginx Cache Purger
 * Description: Purges the local Nginx FastCGI cache after public WordPress content changes.
 * Version: 1.0.0
 */

if (!defined('ABSPATH')) {
    exit;
}

function byway_purge_nginx_fastcgi_cache(): void
{
    static $purged = false;

    if ($purged) {
        return;
    }

    $cacheDirectory = getenv('BYWAY_NGINX_CACHE_DIR') ?: '/var/cache/nginx/wordpress';
    if (!is_dir($cacheDirectory)) {
        return;
    }

    try {
        $items = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($cacheDirectory, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::CHILD_FIRST
        );

        foreach ($items as $item) {
            if ($item->isDir() && !$item->isLink()) {
                @rmdir($item->getPathname());
            } else {
                @unlink($item->getPathname());
            }
        }

        $purged = true;
    } catch (UnexpectedValueException $exception) {
        error_log('Unable to purge the Nginx FastCGI cache: ' . $exception->getMessage());
    }
}

$bywayCachePurgeHooks = [
    'save_post',
    'deleted_post',
    'trashed_post',
    'untrashed_post',
    'created_term',
    'edited_term',
    'delete_term',
    'wp_insert_comment',
    'edit_comment',
    'delete_comment',
    'transition_comment_status',
    'wp_update_nav_menu',
    'customize_save_after',
    'switch_theme',
    'activated_plugin',
    'deactivated_plugin',
    'upgrader_process_complete',
];

foreach ($bywayCachePurgeHooks as $bywayCachePurgeHook) {
    add_action($bywayCachePurgeHook, 'byway_purge_nginx_fastcgi_cache', PHP_INT_MAX);
}
