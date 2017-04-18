#docker rmi iredmail --force
#docker build --no-cache  -t iredmail:latest build
docker build -t iredmail:latest mysql
docker rm iredmail

#rm -rf tmp/mysql/* tmp/vmail/*
#docker run --privileged -p 80:80 -p 443:443 \
#           -v /Users/milos/tmp/iredmail/lejmr/tmp/mysql:/var/lib/mysql \
#           -v /Users/milos/tmp/iredmail/lejmr/tmp/vmail:/var/vmail \
#           --name=iredmail iredmail:latest /sbin/my_init

#docker run --privileged -p 80:80 -p 443:443 --name=iredmail iredmail:latest /sbin/my_init

docker run --privileged -p 80:80 -p 443:443 \
           -e "DOMAIN=lejmr.com" -e "HOSTNAME=mail" \
           -e "MYSQL_ROOT_PASSWORD=heslo" \
           -e "SOGO_WORKERS=1" \
           -e "IREDAPD_PLUGINS=['reject_null_sender', 'throttle', 'amavisd_wblist', 'sql_alias_access_policy']" \
           -e "POSTMASTER_PASSWORD={PLAIN}heslo" \
           --name=iredmail iredmail:latest


#  {SSHA}Q61OCjQ8niwkvZEoeeEusokemJhvC5QLCHh9Qg==
