#!/usr/bin/env bash
# =============================================================================
#  new-project.sh — Buat project PHP/Laravel baru dari template Docker
#
#  Cara pakai:
#    ./new-project.sh nama-project                          → Laravel (default)
#    ./new-project.sh nama-project --php                    → PHP Native (tanpa install Laravel)
#    ./new-project.sh nama-project --port 9090              → tentukan port manual
#    ./new-project.sh nama-project --output /path/ke/tujuan → simpan project ke lokasi kustom
# =============================================================================

set -euo pipefail

# ─── Warna terminal ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Fungsi helper ────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── Validasi argumen ─────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo -e "${BOLD}Cara pakai:${NC}"
  echo "  $0 nama-project                          → buat project Laravel"
  echo "  $0 nama-project --php                    → buat project PHP Native"
  echo "  $0 nama-project --port 9090              → tentukan port awal manual"
  echo "  $0 nama-project --output /path/ke/folder → simpan project ke lokasi kustom"
  exit 1
fi

PROJECT_NAME="$1"
MODE="laravel"
CUSTOM_PORT=""
CUSTOM_OUTPUT=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --php)    MODE="php"; shift ;;
    --port)   CUSTOM_PORT="$2"; shift 2 ;;
    --output) CUSTOM_OUTPUT="$2"; shift 2 ;;
    *)        error "Argumen tidak dikenal: $1" ;;
  esac
done

if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  error "Nama project hanya boleh berisi huruf, angka, underscore, dan tanda hubung."
fi

# ─── Tentukan lokasi template & project ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR"
PROJECTS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"

if [[ -n "$CUSTOM_OUTPUT" ]]; then
  CUSTOM_OUTPUT="$(realpath -m "$CUSTOM_OUTPUT")"
  PARENT_OF_CUSTOM="$(dirname "$CUSTOM_OUTPUT")"
  if [[ -d "$PARENT_OF_CUSTOM" && -w "$PARENT_OF_CUSTOM" ]]; then
    PROJECT_DIR="$CUSTOM_OUTPUT"
  else
    warn "Path '$CUSTOM_OUTPUT' tidak valid atau tidak bisa ditulis. Menggunakan default: $PROJECT_DIR"
  fi
else
  # ─── Prompt interaktif lokasi tujuan ────────────────────────────────────────
  while true; do
    echo -e "${CYAN}Simpan project di folder${NC} [${BOLD}$PROJECTS_DIR${NC}]: \c"
    read -r INPUT_OUTPUT
    if [[ -z "$INPUT_OUTPUT" ]]; then
      TARGET_PARENT="$PROJECTS_DIR"
    else
      TARGET_PARENT="$(realpath -m "$INPUT_OUTPUT")"
    fi
    if [[ ! -d "$TARGET_PARENT" || ! -w "$TARGET_PARENT" ]]; then
      warn "Folder '$TARGET_PARENT' tidak ditemukan atau tidak bisa ditulis. Coba lagi."
      continue
    fi
    PROJECT_DIR="$TARGET_PARENT/$PROJECT_NAME"
    if [[ -d "$PROJECT_DIR" ]]; then
      warn "Folder '$PROJECT_DIR' sudah ada. Masukkan lokasi lain."
      continue
    fi
    break
  done
fi

if [[ -n "$CUSTOM_OUTPUT" && -d "$PROJECT_DIR" ]]; then
  error "Folder '$PROJECT_DIR' sudah ada. Pilih nama lain atau hapus folder tersebut."
fi

# ─── Rollback otomatis kalau script gagal ─────────────────────────────────────
cleanup() {
  if [[ $? -ne 0 ]]; then
    warn "Terjadi error. Membersihkan sisa-sisa..."
    if [[ -d "$PROJECT_DIR" ]]; then
      cd "$PROJECT_DIR" 2>/dev/null && docker compose down -v --remove-orphans 2>/dev/null || true
      sudo rm -rf "$PROJECT_DIR" 2>/dev/null || rm -rf "$PROJECT_DIR" 2>/dev/null || true
      warn "Folder '$PROJECT_DIR' dihapus."
    fi
  fi
}
trap cleanup EXIT

