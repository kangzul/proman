#!/usr/bin/env bash
set -u

# Gunakan warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
check_result() {
    if [ $1 -ne 0 ]; then
        echo -e "${GREEN}[PASS]${NC} $2 (Akses diblokir)"
    else
        echo -e "${RED}[FAIL]${NC} $2 (CELAH KEAMANAN: Akses diizinkan!)"
    fi
}

test_isolation() {
    local TARGET_USER=$1
    local DEFAULT_USER='kangzul'
    echo "--- Menjalankan Audit Keamanan untuk: $TARGET_USER ---"

    echo "Menguji isolasi antar user..."
    set +e
    sudo -u "$TARGET_USER" ls /home > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "Menguji isolasi antar user"
    
    local OTHER_ENV="/home/${DEFAULT_USER}/shared/.env"
    if [ -f "$OTHER_ENV" ]; then
        set +e
        sudo -u "$TARGET_USER" cat "$OTHER_ENV" > /dev/null 2>&1
        rc=$?
        set -e
        check_result $rc "Membaca .env milik project lain"
    fi

    echo "Menguji akses PHP-CLI ke file di luar project (harus diblokir)..."
    set +e
    sudo -u "$TARGET_USER" php -r "exit(@is_readable('/home/${DEFAULT_USER}/shared/.env') ? 0 : 2);" > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "PHP-CLI membaca file di luar project"

    echo "Menguji kemampuan menulis ke home user lain (harus diblokir)..."
    set +e
    # Coba buat file di folder shared milik user lain
    sudo -u "$TARGET_USER" touch /home/${DEFAULT_USER}/shared/.proman_audit_test > /dev/null 2>&1
    rc=$?
    # Cleanup if created (best-effort)
    if [[ $rc -eq 0 ]]; then
        rm -f /home/${DEFAULT_USER}/shared/.proman_audit_test 2>/dev/null || true
    fi
    set -e
    check_result $rc "Menulis ke folder shared milik user lain"

    echo "Menguji akses ke kernel/system info..."
    set +e
    sudo -u "$TARGET_USER" cat /etc/shadow > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "Membaca /etc/shadow"

    set +e
    sudo -u "$TARGET_USER" ls /root > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "Membaca direktori /root"
}