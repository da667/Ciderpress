# CiderPress - Hardened wordpress installer

You ever wanna self-host a blog or whatever, and are getting ready to choose something, and you're all like `"Why not wordpress?"` and your security nerd friends start to convulse and sperg out as though the seventh seal is breaking?

Then proceed to splain you how bad wordpress is? Well, this script is designed to shut them up, and make you a much harder target to hit. Remember that harder to hit doesn't mean invincible. Ask anyone who plays XCOM.

## What Purpose Does this Script Serve?

Takes an ubuntu 18.04 linux install, and installs wordpress running on nginx. 
> Why nginx? 

Personal preference, mainly.

## What, specifically does the script do?

* Installs pre-reqs for Wordpress (e.g. nginx and php and various php extensions)  
* Performs a TON of customizations that make it harder to attack and/or fingerprint your wordpress install, while customizing various aspects of operation. 

### These tasks include:
* setting `server_tokens` to off to stop nginx from broadcasting what software version it is on error pages and in HTTP headers
* ensures that `www-data` user/group owns the wordpress installation directory recursively
* allowing the user to define various aspects of their wordpress installation via config file  
	* root directory wordpress will be installed and served from
	* wordpress database name
	* wordpress database username and password
	* hostname for the instance (important if you plan on using letsencrypt -- more on that later)
	* whether or not you want to use LetsEncrypt or a self-signed SSL cert
	* maximum file upload size
	* enabling weekly patching/system reboot, weekly backups and a weekly job to trim backups older than 90 days

* running `mysql_secure_installation` queries to ensure test users and instances are properly removed  
* Configuring SSL for the installation
	* As previously mentioned, you can use LetsEncrypt, or Self-signed Certs
	* Generates a `dhparam.pem`
	* Configures SSL according to cipherli.st best practices
	* Configures nginx to redirect all HTTP requests to HTTPS automatically
	* Drops all pem files into `/etc/nginx/ssl` and sets file permissions to where only the root user can access it

