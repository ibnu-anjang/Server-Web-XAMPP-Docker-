FROM php-laravel-base:latest

ARG HOST_UID=1000
ARG HOST_GID=1000

# Samakan uid/gid www-data dengan user host supaya file yang dibuat web
# dan file yang di-edit di host punya pemilik yang sama — tidak bentrok permission.
RUN groupmod -g ${HOST_GID} www-data && usermod -u ${HOST_UID} -g ${HOST_GID} www-data

COPY docker/php/apache-vhost.conf /etc/apache2/sites-available/000-default.conf
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html
RUN chown -R www-data:www-data /var/www/html

ENTRYPOINT ["entrypoint.sh"]
CMD ["apache2-foreground"]