#!/bin/sh

envsubst '$$PHOENIX_HOST $$PHOENIX_PORT' < /etc/nginx/nginx.conf.tpl > /etc/nginx/nginx.conf

exec "$@"