* Disables `autoindex` for the entire site so you don't serve directory contents by accident
* If a user requests a file/directory that doesn't exist and isn't explicitly 403'd they get redirected to `index.php`
* Configures maximum age for caching static resources (e.g. image files and CSS)
* Specifically denies access to a host of files and directories:
	* wp-config.php
	* license.txt
	* readme.html
	* wp-trackback.php
	* xmlrpc.php
	* wp-cron.php
	* any file beginning with a period (.)
	* any file beginning with dollar sign ($)
	* /wp-json
	* wp-admin/includes
	* wp-includes/theme-compat/
	* wp-includes/js/tinymce/langs/*.php
	* configures /wp-includes/ and /wp-content/ to `internal` only

* Prevents the execution of common CGI script file extensions (pl|cgi|py|rb|sh|lua)
* Prevents the execution of several commonly abused scripting extension in /wp-content/uploads (html|htm|shtm|php|pl|py|pyc|jsp|asp|cgi|rb|sh|swf|lua) by setting their default MIME type to text/plain
* Makes some customizations to wp-config.php, specifically:
	* Enforces automatic wordpress core updates. Yes, even major updates.
* Installs and enables a custom wordpress plugin `ciderpress_plugin.php` that performs several hardening tasks:
	* Disables meta tags in site source code to make fingerprinting harder
	* Disables feed links in the site source code
	* Disables wordpress JSON (wp-json)
	* Disables REST API access
	* Disables LINK http headers
	* Attempts to unset the X-Pingback header
	* Attempts to unset the X-Redirected-By header
	* Forces automatic updates for wordpress plugins and themes
* Installs and enables the login-lockdown plugin to limit brute-force attempts
* Installs (but doesn't enable) the google-authenticator plugin for enabling two-factor authentication for your wordpress accounts
* (Optionally) installs some scripts for system housekeeping. These scripts include:
	* `updater`, which as the name implies, pulls the latest updates and reboots the system
	* `wp_bkup`, makes a copy of the wordpress install directory, and a mysqldump of the database, creates a .tar.bz2 file of this data, and dumps it to /opt/bkups, then deletes the original files.
		* /opt/bkup is configured to where only the root user can access it
		* Individual backup tar.bz2 files are date timestamped, and configured to where only root can access them
	* `bkup_trimmer`, which runs a find statement that deletes backup files in /opt/bkups that are older than 90 days
	* If configured, these scripts are added to /etc/crontab
		* `updater` runs at 5am
		* `wp_bkup` runs at 5:30am
		* `bkup_trimmer` runs at 6:00am
		* If these times are NOT agreeable, edit /etc/crontab to suit your needs (Check out https://crontab.guru to test your crontab edits)

## Instructions for use:
1. Download this repo via git, or download the .zip file that github will provide you. Unzip it and fill out the `ciderpress.conf` file. The file is heavily commented with default settings and recommendations  

2. Make sure that you read the comments in the file and fill out *ALL* of the variables in the `ciderpress.conf` file
 	1. Its pretty important that you avoid special characters for the `wp_mysql_password` variable.
shell scripts treat special characters in unique ways that could cause this script to spontaenously combust, so I didn't bother trying to enumerate what special characters are safe.
Yeah, this goes against security advice security professionals typically give you, but can be offset if you just make the password longer. Like say, 25+ characters. Download a password manager like say KeepassXC (https://keepassxc.org/) and use that to generate (and store) your password. If not having special characters STILL doesn't set well with you, use the `mysqladmin` command to change the password later, and edit `wp-config.php` in your wordpress directory to use the new password you specify.  

	2. You might notice theres a section that involves using letsencrypt for a free SSL cert. If you want to use letsencrypt there are some prerequisites for that. First, you need to ensure that the api can reach your web server on port 80/tcp since we'll be using the challenge/response method for getting our cert. That means poking holes in your firewall. Next, you need to ensure that your webserver has a public IP address, and a domain name that letsencrypt can resolve in order to get your SSL cert.
Freenom offers free hostnames for up to a year for a few TLDs. I have no idea if letsencrypt will work for dynamic DNS domains, but its something you are welcome to try. Good luck. OTHERWISE, the script will generate a self-signed SSL certificate for use on your website, if you modify the config file to do so. Yeah, web browsers will give you sad faces when you try to browse to it, and crypto nerds will scream bloody murder, but this is a Wendys, sir.
	3. The variable `wp_hostname` is very important. Make sure that this is set to a fully qualified domain name that your clients can resolve, otherwise your wordpress install will be horribly broken. You can also try setting this to an IP address if you don't want to bother with DNS, but I haven't tested it, so I have no idea if that'd work. At the very least, if you did this, you will NOT be able to get a letsencrypt ssl cert. The script has to be run as root, or via sudo privs because of all things we'll be doing that requires root privs (e.g. package installation, modifying file permissions, etc.)
4. `bash ciderpress.sh` or `sudo bash ciderpress.sh` should be enough to get the ball rolling. The script keeps a log of the output of all the commands it runs in /var/log/ciderpress_install.log. This file can be used to help troubleshoot failures if the script bombs out.
	1. theres a portion of the script that generates a `dhparam.pem` file. The script warns you that it'll take some time to do. Its no joke. Its gonna take about 15 or so minutes on a moderately powerful system, and the CPU is gonna kick and scream the entire time. If you wanna make sure that the script is still running, open up another terminal session (e.g. second SSH session, etc.) and run the command tail -f /var/log/ciderpress_install.log
5. Your system WILL reboot as a part of this script.
	1. This script installs several plugins and enables a few of them for you automatically. However, one of these plugins, google-authenticator needs to be activated manually. This is because you need to login to the wordpress console to set up  two-factor authentication for your admin user (and other users you might add later).
		1. Make sure that your web server can keep accurate time. 2FA relies heavily on time for your server being relatively accurate. Be aware that if you are running wordpress in a VM and you revert a snapshot, you might need to update the system clock/time. Consider looking into NTP or the hwlock -s command.

## References:
* Suppress nginx version info: https://www.tecmint.com/hide-nginx-server-version-in-linux/  
* Mysql_secure_installation: https://mariadb.com/kb/en/library/mysql_secure_installation/  
* SSL Best Practice configuration for nginx: https://cipherli.st  
* Nginx wordpress hardening: http://blog.bigdinosaur.org/wordpress-on-nginx/  
* Additional nginx hardening configs: https://gist.github.com/julienbourdeau/a39acf5862600318bdd0  
* wordpress plugin hardening: https://ted.do/category/wordpress/  
* more wordpress plugin hardening: https://wp-mix.com/wordpress-disable-rest-api-header-links/  
* disabling access to the plugin and theme editor: https://www.wpbeginner.com/wp-tutorials/how-to-disable-theme-and-plugin-editors-from-wordpress-admin-panel/
* enforcing auto updates, even on major releases, themes and plugins: https://wordpress.org/support/article/configuring-automatic-background-updates/  
* Are you wondering why we installed rng-tools? Its because it significantly improves RNG collection on VMs, and makes the dhparam.pem generation significantly faster on virtual machines: https://www.cyberciti.biz/open-source/debian-ubuntu-centos-linux-setup-additional-entropy-for-server-using-aveged-rng-tools-utils/  
* How to configure the google-authenticator plugin: https://wordpress.org/plugins/google-authenticator/#installation
* SSL configuration for nginx: https://cipherli.st

## Patch Notes:
### 2019-08-30
* Decided that attempting to blog access to wp-admin via IP address wasn't the way forward(tm). As in, I thought it worked fine, but it was one of those "Works great on my machine!" moments they tell you about in cyber school. You don't think it'll happen until it happens to you.  
* `wp-cli` is a thing that exists and is insanely useful for handling various aspects of installing and configuring wordpress. I've switched the script over to using wp-cli to download, install, perform initial configuration, enable and install plugins as a part of the script  
* wp-cli gets installed as /usr/sbin/wp. Be aware: if you use wp to install themes/plugins/make changes, you'll likely be doing it as root or via sudo.
	* in order to run wp-cli commands as root, you need to add the option `--allow-root` in order for it to run without puking. You also need to run wp-cli from the directory you installed wordpress to (`wp_basedir`)
	* if you install/add/modify things with the wp-cli (`/usr/sbin/wp`) make sure you run the command `[sudo] chown -R www-data:www-data /path/to/wordpress` otherwise you'll probably get file permission errors everywhere.
* there are two new parameters for you to fill out in ciderpress.conf, `wp_site_admin`, and `wp_site_password`. These control the name of your wordpress admin account and its password for logging in to your wordpress instance. Pretty self-explanatory.  
* ciderpress_plugin.php is now activated as a part of the install script, instead of just being installed  
* login-lockdown is installed and activated as a part of the install process. Defaults to blocking an IP for 1 hour after 3 failed logins in 5 minutes or less. This can be edited once you log in to your wordpress instance.  
* google-authenticator is installed as a part of the script. login to wp-admin to activate it and configure your admin account for two-factor auth: https://wordpress.org/plugins/google-authenticator/#installation  
* HSTS doesn't work with self-signed certs, so if you opted to use a self-signed cert, we disable that configuration setting. If you change this later to a non self-signed cert, uncomment line 36 in /etc/nginx/sites-available/default  
* Added in a hardening customization to wp-config.php that disables the plugin and theme editor in the admin console.