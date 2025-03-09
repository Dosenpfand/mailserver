FROM alpine

RUN apk add restic postgresql-client bash msmtp curl --no-cache

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
RUN rm /var/spool/cron/crontabs/root
RUN echo '0 3 * * * bash /backup.sh' > /var/spool/cron/crontabs/root

ENTRYPOINT [ "/entrypoint.sh" ]

CMD busybox crond -f -l 0 -L /dev/stdout
