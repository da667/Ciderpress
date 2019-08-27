CiderPress - Hardened wordpress installer
You ever wanna self-host a blog or whatever, and are getting ready to choose something, and you're all like "Why not wordpress?" and your security nerd friends start to convulse and sperg out as though the seventh seal is breaking?
Then proceed to splain you how bad wordpress is? Well, this script is designed to shut them up, and make you a much harder target to hit. Remember that harder to hit doesn't mean invincible. Ask anyone who plays XCOM.

What purpose does this script serve?
Takes an ubuntu 18.04 linux install, and installs wordpress running on nginx. Why nginx? Personal preference, mainly.

What, specifically does the script do?
-Installs pre-reqs for Wordpress (e.g. nginx and php and various php extensions)
-Performs a TON of customizations that make it harder to attack and/or fingerprint your wordpress install, while customizing various aspects of operation. These tasks include:
--setting server_tokens to off to stop nginx from broadcasting what software version it is on error pages and in HTTP headers
--allow the user to define the wordpress installation directory, and defining that as the server's documentroot (defaults to /var/www/html/wordpress)
--allow the user to define the name of the wordpress database, database admin user, and password via configuration file
---these settings will be used to create a database for wordpress, and user for managing that database

--running several mysql_secure_installation statements to ensure that test users and databases are deleted prior to production use
--configuring SSL for the installation. The script generates a dhparams.pem file, and provides users a choice between using self-signed SSL or, provided they meet the requirements, utilizing letsencrypt as an SSL provider
---(you might wanna see the notes below for the dhparam.pem file generation, as well as the requirements for using letsencrypt)

-Installs a hardened site config for wordpress. The site config is tailored as follows:
--configured to auto-redirect all HTTP connections on port 80  to HTTPS on port 443
--nginx SSL settings are configured in accordance to best practices
--sets the document root directory to whatever the user specifies
--disables autoindexing for the entire site
--sets the client_max_body_size (nginx) as well as the post_max_size and upload_max_filesize settings to the user's specifications (max_upload)
--if a user requests a file that doesn't exist, it redirects them to index.php (could potentially mess with webapp scanners, etc.)
--if users request common CGI files that wordpress doesn't use (pl|cgi|py|rb|sh|lua) in any directory, they get denied.
--sets up caching for static resources (e.g. images and CSS files) to be held for the maximum amount of time

--denies access to a whole slew of files:
---wp-config.php
---license.txt
---xmlrpc.php
---wp-trackback.php
---anything beginning with a period "." or dollarsign "$"

