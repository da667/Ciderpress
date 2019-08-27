#!/bin/bash
#This is a wordpress script for automating your wordpress installs, doing some basic housekeeping, as well as some hardening.
#Why am I writing a wordpress hardening and automation script in $current_year? Why not.

#Functions, functions everywhere.

# Logging setup. Ganked this entirely from stack overflow. Uses FIFO/pipe magic to log all the output of the script to a file. Also capable of accepting redirects/appends to the file for logging compiler stuff (configure, make and make install) to a log file instead of losing it on a screen buffer. This gives the user cleaner output, while logging everything in the background, for troubleshooting, analysis, or sending it to me for help.

logfile=/var/log/ciderpress_install.log
mkfifo ${logfile}.pipe
tee < ${logfile}.pipe $logfile &
exec &> ${logfile}.pipe
rm ${logfile}.pipe

########################################

#metasploit-like print statements. Gratuitously ganked from  Darkoperator's metasploit install script. status messages, error messages, good status returns. I added in a notification print for areas users should definitely pay attention to.

function print_status ()
{
    echo -e "\x1B[01;34m[*]\x1B[0m $1"
}

function print_good ()
{
    echo -e "\x1B[01;32m[*]\x1B[0m $1"
}

function print_error ()
{
    echo -e "\x1B[01;31m[*]\x1B[0m $1"
}

function print_notification ()
{
	echo -e "\x1B[01;33m[*]\x1B[0m $1"
}
########################################

#Script does a lot of error checking. Decided to insert an error check function. If a task performed returns a non zero status code, something very likely went wrong.

function error_check
{

if [ $? -eq 0 ]; then
	print_good "$1 successfully completed."
else
	print_error "$1 failed. Please check $logfile for more details."
exit 1
fi

}
########################################
#Package installation function.

function install_packages()
{

apt-get update &>> $logfile && apt-get install -y ${@} &>> $logfile
error_check 'Package installation'

}

########################################

#directory check. If the directory doesn't exist, create it and any necessary parent directories. If the directories already exist, simply continue.

function dir_check()
{

if [ ! -d $1 ]; then
	print_notification "$1 does not exist. Creating.."
	mkdir -p $1
else
	print_notification "$1 already exists."
fi

}

########################################
##BEGIN MAIN SCRIPT##

#Pre checks: These are a couple of basic sanity checks the script does before proceeding.

########################################

#These lines establish where ciderpress was executed. The config file _should_ be in this directory. the script exits if the config isn't in the same directory as the ciderpress shell script.

print_status "Checking for config file.."
execdir=`pwd`
if [ ! -f "$execdir"/ciderpress.conf ]; then
	print_error "ciderpress.conf was NOT found in $execdir. The script relies HEAVILY on this config file. Please make sure it is in the same directory you are executing the ciderpress script from!"
	exit 1
else
	print_good "Found config file."
fi

source "$execdir"/ciderpress.conf

########################################

#Are we root? We need to be root to perform a lot of the install tasks here.

print_status "Checking for root privs.."
if [ $(whoami) != "root" ]; then
	print_error "This script must be ran with sudo or root privileges."
	exit 1
else
	print_good "We are root."
fi
	 
########################################	 

#this is a nice little hack I found in stack exchange to suppress messages during package installation.
export DEBIAN_FRONTEND=noninteractive

# System updates
print_status "Performing apt-get update and upgrade (May take a while if this is a fresh install).."
apt-get update &>> $logfile && apt-get -y upgrade &>> $logfile
error_check 'System updates'

########################################

#Grabbing a bunch of prereq packages

print_status "Installing base packages: mariadb-server mariadb-client nginx php php-fpm php-pear php-cgi php-common php-zip php-mbstring php-net-socket php-gd php-xml-util php-mysql php-gettext php-bcmath rng-tools..  "
declare -a packages=( mariadb-server mariadb-client nginx php php-fpm php-pear php-cgi php-common php-zip php-mbstring php-net-socket php-gd php-xml-util php-mysql php-gettext php-bcmath rng-tools );
install_packages ${packages[@]}

########################################

#This block detects whether or not there was a failed/flubbed install we rely on the default site config for using letsencrypt/acme
#so if the backup file exists, we restore it. If it doesn't exist, then we make a backup so we can restore it if necessary

if [ -f /etc/nginx/defaultsite.bkup ]; then
	print_notification "Found backup of the original default site. Putting it back in place.."	
	cp /etc/nginx/defaultsite.bkup /etc/nginx/sites-available/default
	error_check 'default site restore'