# ─── Fungsi: cari port kosong ─────────────────────────────────────────────────
find_free_port() {
  local port="$1"
  while ss -tulpn 2>/dev/null | grep -q ":${port} "; do
    port=$((port + 2))
  done
  echo "$port"
}

# ─── Tentukan port ────────────────────────────────────────────────────────────
if [[ -n "$CUSTOM_PORT" ]]; then
  BASE_PORT="$CUSTOM_PORT"
else
  # Ambil port tertinggi dari container yang sedang aktif
  LAST_APP_PORT=$(docker ps --format '{{.Ports}}' 2>/dev/null \
    | grep -oP '0\.0\.0\.0:\K\d+(?=->80)' | sort -n | tail -1 || true)
  BASE_PORT="${LAST_APP_PORT:-8078}"
  BASE_PORT=$((BASE_PORT + 2))
fi

APP_PORT=$(find_free_port "$BASE_PORT")
PMA_PORT=$(find_free_port "$((APP_PORT + 1))")
DB_PORT=$(find_free_port "3306")

# ─── Generate password yang mudah dibaca ──────────────────────────────────────
SUFFIX="$(openssl rand -hex 3 2>/dev/null || echo "abc123")"
DB_PASS="${PROJECT_NAME}-${SUFFIX}"
DB_ROOT_PASS="root-${PROJECT_NAME}-${SUFFIX}"

# ─── Mulai ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        Docker PHP Project Generator          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Nama project : ${BOLD}$PROJECT_NAME${NC}"
info "Mode         : ${BOLD}$MODE${NC}"
info "Lokasi       : ${BOLD}$PROJECT_DIR${NC}"
info "APP_PORT     : ${BOLD}$APP_PORT${NC}  → http://localhost:$APP_PORT"
info "PMA_PORT     : ${BOLD}$PMA_PORT${NC}  → http://localhost:$PMA_PORT"
info "DB_PORT      : ${BOLD}$DB_PORT${NC}"
echo ""

# ─── 1. Pastikan base image tersedia ─────────────────────────────────────────
if ! docker image inspect php-laravel-base:latest &>/dev/null; then
  step "Build base image PHP (hanya sekali)..."
  info  "Ini mungkin membutuhkan 3–5 menit. Selanjutnya akan instan."
  docker build -t php-laravel-base:latest \
    -f "$TEMPLATE_DIR/docker/php/Dockerfile.base" \
    "$TEMPLATE_DIR"
  success "Base image php-laravel-base siap."
else
  success "Base image php-laravel-base sudah ada, skip build."
fi

# ─── 2. Salin template ────────────────────────────────────────────────────────
step "Menyalin template ke $PROJECT_DIR"
cp -r "$TEMPLATE_DIR" "$PROJECT_DIR"
rm -f "$PROJECT_DIR/src/.gitkeep"
rm -f "$PROJECT_DIR/new-project.sh"
rm -f "$PROJECT_DIR/README.md"
rm -f "$PROJECT_DIR/LOGS.md"
success "Template disalin."

# ─── 2. Buat file .env ────────────────────────────────────────────────────────
step "Membuat file .env"

DB_NAME="${PROJECT_NAME//-/_}_db"
DB_USER="${PROJECT_NAME//-/_}_user"

cat > "$PROJECT_DIR/.env" <<EOF
PROJECT_NAME=${PROJECT_NAME}

# Port akses browser
APP_PORT=${APP_PORT}
PMA_PORT=${PMA_PORT}
DB_PORT=${DB_PORT}

# Kredensial database
DB_ROOT_PASS=${DB_ROOT_PASS}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
EOF

success "File .env dibuat."

# ─── 3. Buat Makefile (sesuai mode) ──────────────────────────────────────────
step "Membuat Makefile..."

if [[ "$MODE" == "laravel" ]]; then
cat > "$PROJECT_DIR/Makefile" <<MAKEFILE
.PHONY: up down start stop restart build logs bash artisan migrate fresh tinker info destroy

up:
	docker compose up -d --build

down:
	docker compose down

start:
	docker compose start

stop:
	docker compose stop

restart:
	docker compose restart

build:
	docker compose up -d --build --no-cache

logs:
	docker compose logs -f

bash:
	docker compose exec app bash

