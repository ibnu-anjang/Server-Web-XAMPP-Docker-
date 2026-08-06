#!/bin/sh
set -e

# Pastikan folder yang ditulis web server (www-data) benar milik www-data.
# Karena src/ di-mount dari host, file di storage/bootstrap/cache bisa berganti
# kepemilikan (mis. saat artisan dijalankan sebagai root). Ini dirapikan tiap start.
if [ -d /var/www/html ]; then
  chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true
fi

exec "$@"