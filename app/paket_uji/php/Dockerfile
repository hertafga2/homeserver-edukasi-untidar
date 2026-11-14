# PHP-FPM 8.3 dari paket resmi Alpine (tanpa kompilasi), dengan mysqli dan opcache.
# Pengaturan pool PHP-FPM memakai bawaan paket, sama di ketiga perangkat.
FROM alpine:3.23
RUN apk add --no-cache php83 php83-fpm php83-mysqli php83-opcache \
 && sed -i 's/^listen = .*/listen = 9000/' /etc/php83/php-fpm.d/www.conf
EXPOSE 9000
CMD ["php-fpm83", "-F"]
