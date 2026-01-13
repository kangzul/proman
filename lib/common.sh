#!/usr/bin/env bash
# Common constants and helpers

# Note: expects SCRIPT_DIR to be set by the caller before sourcing.

PHP_VER="8.4"
WEB_ROOT_BASE="/home"
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
PHP_POOL_DIR="/etc/php/${PHP_VER}/fpm/pool.d"

die() {
    echo "ERROR: $1" >&2
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Jalankan dengan sudo"
}

normalize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' '
}

validate_project() {
    [[ "$1" =~ ^[a-z0-9_-]+$ ]] || die "Nama project tidak valid"
}

validate_domain() {
    local domain="$1"

    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        die "Domain mengandung karakter terlarang: $domain"
    fi

    if [[ ! "$domain" == *.* ]]; then
        die "Format domain salah (butuh titik): $domain"
    fi

    if [[ "$domain" == *".."* ]]; then
        die "Domain tidak boleh mengandung double dot (..): $domain"
    fi
}

random_pass() {
    head -c 48 /dev/urandom | tr -dc 'A-Za-z0-9._%+-' | head -c 32
    echo
}

mysql_exec() {
    mariadb --protocol=socket --user=root --batch --silent <<EOF
$1
EOF
}

run_as_user() {
    local _user="$1"
    shift
    sudo -u "${_user}" "$@"
}