artisan:
	docker compose exec app php artisan \$(cmd)

migrate:
	docker compose exec app php artisan migrate

fresh:
	docker compose exec app php artisan migrate:fresh --seed

tinker:
	docker compose exec app php artisan tinker

info:
	@cat PROJECT.md

destroy:
	@echo "Menghapus container, volume, image, dan seluruh folder project..."
	docker compose down -v --remove-orphans 2>/dev/null || true
	docker image rm \$(shell basename \$(shell pwd))-app 2>/dev/null || true
	sudo rm -rf \$(shell pwd)
	@echo "Project dihapus."
MAKEFILE
else
# Makefile khusus PHP Native — tanpa perintah Laravel
cat > "$PROJECT_DIR/Makefile" <<MAKEFILE
.PHONY: up down start stop restart build logs bash db info destroy

up:
	docker compose up -d --build

down:
	docker compose down

start:
	docker compose start

stop:
	docker compose stop

restart:
	docker compose restart

build:
	docker compose up -d --build --no-cache

logs:
	docker compose logs -f

bash:
	docker compose exec app bash

db:
	docker compose exec db mariadb -u \${DB_USER} -p\${DB_PASS} \${DB_NAME}

sql:
	docker compose exec -T db mariadb -u \${DB_USER} -p\${DB_PASS} \${DB_NAME} < \$(file)

info:
	@cat PROJECT.md

destroy:
	@echo "Menghapus container, volume, image, dan seluruh folder project..."
	docker compose down -v --remove-orphans 2>/dev/null || true
	docker image rm \$(shell basename \$(shell pwd))-app 2>/dev/null || true
	sudo rm -rf \$(shell pwd)
	@echo "Project dihapus."
MAKEFILE
fi
success "Makefile dibuat."

# ─── 4. Build & jalankan container ───────────────────────────────────────────
step "Build image Docker dan menjalankan container..."
info  "Ini mungkin membutuhkan 2–5 menit pada build pertama."

cd "$PROJECT_DIR"
docker compose up -d --build

# ─── 5. Tunggu database siap ──────────────────────────────────────────────────
step "Menunggu database siap..."
MAX_WAIT=60
ELAPSED=0
until docker compose exec -T db mariadb -u root -p"${DB_ROOT_PASS}" \
      -e "SELECT 1;" &>/dev/null; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    error "Database tidak merespons setelah ${MAX_WAIT} detik. Cek: docker compose logs db"
  fi
  echo -n "."
done
echo ""
success "Database siap."

# ─── 6. Setup project ─────────────────────────────────────────────────────────
if [[ "$MODE" == "laravel" ]]; then
  step "Menginstall Laravel via Composer..."
  docker compose exec app composer create-project laravel/laravel . --prefer-dist

  step "Mengkonfigurasi .env Laravel..."
  LARAVEL_ENV="$PROJECT_DIR/src/.env"

  sed -i "s|^APP_URL=.*|APP_URL=http://localhost:${APP_PORT}|" "$LARAVEL_ENV"

  # Laravel 13 default sqlite — ganti ke mysql dan tulis ulang semua DB_ vars
  sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" "$LARAVEL_ENV"
  # Hapus baris DB_ lama (sqlite path dll) lalu tambahkan blok mysql yang benar
  sed -i '/^DB_/d' "$LARAVEL_ENV"
  cat >> "$LARAVEL_ENV" <<LARAVELENV

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}
LARAVELENV

  step "Generate APP_KEY..."
  docker compose exec app php artisan key:generate

  step "Menjalankan migrasi database..."
  docker compose exec app php artisan migrate --force

  step "Memperbaiki permission storage..."
  docker compose exec app bash -c \
    "chmod -R 775 storage bootstrap/cache && \
     chown -R www-data:www-data storage bootstrap/cache"

  success "Laravel berhasil diinstall dan dikonfigurasi."

