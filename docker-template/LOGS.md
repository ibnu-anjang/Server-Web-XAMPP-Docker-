# Logs — Docker PHP Project Template

Catatan semua perubahan yang dibuat pada template ini.

---

## Sesi April 2026

### `new-project.sh` — Script utama
- **Dibuat dari awal** sebagai script otomatis untuk generate project baru
- Argumen: `nama-project`, `--php` (PHP Native), `--port XXXX`
- Auto-detect port kosong dari container yang sedang aktif (via `docker ps`, bukan baca `.env`)
- Password DB format readable: `nama-project-XXXXXX` (bukan hex acak)
- `trap cleanup EXIT` — rollback otomatis (hapus folder + container) kalau script gagal
- Menghapus file template dari hasil copy: `new-project.sh`, `README.md`, `src/.gitkeep`
- Fix Laravel 13: `DB_CONNECTION` default sqlite → ditulis ulang ke mysql lengkap
- Step 1: cek/build `php-laravel-base` image dulu sebelum mulai

### `Makefile` — Di-generate tiap project baru
- Target: `up`, `down`, `start`, `stop`, `restart`, `build`, `logs`, `bash`, `artisan`, `migrate`, `fresh`, `tinker`, `destroy`
- `make destroy` — matikan container + hapus volume + hapus image project + hapus folder (pakai `sudo rm -rf` untuk handle file milik `www-data`)

### `docker/php/Dockerfile.base` — Base image (baru)
- Build **sekali**, dipakai semua project
- Isi: `php:8.3-apache` + semua ekstensi Laravel + Composer
- Ekstensi: `pdo`, `pdo_mysql`, `mbstring`, `zip`, `exif`, `pcntl`, `bcmath`, `gd`, `xml`
- Tujuan: project baru tidak perlu install ekstensi ulang dari nol

### `docker/php/Dockerfile` — Project image (ringkas)
- Sebelumnya: install semua ekstensi sendiri (~3–5 menit tiap project)
- Sekarang: `FROM php-laravel-base:latest` → build hanya beberapa detik
- Copy `apache-vhost.conf` ke dalam container

### `docker/php/apache-vhost.conf` — Apache config (baru)
- `DocumentRoot /var/www/html/public` — wajib untuk Laravel & PHP Native
- `AllowOverride All` — agar `.htaccess` Laravel berfungsi
- `Options -Indexes` — matikan directory listing

### `docker-compose.yml` — Tidak berubah
- Service: `app` (PHP+Apache), `db` (MariaDB 11.4), `phpmyadmin` (5.2)
- Volume `db_data` persisten

---

## Masalah yang Ditemukan & Solusinya

| Masalah | Penyebab | Solusi |
|---|---|---|
| Script tidak merespons | `set -euo pipefail` exit saat pipeline grep kosong | Tambah `\|\| true` di pipeline |
| 403 Forbidden | Apache `DocumentRoot` di `/var/www/html`, bukan `public/` | `apache-vhost.conf` set ke `public/` |
| 500 Internal Server Error | Laravel 13 default sqlite, baris `DB_*` tidak ada di `.env` | Hapus semua `DB_*` lama, tulis ulang blok mysql |
| Permission denied saat hapus | File `vendor/` dimiliki `www-data` di dalam container | `make destroy` pakai `sudo rm -rf` |
| Image nyangkut setelah destroy | `docker compose down` tidak hapus image | `make destroy` tambah `docker image rm` |
| Build lama tiap project baru | Ekstensi diinstall ulang tiap build | Base image `php-laravel-base` build sekali |
