# Proman — Project Manager

Proman adalah skrip bash untuk membuat, mengelola, dan mendeploy proyek web (PHP / static) pada satu server. Kode telah dimodularisasi di bawah `lib/` dan skrip utama disebut `proman`.

## Ringkasan fitur

-   Menambahkan project: user Linux terisolasi, direktori release/shared/current
-   Opsi pembuatan database (MariaDB/MySQL) dan file `.env`
-   Konfigurasi PHP-FPM pool, AppArmor profile, dan Nginx site
-   Deployment via `git clone` ke direktori release dan symlink `current`

## Prasyarat

-   Sistem berbasis Debian/Ubuntu (uji pada Debian/Ubuntu)
-   Root / sudo
-   Paket yang direkomendasikan: `nginx`, `git`, `mariadb-client` (atau `mysql-client`), `php8.4-fpm`, `apparmor`, `ssh`, `openssl`

Instal contoh (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y nginx git mariadb-client php8.4-fpm apparmor openssh-client
```

## Instalasi cepat

1. Salin repositori ke server (mis. `/opt/proman`):

```bash
sudo cp -r proman /opt/proman
cd /opt/proman
```

2. Jadikan skrip utama executable :

```bash
sudo chmod +x proman
```

## Struktur penting

-   `proman` (skrip utama — CLI)
-   `lib/` (modul: `common.sh`, `database.sh`, `php.sh`, `nginx.sh`, `users.sh`, `deploy.sh`)

## Contoh penggunaan (production)

1. Tambah project (interaktif):

```bash
sudo ./proman add
# Masukkan: Nama project, Domain, pilih buat database? dan jenis web (php/static)
```

2. Lihat daftar project yang terdaftar:

```bash
sudo ./proman list
```

3. Deploy release dari repo

```bash
sudo ./proman deploy yourproject v1.2.3
```

4. Hapus project (pastikan backup DB dan file terlebih dahulu):

```bash
sudo ./proman delete yourproject
```

Catatan deploy production:

-   Sebelum `deploy` pastikan field `GIT_REPO` pada `[BASE_DIR]/.project.conf` terisi URL repo yang benar.
-   pastikan pubkey sudah ditambahkan di pengaturan deploy keys pada repository git tanpa mencentang write access
-   Selalu deploy ke staging VM terlebih dulu. Jangan jalankan `delete` sebelum backup.

## Keamanan & best-practices

-   Password DB disimpan di `${BASE_DIR}/shared/.env` dengan permission `0640` dan owner project user — jangan mencetaknya di log produksi.
-   Pastikan `proman` dijalankan dengan `sudo` oleh operator tepercaya.
-   Batasi akses SSH dan gunakan kunci ed25519.
-   Cadangkan database dan metadata (`.project.conf`) sebelum operasi destruktif.

## Troubleshooting singkat

-   Lakukan linting shell: `shellcheck proman lib/*.sh`
-   Uji konfigurasi nginx: `nginx -t`
-   Periksa unit systemd: `systemctl status nginx php8.4-fpm`
-   Periksa AppArmor: `apparmor_status` atau `aa-status`

## Pengujian cepat (dry-run)

-   Untuk melihat perintah tanpa menjalankan semua efek, jalankan skrip pada VM staging dan tambahkan `set -x` di top skrip.

## Catatan pemeliharaan

-   Modul terletak di `lib/`. Untuk mengubah perilaku, modifikasi fungsi yang sesuai (mis. `setup_php_pool` di `lib/php.sh`).
-   Pertimbangkan integrasi Vault atau secrets manager jika menyimpan credential di produksi.
