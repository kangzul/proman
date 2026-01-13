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
    echo "--- Menjalankan Audit Keamanan untuk: $TARGET_USER ---"

    echo "Menguji isolasi antar user..."
    set +e
    sudo -u "$TARGET_USER" ls /home > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "Menguji isolasi antar user"
    
    local OTHER_ENV="/home/kangzul/shared/.env"
    if [ -f "$OTHER_ENV" ]; then
        set +e
        sudo -u "$TARGET_USER" cat "$OTHER_ENV" > /dev/null 2>&1
        rc=$?
        set -e
        check_result $rc "Membaca .env milik project lain"
    fi

    echo "Menguji pembatasan AppArmor (Binary)..."
    set +e
    sudo -u "$TARGET_USER" php -r "echo 'hello';" > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "Menjalankan binary PHP via CLI"

    echo "Menguji isolasi folder /tmp..."
    set +e
    sudo -u "$TARGET_USER" touch /tmp/test_file > /dev/null 2>&1
    rc=$?
    set -e
    check_result $rc "Menulis langsung ke root /tmp"

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