else
  step "Menyiapkan struktur folder PHP Native..."

  # Struktur: public/ (browser), includes/ (class/helper), sql/ (DDL)
  mkdir -p "$PROJECT_DIR/src/public/assets"
  mkdir -p "$PROJECT_DIR/src/includes"
  mkdir -p "$PROJECT_DIR/src/sql"

  # ── src/includes/db.php ──────────────────────────────────────
  # Starter koneksi MySQLi — baca dari env Docker (DB_HOST, DB_DATABASE, dll)
  # Env var names sesuai docker-compose.yml (DB_DATABASE / DB_USERNAME / DB_PASSWORD)
  cat > "$PROJECT_DIR/src/includes/db.php" <<'PHPEOF'
<?php
/**
 * File    : includes/db.php
 * Fungsi  : Koneksi ke database menggunakan MySQLi OOP
 *
 * File ini berada di luar public/ → TIDAK bisa diakses browser langsung.
 * Gunakan: require_once __DIR__ . '/../includes/db.php';
 */

$host   = getenv('DB_HOST')     ?: 'db';
$dbname = getenv('DB_DATABASE') ?: 'mydb';
$user   = getenv('DB_USERNAME') ?: 'root';
$pass   = getenv('DB_PASSWORD') ?: '';

$conn = new mysqli($host, $user, $pass, $dbname);

if ($conn->connect_error) {
    die('Koneksi database gagal: ' . htmlspecialchars($conn->connect_error));
}

$conn->set_charset('utf8mb4');
PHPEOF

  # ── src/sql/init.sql ─────────────────────────────────────────
  cat > "$PROJECT_DIR/src/sql/init.sql" <<SQLEOF
-- File    : sql/init.sql
-- Fungsi  : DDL awal project — edit sesuai kebutuhan
-- Cara import: make sql file=src/sql/init.sql

