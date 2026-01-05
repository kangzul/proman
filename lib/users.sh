#!/usr/bin/env bash
# User and filesystem related helpers. Assumes common.sh is sourced first.

prepare_linux_user() {
    useradd -m -d "$BASE_DIR" -s /usr/sbin/nologin "$SITE_USER"
    chmod 750 "$BASE_DIR"
}

prepare_directories() {
    mkdir -p \
        "$BASE_DIR/releases" \
        "$BASE_DIR/shared" \
        "$BASE_DIR/current"

    chown -R "${SITE_USER}:${SITE_USER}" "$BASE_DIR"
}

write_metadata() {
    cat <<EOF > "${BASE_DIR}/.project.conf"
PROJECT_NAME=${SITE_USER}
DOMAIN=${DOMAIN}
GIT_REPO=SILAHKAN DIISI
WEB_TYPE=${WEB_TYPE}
WITH_DB=${WITH_DB}
DB_NAME=${DB_NAME:-}
DB_USER=${DB_USER:-}
PHP_VER=${PHP_VER}
# 1. DELETE_PATHS: Folder di repo yang ingin dihapus sebelum diganti symlink
# Kita hapus folder uploads bawaan repo agar tidak bentrok dengan symlink
DELETE_PATHS=""
# 2. SYMLINK_PATHS: Format "source_di_shared:target_di_release"
# Menghubungkan .env dan folder uploads dari shared ke folder release terbaru
SYMLINK_PATHS=""
CREATED_AT=$(date +%F)
EOF

    chmod 600 "${BASE_DIR}/.project.conf"
    chown "${SITE_USER}:${SITE_USER}" "${BASE_DIR}/.project.conf"
}

list_project() {
    for d in "${WEB_ROOT_BASE}"/*; do
        [[ -f "$d/.project.conf" ]] || continue
        # shellcheck disable=SC1090
        source "$d/.project.conf"
        printf "%-15s %-30s\n" "$PROJECT_NAME" "$DOMAIN"
    done
}

delete_project() {
    local RAW_NAME="$1"
    SITE_USER=$(normalize_name "$RAW_NAME")

    BASE_DIR="${WEB_ROOT_BASE}/${SITE_USER}"
    META="${BASE_DIR}/.project.conf"

    [[ -f "$META" ]] || die "Metadata tidak ditemukan"

    # shellcheck disable=SC1090
    source "$META"

    rm -f "${NGINX_ENABLED}/${SITE_USER}.conf"
    rm -f "${NGINX_AVAIL}/${SITE_USER}.conf"
    nginx -t && systemctl reload nginx || die "Gagal reload Nginx"

    if [[ "$WEB_TYPE" == "php" ]]; then
        rm -f "/etc/tmpfiles.d/php-fpm-${SITE_USER}.conf"
        rm -rf "/tmp/php_${SITE_USER}"
        rm -f "${PHP_POOL_DIR}/${SITE_USER}.conf"
        systemctl reload "php${PHP_VER}-fpm" || die "Gagal reload PHP-FPM"
        rm -f "/etc/apparmor.d/php-fpm-${SITE_USER}"
    fi

    if [[ "$WITH_DB" == "yes" ]]; then
        mysql_exec "
        DROP DATABASE IF EXISTS \`${DB_NAME}\`;
        DROP USER IF EXISTS '${DB_USER}'@'localhost';
        FLUSH PRIVILEGES;
        "
    fi

    userdel -r "$SITE_USER" || die "Gagal menghapus user Linux"
    echo "PROJECT DIHAPUS TOTAL"
}
