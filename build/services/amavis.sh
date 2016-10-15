#!/bin/sh

logger DEBUG Starting amavisd-new
exec /usr/sbin/amavisd-new foreground
