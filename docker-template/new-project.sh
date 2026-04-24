#!/usr/bin/env bash
# =============================================================================
#  new-project.sh — Buat project PHP/Laravel baru dari template Docker
#
#  Cara pakai:
#    ./new-project.sh nama-project          → Laravel (default)
#    ./new-project.sh nama-project --php    → PHP Native (tanpa install Laravel)
#    ./new-project.sh nama-project --port 9090  → tentukan port manual
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
  echo "  $0 nama-project              → buat project Laravel"
  echo "  $0 nama-project --php        → buat project PHP Native"
  echo "  $0 nama-project --port 9090  → tentukan port awal manual"
  exit 1
fi

PROJECT_NAME="$1"
MODE="laravel"
CUSTOM_PORT=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --php)    MODE="php"; shift ;;
    --port)   CUSTOM_PORT="$2"; shift 2 ;;
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

if [[ -d "$PROJECT_DIR" ]]; then
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

# ─── 3. Buat Makefile ─────────────────────────────────────────────────────────
step "Membuat Makefile..."
cat > "$PROJECT_DIR/Makefile" <<MAKEFILE
.PHONY: up down start stop restart build logs bash artisan migrate fresh tinker destroy

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

destroy:
	@echo "Menghapus container, volume, image, dan seluruh folder project..."
	docker compose down -v --remove-orphans 2>/dev/null || true
	docker image rm \$(shell basename \$(shell pwd))-app 2>/dev/null || true
	sudo rm -rf \$(shell pwd)
	@echo "Project dihapus."
MAKEFILE
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
  step "Membuat file index.php untuk PHP Native..."
  mkdir -p "$PROJECT_DIR/src/public"
  cat > "$PROJECT_DIR/src/public/index.php" <<'PHPEOF'
<?php
$host = 'db';
$db   = $_ENV['DB_DATABASE'] ?? getenv('DB_NAME') ?: 'mydb';
$user = $_ENV['DB_USERNAME'] ?? getenv('DB_USER') ?: 'root';
$pass = $_ENV['DB_PASSWORD'] ?? getenv('DB_PASS') ?: '';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$db", $user, $pass);
    $status = '<span style="color:green">✔ Terhubung ke database!</span>';
} catch (PDOException $e) {
    $status = '<span style="color:red">✘ Gagal koneksi: ' . $e->getMessage() . '</span>';
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <title>PHP Native — Docker</title>
  <style>
    body { font-family: sans-serif; max-width: 600px; margin: 80px auto; }
    h1   { color: #4F46E5; }
  </style>
</head>
<body>
  <h1>🐘 PHP Native + Docker</h1>
  <p>PHP versi: <strong><?= PHP_VERSION ?></strong></p>
  <p>Database: <?= $status ?></p>
  <p>Edit file di <code>src/public/index.php</code> untuk mulai coding.</p>
</body>
</html>
PHPEOF
  success "File index.php dibuat."
fi

# ─── 7. Ringkasan akhir ───────────────────────────────────────────────────────
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
echo -e "  make migrate     # jalankan migrasi"
echo -e "  make fresh       # migrate:fresh --seed"
echo -e "  make tinker      # buka tinker"
echo -e "  make artisan cmd=\"route:list\"  # artisan command bebas"
echo -e "  make destroy     # hapus container + volume + folder project"
echo ""
