# Docker PHP & Laravel — Panduan Lengkap

> Filosofi: **Satu Project = Satu Dapur** — tiap project punya container sendiri, tidak saling ganggu.

---

## Daftar Isi

1. [Prasyarat](#1-prasyarat)
2. [Struktur Folder](#2-struktur-folder)
3. [Buat Project Baru](#3-buat-project-baru)
4. [Jalankan Environment](#4-jalankan-environment)
5. [Setup Laravel](#5-setup-laravel)
6. [Perintah Harian](#6-perintah-harian)
7. [Akses Browser](#7-akses-browser)
8. [Multiple Project Sekaligus](#8-multiple-project-sekaligus)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prasyarat

Pastikan sudah terinstall di Arch Linux:

```bash
# Install Docker
sudo pacman -S docker docker-compose

# Aktifkan dan jalankan Docker daemon
sudo systemctl enable docker
sudo systemctl start docker

# Tambahkan user kamu ke grup docker (agar tidak perlu sudo tiap kali)
sudo usermod -aG docker $USER

# WAJIB: logout lalu login ulang agar grup aktif
# Atau jalankan perintah ini untuk sesi saat ini:
newgrp docker

# Verifikasi
docker --version
docker compose version
```

---

## 2. Struktur Folder

```
nama-project/
├── docker/
│   └── php/
│       └── Dockerfile        ← PHP 8.3 + Apache + semua ekstensi Laravel
├── src/                      ← SEMUA kode kamu ada di sini
│   └── (file Laravel/PHP)
├── docker-compose.yml
├── .env                      ← konfigurasi port & database (jangan di-commit!)
└── .env.example              ← template .env untuk di-commit ke git
```

> **Catatan:** Folder `src/` di laptop kamu = folder `/var/www/html` di dalam container.
> Edit file di laptop → langsung keliatan perubahannya di browser. Tidak perlu restart container.

---

## 3. Buat Project Baru

### Cara Cepat (Pakai Script Otomatis)

```bash
# Beri izin eksekusi dulu (hanya perlu sekali)
chmod +x new-project.sh

# Buat project Laravel baru
./new-project.sh nama-project-ku

# Buat project PHP Native baru
./new-project.sh nama-project-ku --php
```

Script akan otomatis:
- Menyalin template ke folder baru
- Membuat file `.env` dengan nama project & port yang unik
- Menjalankan `docker compose up -d --build`
- Menginstall Laravel (jika tidak pakai flag `--php`)
- Meng-generate `APP_KEY`
- Menjalankan migrasi database

### Cara Manual (Step by Step)

```bash
# 1. Salin template
cp -r ~/ServerwebXAMPP/docker-template/ ~/projects/nama-project-ku
cd ~/projects/nama-project-ku

# 2. Buat file .env
cp .env.example .env

# 3. Edit .env — ubah PROJECT_NAME dan PORT agar tidak bentrok
nano .env

# 4. Build dan jalankan container
docker compose up -d --build

# 5. Masuk ke container
docker compose exec app bash

# 6. Install Laravel
composer create-project laravel/laravel .

# 7. Keluar dari container
exit

# 8. Konfigurasi .env Laravel (src/.env)
# Lihat bagian "Setup Laravel" di bawah
```

---

## 4. Jalankan Environment

```bash
# Pertama kali atau setelah ubah Dockerfile (perlu build ulang)
docker compose up -d --build

# Kali berikutnya (image sudah ada)
docker compose up -d

# Cek status container
docker compose ps

# Lihat log semua service
docker compose logs -f

# Lihat log hanya service tertentu
docker compose logs -f app
docker compose logs -f db
```

**Output normal `docker compose ps`:**

```
NAME                  IMAGE         STATUS          PORTS
nama-project_app      ...           Up              0.0.0.0:8080->80/tcp
nama-project_db       mariadb:11.4  Up (healthy)    0.0.0.0:3306->3306/tcp
nama-project_pma      phpmyadmin    Up              0.0.0.0:8081->80/tcp
```

---

## 5. Setup Laravel

### Konfigurasi `.env` di dalam Folder `src/`

Setelah Laravel terinstall, buka `src/.env` dan ubah bagian database:

```env
APP_NAME=NamaProject
APP_ENV=local
APP_KEY=                    ← akan di-generate otomatis
APP_DEBUG=true
APP_URL=http://localhost:8080

DB_CONNECTION=mysql
DB_HOST=db                  ← PENTING: pakai nama service, bukan localhost
DB_PORT=3306
DB_DATABASE=nama_database   ← samakan dengan DB_NAME di .env root
DB_USERNAME=dbuser          ← samakan dengan DB_USER di .env root
DB_PASSWORD=dbpassword      ← samakan dengan DB_PASS di .env root
```

> **Kenapa `DB_HOST=db` bukan `localhost`?**
> Di dalam Docker, tiap service punya nama host sendiri sesuai nama service di `docker-compose.yml`.
> Container `app` berkomunikasi dengan container `db` lewat nama `db`, bukan `localhost`.

### Perintah Artisan

Semua perintah `artisan` harus dijalankan **di dalam container**:

```bash
# Masuk ke container
docker compose exec app bash

# Generate APP_KEY
php artisan key:generate

# Jalankan migrasi
php artisan migrate

# Jalankan migrasi + seeder
php artisan migrate --seed

# Reset & jalankan ulang semua migrasi
php artisan migrate:fresh --seed

# Buat file baru
php artisan make:model NamaModel -mcr   # Model + Migration + Controller (resource)
php artisan make:controller NamaController
php artisan make:migration create_nama_table
php artisan make:seeder NamaSeeder
php artisan make:request NamaRequest
php artisan make:middleware NamaMiddleware

# Cache & optimasi
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Clear cache
php artisan optimize:clear

# Lihat semua route
php artisan route:list

# Keluar dari container
exit
```

### Cara Singkat (Tanpa Masuk Container)

```bash
# Format: docker compose exec app php artisan [perintah]
docker compose exec app php artisan migrate
docker compose exec app php artisan make:model Post -mcr
docker compose exec app php artisan route:list
```

### Install Package dengan Composer

```bash
# Masuk container dulu
docker compose exec app bash

# Contoh install package
composer require laravel/sanctum
composer require spatie/laravel-permission
composer require barryvdh/laravel-debugbar --dev

exit
```

---

## 6. Perintah Harian

```bash
# ── Menjalankan ──────────────────────────────────────────────
docker compose up -d              # Jalankan semua container (background)
docker compose up -d app          # Jalankan hanya service tertentu
docker compose start              # Start container yang sudah ada (tanpa build ulang)

# ── Menghentikan ─────────────────────────────────────────────
docker compose stop               # Stop container, data tetap ada
docker compose down               # Stop + hapus container (data DB tetap di volume)
docker compose down -v            # Stop + hapus container + hapus data DB (RESET TOTAL)

# ── Monitoring ───────────────────────────────────────────────
docker compose ps                 # Status semua container
docker compose logs -f            # Log real-time semua service
docker compose logs -f app        # Log real-time hanya PHP
docker stats                      # Monitor penggunaan CPU & RAM real-time

# ── Masuk ke Container ────────────────────────────────────────
docker compose exec app bash      # Masuk ke container PHP
docker compose exec db bash       # Masuk ke container MariaDB
docker compose exec db mariadb -u root -p  # Masuk ke MariaDB CLI

# ── Build Ulang ───────────────────────────────────────────────
docker compose build              # Build ulang image tanpa menjalankan
docker compose up -d --build      # Build ulang lalu jalankan
docker compose up -d --build --no-cache  # Build ulang dari nol (tanpa cache)
```

---

## 7. Akses Browser

| Service | URL | Keterangan |
|---|---|---|
| Website / PHP | `http://localhost:8080` | Sesuaikan `APP_PORT` di `.env` |
| phpMyAdmin | `http://localhost:8081` | Sesuaikan `PMA_PORT` di `.env` |

**Login phpMyAdmin:**
- Server: `db`
- Username: `root`
- Password: nilai `DB_ROOT_PASS` di file `.env` kamu

---

## 8. Multiple Project Sekaligus

Karena tiap project punya port sendiri, kamu bisa jalankan banyak project bersamaan. Pastikan port tidak bentrok di file `.env` masing-masing project:

```
project-toko/      APP_PORT=8080  PMA_PORT=8081  DB_PORT=3306
project-blog/      APP_PORT=8082  PMA_PORT=8083  DB_PORT=3307
project-api/       APP_PORT=8084  PMA_PORT=8085  DB_PORT=3308
```

```bash
# Jalankan semua project sekaligus
cd ~/projects/project-toko  && docker compose up -d
cd ~/projects/project-blog  && docker compose up -d
cd ~/projects/project-api   && docker compose up -d
```

---

## 9. Troubleshooting

### Container tidak mau jalan

```bash
# Cek log error
docker compose logs app
docker compose logs db

# Cek apakah port sudah dipakai proses lain
sudo ss -tulpn | grep 8080
```

### Error: `SQLSTATE[HY000] [2002] No such file or directory`

Pastikan `DB_HOST=db` (bukan `localhost`) di file `src/.env` Laravel.

### Error: `Permission denied` di Laravel

```bash
docker compose exec app bash
chmod -R 775 storage bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache
exit
```

### Ingin hapus semua image Docker yang tidak terpakai

```bash
# Hapus container, image, network yang tidak dipakai (hemat storage)
docker system prune -a

# Cek berapa storage yang dipakai Docker
docker system df
```

### Build ulang setelah ubah `Dockerfile`

```bash
docker compose up -d --build --no-cache
```
