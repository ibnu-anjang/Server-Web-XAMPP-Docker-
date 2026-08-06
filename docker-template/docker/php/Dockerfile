FROM php-laravel-base:latest

ARG HOST_UID=1000
ARG HOST_GID=1000

# intl extension (dibutuhkan Laravel/Filament untuk formatting locale & number).
# Dipasang di image app (bukan base) supaya image base tetap utuh dan tiap project
# pasti dapat intl meski base-nya belum dibangun ulang.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libicu-dev \
    && docker-php-ext-configure intl \
    && docker-php-ext-install intl \
    && rm -rf /var/lib/apt/lists/*

# Samakan uid/gid www-data dengan user host supaya file bikinan web (www-data)
# dan file yang kamu edit di host punya pemilik yang sama -> tidak bentrok permission.
RUN groupmod -g ${HOST_GID} www-data && usermod -u ${HOST_UID} -g ${HOST_GID} www-data

COPY docker/php/apache-vhost.conf /etc/apache2/sites-available/000-default.conf

# Entry point: rapikan permission storage/bootstrap/cache tiap container start.
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html
RUN chown -R www-data:www-data /var/www/html

ENTRYPOINT ["entrypoint.sh"]
CMD ["apache2-foreground"]