-- Contoh tabel
CREATE TABLE IF NOT EXISTS contoh (
    id         INT          NOT NULL AUTO_INCREMENT,
    nama       VARCHAR(100) NOT NULL,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQLEOF

  # ── src/public/index.php ─────────────────────────────────────
  cat > "$PROJECT_DIR/src/public/index.php" <<'PHPEOF'
<?php
/**
 * File    : public/index.php
 * Fungsi  : Halaman utama — edit sesuai kebutuhan
 *
 * File class/helper taruh di src/includes/ (tidak bisa diakses browser).
 * Require dari sini dengan path: __DIR__ . '/../includes/db.php'
 */

require_once __DIR__ . '/../includes/db.php';

// Test koneksi
$test = $conn->query('SELECT 1');
$status = $test
    ? '<span style="color:green;font-weight:bold">✔ Terhubung ke database!</span>'
    : '<span style="color:red;font-weight:bold">✘ Query gagal</span>';
?>
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>PHP Native — Docker</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: sans-serif; background: #f0f2f5; margin: 0; padding: 40px 20px; }
    .card { background: #fff; border-radius: 12px; padding: 32px 40px;
            max-width: 560px; margin: 0 auto; box-shadow: 0 2px 12px rgba(0,0,0,.08); }
    h1 { margin-top: 0; color: #4F46E5; }
    code { background: #f3f4f6; padding: 2px 6px; border-radius: 4px; font-size: .9em; }
    .info { margin-top: 24px; padding: 16px; background: #f9fafb;
            border-left: 4px solid #4F46E5; border-radius: 4px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🐘 PHP Native + Docker</h1>
    <p><strong>PHP versi :</strong> <?= PHP_VERSION ?></p>
    <p><strong>Database  :</strong> <?= $status ?></p>
    <div class="info">
      <strong>Struktur folder:</strong><br><br>
      <code>src/public/</code> → file yang bisa diakses browser<br>
      <code>src/includes/</code> → class, helper, koneksi DB (aman dari browser)<br>
      <code>src/sql/</code> → file SQL untuk import skema<br><br>
      <strong>Require dari public/:</strong><br>
      <code>require_once __DIR__ . '/../includes/db.php';</code>
    </div>
  </div>
</body>
</html>
PHPEOF

  success "Struktur folder PHP Native siap (public/, includes/, sql/)."
fi

# ─── 7. Ringkasan akhir ───────────────────────────────────────────────────────

# Generate PROJECT.md (tanpa ANSI color, bisa dibaca kapan saja)
if [[ "$MODE" == "php" ]]; then
  EXTRA_COMMANDS="  make db          # masuk ke MySQL CLI
  make sql file=src/sql/init.sql  # import file SQL"
  EXTRA_INFO="
## Struktur Folder PHP Native

  src/public/    → file yang diakses browser (.php, .css, .js)
  src/includes/  → class, helper, koneksi DB (aman dari browser)
  src/sql/       → file SQL untuk skema database

Require koneksi dari public/:
  require_once __DIR__ . '/../includes/db.php';"
else
  EXTRA_COMMANDS="  make migrate     # jalankan migrasi
  make fresh       # migrate:fresh --seed
  make tinker      # buka tinker
  make artisan cmd=\"route:list\"  # artisan command bebas"
  EXTRA_INFO=""
fi

cat > "$PROJECT_DIR/PROJECT.md" <<INFO
# Project: $PROJECT_NAME

Dibuat   : $(date '+%Y-%m-%d %H:%M')
Mode     : $MODE
Lokasi   : $PROJECT_DIR

## Akses Browser

  Website    : http://localhost:${APP_PORT}
  phpMyAdmin : http://localhost:${PMA_PORT}

## Login phpMyAdmin

  Server   : db
  Username : root
  Password : ${DB_ROOT_PASS}

## Perintah Berguna

  cd $PROJECT_DIR
  make up          # build & jalankan container
  make down        # matikan & hapus container
  make start       # start container (tanpa build ulang)
  make stop        # stop container
  make logs        # lihat log real-time
  make bash        # masuk ke container PHP
${EXTRA_COMMANDS}
  make info        # tampilkan info project ini
  make destroy     # hapus container + volume + folder project
${EXTRA_INFO}
INFO

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║           Project Siap Digunakan!            ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Nama Project  :${NC} $PROJECT_NAME"
echo -e "  ${BOLD}Mode          :${NC} $MODE"
echo -e "  ${BOLD}Lokasi        :${NC} $PROJECT_DIR"
echo ""
echo -e "  ${BOLD}${CYAN}Akses Browser:${NC}"
echo -e "  → Website      : ${BOLD}http://localhost:${APP_PORT}${NC}"
echo -e "  → phpMyAdmin   : ${BOLD}http://localhost:${PMA_PORT}${NC}"
echo ""
echo -e "  ${BOLD}${CYAN}Login phpMyAdmin:${NC}"
echo -e "  → Server   : db"
echo -e "  → Username : root"
echo -e "  → Password : ${BOLD}${DB_ROOT_PASS}${NC}"
echo ""
echo -e "  ${BOLD}${CYAN}Perintah berguna (dari folder project):${NC}"
echo -e "  cd $PROJECT_DIR"
echo -e "  make up          # build & jalankan container"
echo -e "  make down        # matikan & hapus container"
echo -e "  make start       # start container (tanpa build ulang)"
echo -e "  make stop        # stop container"
echo -e "  make logs        # lihat log real-time"
echo -e "  make bash        # masuk ke container PHP"
if [[ "$MODE" == "laravel" ]]; then
echo -e "  make migrate     # jalankan migrasi"
echo -e "  make fresh       # migrate:fresh --seed"
echo -e "  make tinker      # buka tinker"
echo -e "  make artisan cmd=\"route:list\"  # artisan command bebas"
else
echo -e "  make db          # masuk ke MySQL CLI"
echo -e "  make sql file=src/sql/init.sql  # import file SQL"
fi
echo -e "  make info        # tampilkan info project ini lagi"
echo -e "  make destroy     # hapus container + volume + folder project"
echo ""
if [[ "$MODE" == "php" ]]; then
echo -e "  ${BOLD}${CYAN}Struktur folder PHP Native:${NC}"
echo -e "  src/public/    → file yang diakses browser (.php, .css, .js)"
echo -e "  src/includes/  → class, helper, koneksi DB (aman dari browser)"
echo -e "  src/sql/       → file SQL untuk skema database"
echo -e ""
echo -e "  ${BOLD}${CYAN}Require koneksi dari public/:${NC}"
echo -e "  require_once __DIR__ . '/../includes/db.php';"
echo ""
fi
echo -e "  ${BOLD}${CYAN}Info tersimpan di:${NC} $PROJECT_DIR/PROJECT.md"
echo -e "  Atau jalankan: ${BOLD}make info${NC} dari folder project"
echo ""