--denies access to certain directories
---wp-admin (limited to only a single IP address or subnet as determined by the user)
---wp-admin/includes
---wp-includes/theme-compat
---wp-includes/js/tinymce/langs/*.php
---wp-includes/*.php
---wp-includes (set to "internal" only)
---wp-content (set to "internal" only
---wp-json

--configures wp-content/uploads to treat (html|htm|shtm|php|pl|py|pyc|jsp|asp|cgi|rb|sh|swf|lua) as the plaintext mimetype (they won't execute)

-created a wordpress plugin "ciderpress_plugin.php". This plugin performs the following tasks:
--disables meta tags in the site source code that could be used to fingerprint wordpress
--disables feed links in source code
--disables wordpress json (wp-json)
--disables REST api access and LINK http headers
--enables automatic updates for themes and wordpress plugins

-This script also (optionally) installs a few support shell scripts that automate a few things like:
--system updates. This script updates your system once weekly and reboots the system after the update completes
--automated backups. mysqldump the wordpress database, and copies the wordpress installation directory (defined by the user), then compresses them both together to /opt/bkup/wp-backup[timestamp].tar.gz
  then sets permissions to where only the root user can access the backups and backup directory
--automated backup trimming. automatically deletes any files from /opt/bkup that are more than 90 days old. modify the mtime parameter in the bkup_trimmer.sh script if you want this to be a larger amount of time.

Instructions for use:
1. Download this repo via git, or download the .zip file that github will provide you. Unzip it and fill out the ciderpress.conf file. 

2. ALL of the variables/configuration options MUST BE FILLED OUT.

2A: Its pretty important that you avoid special characters for the wp_mysql_password variable.
shell scripts treat special characters in unique ways that could cause this script to spontaenously combust, so I didn't bother trying to enumerate what special characters are safe.
Yeah, this goes against security advice security professionals typically give you, but can be offset if you just make the password longer. Like say, 25+ characters.
Download a password manager like say KeepassXC (https://keepassxc.org/) and use that to generate (and store) your password.
If not having special characters STILL doesn't set well with you, use mysqladmin to change the password later, and edit wp-config.php to use the new password you specify. 

2B: You might notice theres a section that involves using letsencrypt for a free SSL cert. If you want to use letsencrypt there are some prerequisites for that.
First, you need to ensure that the api can reach your web server on port 80/tcp since we'll be using the challenge/response method for getting our cert. That means poking holes in your firewall. 
Next, you need to ensure that your webserver has a public IP address, and a domain name that letsencrypt can resolve in order to get your SSL cert.
Freenom offers free hostnames for up to a year for a few TLDs. I have no idea if letsencrypt will work for dynamic DNS domains, but its something you are welcome to try. Good luck.
OTHERWISE, the script will generate a self-signed SSL certificate for use on your website, if you modify the config file to do so.
Yeah, web browsers will give you sad faces when you try to browse to it, and crypto nerds will scream bloody murder, but this is a Wendys, sir.

2C: You see that variable admin_net? That is the IP address you need to run the wordpress setup from, once this script completes by default this is set to 127.0.0.1. 
You're probably asking "Well, how do I run first-time setup? Especially on a headless linux server?" Use SSH tunnels. You'll need to have SSHD installed on your web server to do this.
Linux/OSX/Windows[10] ssh client: ssh -D 8080 [webserver IP here], log into the SSH service on your web server.
Set 127.0.0.1:8080 as your browser's SOCKS5 proxy, connect to https://127.0.0.1 and enjoy.
Windows putty: Connections > SSH > Tunnels > source port:8080, Destination [no ip address], dynamic, auto > click Add, save the session if desired, and connect to the web server's SSH service. 
Set 127.0.0.1:8080 as your browser's SOCKS5 proxy, connect to https://127.0.0.1 and enjoy.

3. The script has to be run as root, or via sudo privs because of all things we'll be doing that requires root privs (e.g. package installation, modifying file permissions, etc.)

4. bash ciderpress.sh or sudo bash ciderpress.sh should be enough to get the ball rolling

5. Your system WILL reboot as a part of this script.

Resources/References used to build this script: 
Suppress nginx version info: https://www.tecmint.com/hide-nginx-server-version-in-linux/
Mysql_secure_installation: https://mariadb.com/kb/en/library/mysql_secure_installation/
SSL Best Practice configuration for nginx: https://cipherli.st
Nginx wordpress hardening: http://blog.bigdinosaur.org/wordpress-on-nginx/
Additional nginx hardening configs: https://gist.github.com/julienbourdeau/a39acf5862600318bdd0
wordpress plugin hardening: https://ted.do/category/wordpress/
more wordpress plugin hardening: https://wp-mix.com/wordpress-disable-rest-api-header-links/
SSH dynamic tunnels/SOCKS5 proxying on Linux/Unix systems: https://www.tecmint.com/create-ssh-tunneling-port-forwarding-in-linux/ 
SSH dynamic tunnels/SOCKS5 proxying with putty: https://blog.devolutions.net/2017/4/how-to-configure-an-ssh-tunnel-on-putty
Are you wondering why we installed rng-tools? Its because it significantly improves RNG collection on VMs, and makes the dhparam.pem generation significantly faster on virtual machines: https://www.cyberciti.biz/open-source/debian-ubuntu-centos-linux-setup-additional-entropy-for-server-using-aveged-rng-tools-utils/