else
	print_notification "Backing up default site in case of a flubbed install.."
	cp /etc/nginx/sites-available/default /etc/nginx/defaultsite.bkup
	error_check 'default site backup'
fi

########################################

#Ubuntu seems to think if you're installing PHP that you want apache. We like our web servers with more hardbass.
#Apache wants to be the web server. We don't want that. So we disable the service (to stop it from trying to take over port 80/443 on startup) and stop the service. Then tell nginx to restart
#To take its rightful place as the king of hardbass web servers.

print_status "Disabling and shutting down apache2.."
systemctl disable apache2.service &>> $logfile
error_check 'Disabling apache2'
systemctl stop apache2.service &>> $logfile
error_check 'Stopping apache2'
systemctl restart nginx.service &>> $logfile
error_check 'Restarting nginx'

########################################

#We need to pull the php version we're running so we can tell wordpress the correct path to the php FPM unix socket.
phpver=`php -v | head -1 | cut -d" " -f2 | cut -d"." -f1,2`

########################################

#Disable the server_tokens directive.
#This will prevent nginx from returning its version in HTTP headers and/or error pages.

print_notification "Disabling nginx server tokens.."
sed -i "s/# server_tokens/server_tokens/" /etc/nginx/nginx.conf
error_check 'server_tokens modification'

########################################

#Database cleanup.
#this section involves running some of the stuff from mysql_secure_installation, except requiring no user intervention
#We don't bother setting a password for the mysql root user, because the password never gets used
#mysql-server and mariadb use unix-socket based auth for the root database user
#long story short: if you're the root system user, you get to access to the database as the root database user too
#Implication is that password bruteforcing the root mysql account is pointless, but privesc to root means you get the root database user too. Which, is sort of implied when you get the root user on a system anyhow.
#documentation: https://mariadb.com/kb/en/library/authentication-plugin-unix-socket/

print_status "Running mysql_secure_installation commands.."

#This blob of mysql commands is removing null users, verifying that remote access as the root database user is disabled for the database, and verifying that any test databases are removed.

mysql -uroot -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'; FLUSH PRIVILEGES;" &>> $logfile
error_check 'mysql_secure_installation commands'

#Then we also create the wordpress database user, the database we'll be using for the install, and assign privs to the wordpress database user to be able to manage the database
#If the user already exists, we assume the user wants to replace it. If the database already exists, we assume that the user wants to continue using that same database name.

print_status "Adding the wordpress database, and granting access to the wordpress database user.."
mysql -uroot -e "CREATE OR REPLACE USER '$wp_db_user'@'localhost' identified by '$wp_mysql_password'; CREATE DATABASE IF NOT EXISTS $wp_database_name; GRANT ALL PRIVILEGES ON $wp_database_name.* TO '$wp_db_user'@'localhost';" &>> $logfile
error_check 'wordpress database and user creation'

########################################

#SSL setup. User is given an option to use LE, or go self-signed. Privacy nerds and SSL snobs be damned.
#certificate, key, and dhparams are installed to /etc/nginx/ssl, and file permissions are configured to where only root can access the directory and files (once they are generated)
#If use_letsecnrypt is set to 1, we'll be downloading and executing the shell script version of the acme client, and running it in nginx mode.
#Yeah, its a wget | bash script. No, I don't care that this rattles your bones.
#The shell script gets installed to ~/.acme (so in this case, root's home directory), which is where we'll be running it.
#In order to run the script successfully, we have to set the server_name in nginx to the domain name specified in the acme client, otherwise, the client barfs.
#If its successful, a subdirectory with all of the SSL setup information (private key, cert, intermediary certs, the full bundle, plus the CSR) are dumped into a subdirectory that matches the domain name you requested.
#We re-run acme with parameters to install/reload the cert/private key to /etc/nginx/ssl, make the directory permissions to where only root can access it, and make the files readable and writable by the root user only.
#If use_letsencrypt is set to anything other than 1, we generate a self-signed SSL cert and key, and dump it into /etc/nginx/ssl instead.

print_status "Configuring SSL.."

dir_check /etc/nginx/ssl
chmod 700 /etc/nginx/ssl

print_status "Generating dhparam.pem.."
print_notification "This is going to take some time. On my VM on a modern server, this took about 5 minutes. Your results could be faster or slower, depending on hardware."
print_notification "If you want to check progress, open another terminal session and run the command tail -f /var/log/ciderpress_install.log"
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 4096 &>> $logfile
error_check 'dhparam.pem file creation'

