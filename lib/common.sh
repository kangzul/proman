#!/usr/bin/env bash
# Common constants and helpers

# Note: expects SCRIPT_DIR to be set by the caller before sourcing.

PHP_VER="8.4"
USER_HOME_BASE="/home"
WEB_ROOT_BASE="/var/www"
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

# Detect php-fpm systemd service name. Returns service name (without .service) or empty.
detect_php_fpm_service() {
    # Try to find any php-fpm unit first (handles different PHP versions)
    local svc
    svc=$(systemctl list-unit-files --type=service --all | awk -F'.service' '/php[0-9.]*-fpm/ {print $1; exit}') || true
    if [[ -n "$svc" ]]; then
        echo "$svc"
        return 0
    fi

    # Fall back to configured PHP_VER candidates
    local candidates=("php-${PHP_VER}-fpm" "php${PHP_VER}-fpm" "php${PHP_VER}fpm" "php-fpm")
    local c
    for c in "${candidates[@]}"; do
        if systemctl list-unit-files --type=service --all | grep -q "^${c}\.service"; then
            echo "${c}"
            return 0
        fi
    done

    for c in "${candidates[@]}"; do
        if command -v "${c}" >/dev/null 2>&1; then
            echo "${c}"
            return 0
        fi
    done

    # try globs for php*-fpm binaries
    for p in /usr/sbin/php*-fpm /usr/bin/php*-fpm; do
        if [[ -x "${p}" ]]; then
            basename "${p}" | sed 's/\.service$//'
            return 0
        fi
    done

    return 1
}

# Reload a service robustly. For php-fpm, auto-detect service name based on PHP_VER.
system_reload() {
    local svc="$1"
    if [[ "$svc" == "php-fpm" ]]; then
        local php_svc
        php_svc=$(detect_php_fpm_service) || die "PHP-FPM service not found"
        systemctl reload "${php_svc}" || die "Gagal reload ${php_svc}"
        return 0
    fi

    # fallback: attempt to reload given service name
    systemctl reload "${svc}" || die "Gagal reload ${svc}"
}
