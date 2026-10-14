<?php
/**
 * Plugin Name: ZZmore App Version & Update Notices
 * Description: Admin page to publish the latest app version (used by the app's
 *              "Update available" prompt) and optionally push-notify app users.
 *
 * Install: upload to wp-content/mu-plugins/ (same folder as the other
 * zzmore-*.php files). Then open  WP Admin → Settings → ZZmore App Version.
 *
 * Safe by design: old app versions keep working. The app only SHOWS a
 * dismissible reminder (at most once every 3 days). "Minimum supported build"
 * stays 0 (nobody is ever forced to update) unless you deliberately raise it.
 */

if (!defined('ABSPATH')) exit;

add_action('admin_menu', function () {
    add_options_page('ZZmore App Version', 'ZZmore App Version', 'manage_options', 'zzmore-app-version', 'zzmore_app_version_page');
});

function zzmore_app_version_fields(): array
{
    return [
        'zzmore_latest_app_version_code' => ['Latest build number', 'int',  'The number after the + in pubspec.yaml (e.g. 17). Apps with a lower build see the update reminder.'],
        'zzmore_latest_app_version_name' => ['Latest version name',  'text', 'e.g. 3.3.8 — shown in the reminder.'],
        'zzmore_app_update_url'          => ['Google Play link',     'url',  'https://play.google.com/store/apps/details?id=store.zzmore.app'],
        'zzmore_app_update_url_ios'      => ['App Store link',       'url',  'Your iPhone listing URL. Leave empty and iPhone users get no reminder.'],
        'zzmore_app_update_message'      => ['Custom message',       'text', 'Optional. Leave empty for the standard friendly message.'],
        'zzmore_min_app_version_code'    => ['Minimum supported build', 'int', 'Leave at 0. Only raise it if an old build can no longer work with the server; those users are then required to update.'],
    ];
}

function zzmore_app_version_page(): void
{
    if (!current_user_can('manage_options')) return;
    $notice = '';

    if (!empty($_POST['zzmore_save']) && check_admin_referer('zzmore_app_version')) {
        foreach (zzmore_app_version_fields() as $key => $f) {
            $val = isset($_POST[$key]) ? wp_unslash($_POST[$key]) : '';
            $val = $f[1] === 'int' ? max(0, (int) $val) : ($f[1] === 'url' ? esc_url_raw($val) : sanitize_text_field($val));
            update_option($key, $val);
        }
        $notice = 'Saved. Apps will see the new version on their next launch.';
    }

    if (!empty($_POST['zzmore_push']) && check_admin_referer('zzmore_app_version')) {
        $name = (string) get_option('zzmore_latest_app_version_name', '');
        $title = 'ZZmore update available';
        $body  = $name ? "Version $name is out with new features and fixes. Update when you're ready." : 'A new version of ZZmore is out. Update when you\'re ready.';
        update_option('zzmore_update_push_queue', ['offset' => 0, 'title' => $title, 'body' => $body, 'version' => (int) get_option('zzmore_latest_app_version_code', 0)], false);
        if (!wp_next_scheduled('zzmore_update_push_batch')) wp_schedule_single_event(time() + 5, 'zzmore_update_push_batch');
        $notice = 'Update notification queued. It is sent in small batches in the background.';
    }

    echo '<div class="wrap"><h1>ZZmore App Version</h1>';
    if ($notice) echo '<div class="notice notice-success"><p>' . esc_html($notice) . '</p></div>';
    echo '<form method="post">';
    wp_nonce_field('zzmore_app_version');
    echo '<table class="form-table">';
    foreach (zzmore_app_version_fields() as $key => $f) {
        printf('<tr><th><label for="%1$s">%2$s</label></th><td><input class="regular-text" type="%3$s" id="%1$s" name="%1$s" value="%4$s"><p class="description">%5$s</p></td></tr>',
            esc_attr($key), esc_html($f[0]), $f[1] === 'int' ? 'number' : 'text', esc_attr((string) get_option($key, '')), esc_html($f[2]));
    }
    echo '</table><p><button class="button button-primary" name="zzmore_save" value="1">Save version settings</button></p>';
    echo '<hr><h2>Notify app users</h2><p>Sends a push notification to logged-in app users telling them an update is available. Only do this after the new version is live in the stores. Sending is throttled and runs in the background.</p>';
    echo '<p><button class="button" name="zzmore_push" value="1" onclick="return confirm(\'Send the update notification to all app users?\');">Send update notification</button></p>';
    echo '</form></div>';
}

// Background sender: 100 users per batch, one batch every minute, so a large
// user base never times out or floods the push service.
add_action('zzmore_update_push_batch', function () {
    $q = get_option('zzmore_update_push_queue');
    if (!is_array($q) || !function_exists('zzmore_send_push_to_user')) return;

    $users = get_users([
        'meta_key' => '_fcm_tokens', 'meta_compare' => 'EXISTS',
        'fields' => 'ID', 'number' => 100, 'offset' => (int) $q['offset'], 'orderby' => 'ID',
    ]);
    foreach ($users as $uid) {
        zzmore_send_push_to_user((int) $uid, $q['title'], $q['body'], ['type' => 'app_update', 'version_code' => (string) $q['version']]);
    }
    if (count($users) < 100) {
        delete_option('zzmore_update_push_queue');
        return;
    }
    $q['offset'] += 100;
    update_option('zzmore_update_push_queue', $q, false);
    wp_schedule_single_event(time() + 60, 'zzmore_update_push_batch');
});