if [[ $use_letsencrypt == "1" ]]; then
	print_status "Downloading, installing, and executing letsencrypt ACME bash client.."
	curl https://get.acme.sh | sh &>> $logfile
	error_check 'acme script download'
	sed -i "s#server_name _;#server_name $wp_hostname;#" /etc/nginx/sites-available/default &>> $logfile
	error_check 'nginx server_name modification'
	cd /root/.acme.sh
	bash acme.sh --issue --nginx -d $wp_hostname &>> $logfile
	error_check 'certificate request'
	bash acme.sh --install-cert -d $wp_hostname --key-file /etc/nginx/ssl/key.pem --fullchain-file /etc/nginx/ssl/cert.pem --reloadcmd "service nginx force-reload" &>> $logfile
	error_check 'certificate and key install to /etc/nginx/ssl'
else
    print_status "Generating self-signed SSL cert and key.."
	cd /etc/nginx/ssl
	openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=Nevada/L=LasVegas/O=Security/CN=$wp_hostname" -keyout key.pem  -out cert.pem &>> $logfile
	error_check 'SSL certificate and key generation to /etc/nginx/ssl'
fi

chmod 600 /etc/nginx/ssl/*.pem &>> $logfile
error_check 'ssl cert and key permission modification'

########################################

#Time to generate our nginx site config. First, we move the nginx site config to sites-available and copy it over the original default site. 

print_notification "replacing default site with wordpress site config.."

cp $execdir/wordpress /etc/nginx/sites-available/default &>> $logfile
error_check 'replacement of default nginx site'

#next, we have to replace a couple of variables in the site config and php.ini file with the user's settings out of the ciderpress.conf file

print_notification "adding configuration settings from ciderpress.conf to wordpress site config, and /etc/php/$phpver/fpm/php.ini.."

sed -i "s#\$wp_hostname#$wp_hostname#g" /etc/nginx/sites-available/default &>> $logfile
sed -i "s#\$max_upload#$max_upload#" /etc/nginx/sites-available/default &>> $logfile
sed -i "s#\$wp_basedir#$wp_basedir#" /etc/nginx/sites-available/default &>> $logfile
sed -i "s#\$phpver#$phpver#" /etc/nginx/sites-available/default &>> $logfile
sed -i "s#\$admin_net#$admin_net#" /etc/nginx/sites-available/default &>> $logfile
error_check 'site config editing'
sed -i "s#post_max_size = 8M#post_max_size = $max_upload#" /etc/php/$phpver/fpm/php.ini &>> $logfile
sed -i "s#upload_max_filesize = 2M#upload_max_filesize = $max_upload#" /etc/php/$phpver/fpm/php.ini &>> $logfile
error_check 'php.ini editing'


#Grabbing and unzipping the latest wordpress install. Unlike snort.org, they actually have their s**t together and have a "latest.tar.gz" link.
#Once we grab and extract the tarball, delete it.
#Why? the tarball is an installer artifact that can fingerprint your installation

print_status "Grabbing and inflating the latest Wordpress tarball.."
dir_check $wp_basedir
cd $wp_basedir
wget https://wordpress.org/latest.tar.gz &>> $logfile
error_check 'wordpress download'
tar --strip-components=1 -xzvf latest.tar.gz &>> $logfile
error_check 'wordpress file installation'
rm -rf latest.tar.gz &>> $logfile

########################################

#Have to modify and configure the wp-config-sample.php file. Here is what needs to be done:
#Enter the username, password, and database name for the mysql database wordpress will be dumping its schema to
#Grabbing some RNG keys and salts via https://api.wordpress.org/secret-key/1.1/salt/ 
#adding an option to explicitly ensure that both minor and major core wordpress updates are automatically installed
#afterwards. we change file permissions to where only www-data user and group can access the wp-config.php file

print_status "Setting up wp-config for first-time use.."

cp $wp_basedir/wp-config-sample.php $wp_basedir/wp-config.php.tmp &>> $logfile
sed -i "s#database_name_here#$wp_database_name#" $wp_basedir/wp-config.php.tmp &>> $logfile
sed -i "s#username_here#$wp_db_user#" $wp_basedir/wp-config.php.tmp &>> $logfile
sed -i "s#password_here#$wp_mysql_password#" $wp_basedir/wp-config.php.tmp &>> $logfile
echo "//ensuring that wordpress core major and minor updates are AUTOMATICALLY installed" >> $wp_basedir/wp-config.php.tmp
echo "define( 'WP_AUTO_UPDATE_CORE', true);" >> $wp_basedir/wp-config.php.tmp
mv $wp_basedir/wp-config.php.tmp $wp_basedir/wp-config.php &>> $logfile
chmod 660 $wp_basedir/wp-config.php &>> $logfile
error_check 'wp-config.php setup'

########################################

#Setting up ciderpress_plugin.php
#all we're doing is making sure that $wp_basedir/wp-content/plugins exists, and if it doesn't create it and drop the plugin script there.

dir_check $wp_basedir/wp-content/plugins
cp $execdir/ciderpress_plugin.php $wp_basedir/wp-content/plugins &>> $logfile
error_check 'ciderpress plugin installation'

########################################

#set up file permissions to where www-data owns everything in the wordpress installation directory

print_status "Granting recursive ownership of $wp_basedir to www-data.."
chown -R www-data:www-data $wp_basedir &>> $logfile
error_check 'file permission editing'

########################################

#automation scripts. start by creating /root/adm_scripts directory
print_status "Setting up maintenance scripts.."
print_notification "All maintenance scripts enabled are installed at: /root/adm_scripts"
print_notification "All jobs are scheduled via /etc/crontab"
dir_check /root/adm_scripts
chmod 700 /root/adm_scripts &>> $logfile
#checking to see if /etc/crontab is backed up. It means that this script failed. We don't want multiple duplicate jobs, so if there is backup, restore it. If not, make one in case the script bombs.

if [ -f /etc/crontab.bkup ]; then
	print_notification "Found backup of the original crontab. Putting it back in place.."	
	cp /etc/crontab.bkup /etc/crontab &>> $logfile
	error_check 'crontab restore'
else
	print_notification "Backing up crontab in case of a flubbed install.."
	cp /etc/crontab /etc/crontab.bkup &>> $logfile
	error_check 'crontab backup'
fi

#sets up update automation, and configures the job to run at 5am weekly on monday.
if [[ $update_automation == "1" ]]; then
	print_status "setting up update automation.."
	cp $execdir/updater /root/adm_scripts/updater &>> $logfile
	chmod 700 /root/adm_scripts/updater &>> $logfile
	error_check "update script installation" >> /etc/crontab
	echo "#update automation. installed via ciderpress.sh. remove the line below to disable this" >> /etc/crontab
	echo "0 5    * * 1   root    /bin/bash /root/adm_scripts/updater" >> /etc/crontab
	grep updater /etc/crontab &>> $logfile
	error_check 'update automation cron job addition'
else
	print_notification "skipping update automation"
fi

#Sets up automated backups. this script will backup the wordpress installation directory and the wordpress database (via mysqldump as root -- doesn't need creds, which is neat), then make a tarball in /opt/bkup
#We then delete the db dump and copied wordpress directory. /opt/wp_backup is restricted to the root user only, and the database backups can only be read by the root user. 
#Each backup has the date the backup was ran in the filename.
if [[ $backup_automation == "1" ]]; then
	print_status "setting up backup automation.."
	cp $execdir/wp_backup /root/adm_scripts/wp_backup &>> $logfile
	sed -i "s#\$wp_basedir#$wp_basedir#" /root/adm_scripts/wp_backup
	sed -i "s#\$wp_database_name#$wp_database_name#" /root/adm_scripts/wp_backup
	chmod 700 /root/adm_scripts/wp_backup &>> $logfile
	error_check "backup script installation" >> /etc/crontab
	dir_check /opt/bkups
	chmod 700 /opt/bkups
	echo "#backup automation. installed via ciderpress.sh. remove the line below to disable this" >> /etc/crontab
	echo "30 5    * * 1   root    /bin/bash /root/adm_scripts/wp_backup" >> /etc/crontab
	grep wp_backup /etc/crontab &>> $logfile
	error_check 'backup automation cron job addition'
else
	print_notification "skipping backup automation"
fi

#sets up automated backup trimming. This script is running find against /opt/bkups
if [[ $backup_trimming == "1" ]]; then
	print_status "setting up backup trim automation.."
	cp $execdir/bkup_trimmer /root/adm_scripts/bkup_trimmer &>> $logfile
	chmod 700 /root/adm_scripts/bkup_trimmer &>> $logfile
	error_check "#updater script installation" >> /etc/crontab
	echo "#backup trim automation. installed via ciderpress.sh. remove the line below to disable this" >> /etc/crontab
	echo "0 6    * * 1   root    /bin/bash /root/adm_scripts/bk_trimmer" >> /etc/crontab
	grep bkup_trimmer /etc/crontab &>> $logfile
	error_check 'backup trim cron job addition'
else
	print_notification "skipping update automation"
fi