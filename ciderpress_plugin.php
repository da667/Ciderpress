<?php
/**
 * @package CiderPress
 * @version 1.0.0
 */
/*
Plugin Name: Cider Press
Plugin URI: https://github.com/da667/ciderpress
Description: This plugin is designed to harden wordpress. A lot of this plugin Ted Kruijff's blog ted.do/category/wordpress describing how to harden wordpress. This plugin disables a TON of functionality.
Author: da667, Ted Kruijff
Version: 1.0.0
Author URI: https://github.com/da667
*/
if (!defined('ABSPATH'))	{
	exit;
}

#Disable meta tags in sourcecode that can leak wordpress version information
add_filter('the_generator', '__return_false');
#Disable feed links in source code
add_filter('category_feed_link', '__return_false');
add_filter('feed_link', '__return_false');
#Disable wp-json
add_filter('json_enabled', '__return_false');
add_filter('json_jsonp_enabled', '__return_false');
#Disable pingback and x redirect by headers
add_filter('wp_headers', 'disable_x_headers');
function disable_x_headers($headers) {
	unset($headers['X-Pingback']);
	unset($headers['X-Redirected-By']);
	return $headers;
}
#disable rest api stuff and WP Link headers https://wp-mix.com/wordpress-disable-rest-api-header-links/
remove_action('wp_head', 'rest_output_link_wp_head', 10);
remove_action('wp_head', 'wp_oembed_add_discovery_links', 10);
remove_action('template_redirect', 'rest_output_link_header', 11, 0);
#wp-config should be configured to automate major and minor wp core updates, so we're just ensuring that themes and plugins get auto updates as well.
#https://wordpress.org/support/article/configuring-automatic-background-updates/
add_filter( 'auto_update_plugin', '__return_true' );
add_filter( 'auto_update_theme', '__return_true' );