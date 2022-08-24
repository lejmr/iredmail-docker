#!/bin/sh

# Fix of paths
rm -f  /etc/pki/tls/private/iRedMail.key
ln -s /etc/ssl/private/iRedMail.key /etc/pki/tls/private/iRedMail.key

# Start Nginx
exec /usr/sbin/nginx -g "daemon off;"
