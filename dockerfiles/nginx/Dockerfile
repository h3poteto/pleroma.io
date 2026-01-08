FROM  nginx:1.29-alpine

ADD ./entrypoint.sh /var/opt/entrypoint.sh
ADD ./nginx.conf /etc/nginx/nginx.conf.tpl

ENTRYPOINT ["/var/opt/entrypoint.sh"]

CMD ["nginx", "-g", "daemon off;"]
