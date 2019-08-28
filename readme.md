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
	* a single IP address or subnet that is authorized to access wp-admin
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
	* Adds a block that sets the `WP_SITEURL` and `WP_HOME` to `https://127.0.0.1` if the `REMOTE_ADDR` is `127.0.0.1`
		* This is specifically for limiting access to wp-admin (more on this in a moment)
* Installs a custom wordpress plugin `ciderpress_plugin.php` that performs several hardening tasks:
	* Disables meta tags in site source code to make fingerprinting harder
	* Disables feed links in the site source code
	* Disables wordpress JSON (wp-json)
	* Disables REST API access
	* Disables LINK http headers
	* Attempts to unset the X-Pingback header
	* Attempts to unset the X-Redirected-By header
	* Forces automatic updates for wordpress plugins and themes
* (Optionally) installs some scripts for system housekeeping. These scripts include:
	* `updater`, which as the name implies, pulls the latest updates and reboots the system
	* `wp_bkup`, makes a copy of the wordpress install directory, and a mysqldump of the database, creates a .tar.bz2 file of this data, and dumps it to /opt/bkups, then deletes the original files.
		* /opt/bkup is configured to where only the root user can access it
		* Individual backup tar.bz2 files are date timestamped, and configured to where only root can access them
	* `bkup_trimmer`, which runs a find statement that deletes backup files in /opt/bkups that are older than 90 days
	* If configured, these scripts are added to /etc/crontab
		* `updater` runs at 5am
		* `wp_bkup` runs at 5:30am
		* `bkup_trimmer` runs at 6:30am
		* If these times are NOT agreeable, edit /etc/crontab to suit your needs (Check out https://crontab.guru to test your crontab edits)

## Instructions for use:
1. Download this repo via git, or download the .zip file that github will provide you. Unzip it and fill out the `ciderpress.conf` file. The file is heavily commented with default settings and recommendations  

2. Make sure that you read the comments in the file and fill out *ALL* of the variables in the `ciderpress.conf` file
 	1. Its pretty important that you avoid special characters for the `wp_mysql_password` variable.
shell scripts treat special characters in unique ways that could cause this script to spontaenously combust, so I didn't bother trying to enumerate what special characters are safe.
Yeah, this goes against security advice security professionals typically give you, but can be offset if you just make the password longer. Like say, 25+ characters. Download a password manager like say KeepassXC (https://keepassxc.org/) and use that to generate (and store) your password. If not having special characters STILL doesn't set well with you, use the `mysqladmin` command to change the password later, and edit `wp-config.php` in your wordpress directory to use the new password you specify.  

	2. You might notice theres a section that involves using letsencrypt for a free SSL cert. If you want to use letsencrypt there are some prerequisites for that. First, you need to ensure that the api can reach your web server on port 80/tcp since we'll be using the challenge/response method for getting our cert. That means poking holes in your firewall. Next, you need to ensure that your webserver has a public IP address, and a domain name that letsencrypt can resolve in order to get your SSL cert.
Freenom offers free hostnames for up to a year for a few TLDs. I have no idea if letsencrypt will work for dynamic DNS domains, but its something you are welcome to try. Good luck. OTHERWISE, the script will generate a self-signed SSL certificate for use on your website, if you modify the config file to do so. Yeah, web browsers will give you sad faces when you try to browse to it, and crypto nerds will scream bloody murder, but this is a Wendys, sir.
	3. You see that variable `admin_net`? That is the IP address you need to run the wordpress setup from, once this script completes by default this is set to 127.0.0.1.  You're probably asking 
		>Well, how do I run first-time setup? Especially on a headless linux server? 

		Use SSH tunnels. You'll need to have SSHD installed on your web server and some sort of an SSH client that supports tunneling to do this.  
        
        Linux/OSX/Windows[10] ssh client: ssh -D 8080 [webserver IP here], log into the SSH service on your web server.
Set 127.0.0.1:8080 as your browser's SOCKS5 proxy, connect to https://127.0.0.1 and enjoy.  

		Windows putty: Connections > SSH > Tunnels > source port:8080, Destination [no ip address], dynamic, auto > click Add, save the session if desired, and connect to the web server's SSH service.
Set 127.0.0.1:8080 as your browser's SOCKS5 proxy, connect to https://127.0.0.1 and enjoy.

3. The script has to be run as root, or via sudo privs because of all things we'll be doing that requires root privs (e.g. package installation, modifying file permissions, etc.)
4. `bash ciderpress.sh` or `sudo bash ciderpress.sh` should be enough to get the ball rolling. The script keeps a log of the output of all the commands it runs in /var/log/ciderpress_install.log. This file can be used to help troubleshoot failures if the script bombs out.
	1. theres a portion of the script that generates a `dhparam.pem` file. The script warns you that it'll take some time to do. Its no joke. Its gonna take about 15 or so minutes on a moderately powerful system, and the CPU is gonna kick and scream the entire time. If you wanna make sure that the script is still running, open up another terminal session (e.g. second SSH session, etc.) and run the command tail -f /var/log/ciderpress_install.log
5. Your system WILL reboot as a part of this script.

## References:
* Suppress nginx version info: https://www.tecmint.com/hide-nginx-server-version-in-linux/  
* Mysql_secure_installation: https://mariadb.com/kb/en/library/mysql_secure_installation/  
* SSL Best Practice configuration for nginx: https://cipherli.st  
* Nginx wordpress hardening: http://blog.bigdinosaur.org/wordpress-on-nginx/  
* Additional nginx hardening configs: https://gist.github.com/julienbourdeau/a39acf5862600318bdd0  
* wordpress plugin hardening: https://ted.do/category/wordpress/  
* more wordpress plugin hardening: https://wp-mix.com/wordpress-disable-rest-api-header-links/  
* enforcing auto updates, even on major releases, themes and plugins: https://wordpress.org/support/article/configuring-automatic-background-updates/  
* SSH dynamic tunnels/SOCKS5 proxying on Linux/Unix systems: https://www.tecmint.com/create-ssh-tunneling-port-forwarding-in-linux/   
* SSH dynamic tunnels/SOCKS5 proxying with putty: https://blog.devolutions.net/2017/4/how-to-configure-an-ssh-tunnel-on-putty  
* Access wp-admin via localhost/dynamic SSH tunnel: https://wordpress.stackexchange.com/questions/186272/how-to-deal-with-wordpress-on-localhost  
* Are you wondering why we installed rng-tools? Its because it significantly improves RNG collection on VMs, and makes the dhparam.pem generation significantly faster on virtual machines: https://www.cyberciti.biz/open-source/debian-ubuntu-centos-linux-setup-additional-entropy-for-server-using-aveged-rng-tools-utils/  
* Why didn't we generate salts and keys in wp-config.php? Because wordpress will generate them on its own on first setup.