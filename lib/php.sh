#!/usr/bin/env bash
# PHP-related setup: SSH key, php-fpm pool, AppArmor

setup_ssh() {
    local ssh_dir="${BASE_DIR}/.ssh"
    local key_path="${ssh_dir}/id_ed25519"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "deploy-${SITE_USER}"
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    chown -R "${SITE_USER}:${SITE_USER}" "$ssh_dir"
    SSH_PUB_KEY=$(cat "${key_path}.pub")
}

setup_php_pool() {
    cat <<EOF > "${PHP_POOL_DIR}/${SITE_USER}.conf"
[${SITE_USER}]
user = ${SITE_USER}
group = ${SITE_USER}

listen = /run/php/php-${SITE_USER}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 6
pm.process_idle_timeout = 10s
pm.max_requests = 300

chdir = ${BASE_DIR}/current

clear_env = yes
security.limit_extensions = .php

php_admin_value[open_basedir] = ${BASE_DIR}/current:${BASE_DIR}/shared:/tmp
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec
php_admin_value[allow_url_fopen] = Off
php_admin_value[expose_php] = Off
php_admin_flag[log_errors] = On
php_admin_value[upload_tmp_dir] = /tmp/php_${SITE_USER}
php_admin_value[sys_temp_dir] = /tmp/php_${SITE_USER}
EOF
    mkdir -p /tmp/php_${SITE_USER}
    chown ${SITE_USER}:${SITE_USER} /tmp/php_${SITE_USER}
    chmod 700 /tmp/php_${SITE_USER}
    systemctl reload "php${PHP_VER}-fpm" || die "Gagal reload PHP-FPM"
}

setup_apparmor() {
    local profile_name="php-fpm-${SITE_USER}"
    local profile_path="/etc/apparmor.d/${profile_name}"

    cat <<EOF > "$profile_path"
#include <tunables/global>

profile $profile_name flags=(attach_disconnected,mediate_deleted) {
    #include <abstractions/base>
    #include <abstractions/nameservice>
    #include <abstractions/ssl_certs>
    #include <abstractions/php>

    # Batasi eksekusi PHP-FPM hanya untuk master binary
    /usr/sbin/php-fpm${PHP_VER} mrix,
    
    # Larang eksekusi binary umum untuk mencegah shell escape
    deny /usr/bin/php* x,
    deny /usr/bin/perl* x,
    deny /usr/bin/python* x,
    deny /usr/bin/ruby* x,

    # Akses Read-only ke sistem library (Inherited from abstractions, but explicit for safety)
    /usr/lib/** r,
    /lib/** r,
    /etc/php/${PHP_VER}/** r,

    # Komunikasi Socket
    /run/php/php-${SITE_USER}.sock rw,

    owner /tmp/php_${SITE_USER}/ rw,
    owner /tmp/php_${SITE_USER}/** rwk,

    # ISOLASI DATA: Hanya izinkan akses ke folder project milik sendiri
    # Akses ke kode utama (Read-only)
    owner ${BASE_DIR}/current/** r,
    
    # Akses ke .env (Read-only)
    owner ${BASE_DIR}/shared/.env r,
    
    # Akses ke folder uploads yang di-symlink (Read-Write-Lock)
    owner ${BASE_DIR}/shared/uploads/** rwk,
    
    # Akses ke folder writable CI4 (untuk logs/cache)
    owner ${BASE_DIR}/releases/**/writable/** rwk,

    # DENY RULES (Blacklisting as second layer)
    deny /proc/** rwklx,
    deny /sys/** rwklx,
    deny /root/** rwklx,
    deny /home/*/.ssh/** rwklx, # Mencegah membaca key user lain
}
EOF
    apparmor_parser -r "$profile_path" || die "Gagal memuat profil AppArmor untuk ${SITE_USER}"
    aa-enforce "$profile_name" || die "Gagal mengaktifkan mode enforce untuk ${SITE_USER}"
}

setup_tmp_isolation() {
    local TMP_CONF="/etc/tmpfiles.d/php-fpm-${SITE_USER}.conf"
    
    # Format: Type Path Mode User Group Age Argument
    # d = create directory if it doesn't exist
    echo "d /tmp/php_${SITE_USER} 0700 ${SITE_USER} ${SITE_USER} -" > "$TMP_CONF"
    
    # Jalankan langsung agar folder tersedia sekarang tanpa reboot
    systemd-tmpfiles --create "$TMP_CONF" || die "Gagal membuat folder isolasi temp"
}

setup_php_stack() {
    setup_ssh
    setup_tmp_isolation
    setup_php_pool
    setup_apparmor
}
