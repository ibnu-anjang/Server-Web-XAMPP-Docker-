# Panduan Ngoding PHP Native di Docker

---

## Struktur Folder yang Benar

```
src/
├── public/          ← Apache serve dari sini (browser bisa akses)
│   ├── index.php    ← halaman utama
│   ├── kontak.php
│   └── assets/
│       ├── style.css
│       └── script.js
│
├── includes/        ← TIDAK bisa diakses browser langsung (aman!)
│   ├── db.php       ← koneksi database
│   └── helper.php
│
└── config/          ← TIDAK bisa diakses browser langsung
    └── app.php
```

---

## Kenapa Harus di `public/`?

Apache dikonfigurasi dengan `DocumentRoot /var/www/html/public`.  
Artinya Apache hanya mau melayani file yang ada di dalam folder `public/`.

```
Browser minta: http://localhost:8080/kontak.php
Apache cari file di: /var/www/html/public/kontak.php  ✔
```

### Apa yang Terjadi Kalau `index.php` Dipindah ke Luar `public/`?

```
src/
├── index.php        ← dipindah ke sini
└── public/          ← kosong
```

**Hasilnya: 403 Forbidden**

Apache tidak menemukan file apapun di `public/`, lalu menolak request.
File `index.php` yang ada di `src/` tidak kelihatan oleh Apache sama sekali.

---

## Mengakses File di Luar `public/` (Cara yang Benar)

File di luar `public/` tidak bisa diakses via URL, tapi **bisa di-include dari PHP**:

```php
// src/public/index.php

// Path ke folder src/ (satu level di atas public/)
require_once __DIR__ . '/../includes/db.php';
require_once __DIR__ . '/../includes/helper.php';
```

`__DIR__` = lokasi file saat ini = `.../src/public`  
`__DIR__ . '/../'` = naik satu level = `.../src/`

### Ini Justru Bagus untuk Keamanan

File `db.php` yang berisi password database **tidak bisa diakses langsung** via browser:

```
http://localhost:8080/../includes/db.php  → 403 Forbidden  ✔ Aman!
```

---

## Contoh Struktur Project Sederhana

```
src/
├── public/
│   ├── index.php       ← daftar produk
│   ├── detail.php      ← detail produk
│   └── assets/
│       └── style.css
│
└── includes/
    └── db.php          ← koneksi PDO
```

**`src/includes/db.php`:**
```php
<?php
$host = 'db';
$db   = getenv('DB_DATABASE') ?: 'mydb';
$user = getenv('DB_USERNAME') ?: 'root';
$pass = getenv('DB_PASSWORD') ?: '';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$db;charset=utf8", $user, $pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die('Koneksi gagal: ' . $e->getMessage());
}
```

**`src/public/index.php`:**
```php
<?php
require_once __DIR__ . '/../includes/db.php';

$stmt = $pdo->query('SELECT * FROM produk');
$produk = $stmt->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html>
<body>
  <?php foreach ($produk as $item): ?>
    <p><?= htmlspecialchars($item['nama']) ?></p>
  <?php endforeach; ?>
</body>
</html>
```

---

## Navigasi Antar Halaman

```php
<!-- Link ke halaman lain -->
<a href="/kontak.php">Kontak</a>          <!-- → src/public/kontak.php -->
<a href="/assets/style.css">CSS</a>       <!-- → src/public/assets/style.css -->

<!-- JANGAN pakai path relatif seperti ini kalau bisa -->
<a href="../index.php">Home</a>           <!-- bisa error tergantung URL -->
```

Gunakan `/` di depan untuk path absolut dari root website.

---

## Perintah Berguna

```bash
# Masuk ke container untuk debug
make bash

# Lihat error PHP real-time
make logs

# Restart container setelah ubah konfigurasi
make restart
```

---

## Ringkasan Aturan

| Mau apa | Taruh di mana |
|---|---|
| File yang diakses browser (`.php`, `.css`, `.js`, gambar) | `src/public/` |
| Koneksi DB, fungsi helper, config | `src/includes/` atau `src/config/` |
| Upload file dari user | `src/public/uploads/` |
