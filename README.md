# iRedMail Docker Container #

iRedMail allows to deploy an OPEN SOURCE, FULLY FLEDGED, FULL-FEATURED mail server in several minutes, for free. If several minutes is long time then this docker container can reduce help you and deploy your mail server in seconds.

Current version of container uses MySQL for accounts saving. In the future the LDAP can be used, so pull requests are welcome. Container contains all components (Postfix, Dovecot, Fail2ban, ClamAV, Roundcube, and SoGo) and MySQL server. In order to customize container several environmental variables are allowed:

  * DOMAIN -  Primary domain which is used for iRedMail instalation (example.com)
  * HOSTNAME - server name (mail, so FQDN will be mail.example.com)
  * MYSQL_ROOT_PASSWORD - Root password for MySQL server installation
  * POSTMASTER_PASSWORD - Initial password for postmaster@DOMAIN. Password can be generated according to [wiki](http://www.iredmail.org/docs/reset.user.password.html). ({PLAIN}password)
  * TIMEZONE - Container timezone that is propagated to other components
  * SOGO_WORKERS - Number of SOGo workers which can affect SOGo interface performance.

Container is prepared to handle data as persistent using mounted folders for data. Folders prepared for initialization are:PATH/

 * /var/lib/mysql
 * /var/vmail
 * /var/lib/clamav

With all information prepared, let's test your new iRedMail server:

```
docker run --privileged -p 80:80 -p 443:443 \
           -e "DOMAIN=example.com" -e "HOSTNAME=mail" \
           -e "MYSQL_ROOT_PASSWORD=password" \
           -e "SOGO_WORKERS=1" \
           -e "TIMEZONE=Europe/Prague" \
           -e "POSTMASTER_PASSWORD={PLAIN}password" \
           -e "IREDAPD_PLUGINS=['reject_null_sender', 'reject_sender_login_mismatch', 'greylisting', 'throttle', 'amavisd_wblist', 'sql_alias_access_policy']" \
           -v PATH/mysql:/var/lib/mysql \
           -v PATH/vmail:/var/vmail \
           -v PATH/clamav:/var/lib/clamav \
           --name=iredmail lejmr/iredmail:mysql-latest

```

## How to upgrade from 0.9.5-1
iRedMail v0.9.6 changes structure of its persistent store, so as changes format of SoGo cache:
 * http://www.iredmail.org/docs/upgrade.sogo.combined.sql.tables.html
 * http://www.iredmail.org/docs/upgrade.iredmail.0.9.5.1-0.9.6.html#mysqlmariadb-backend-special

In order to apply changes upgrade process is as follows:

 - Stop and remove current container ```docker rm -f iredmail```
 - Update image ```docker pull lejmr/iredmail:mysql-0.9.6```
 - Start iRedmail from newer image
 - Initiate upgrade ```rm $tmpf```
 
 



