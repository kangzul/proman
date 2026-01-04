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
EOF

    systemctl reload "php${PHP_VER}-fpm" || true
}

setup_apparmor() {
    cat <<EOF > "/etc/apparmor.d/php-fpm-${SITE_USER}"
#include <tunables/global>

profile php-fpm-${SITE_USER} flags=(attach_disconnected,mediate_deleted) {
    #include <abstractions/base>
    #include <abstractions/nameservice>
    #include <abstractions/ssl_certs>

    /usr/sbin/php-fpm${PHP_VER} ix,
    /usr/bin/php mr,

    /usr/lib/** r,
    /lib/** r,

    /run/php/php-${SITE_USER}.sock rw,

    ${BASE_DIR}/current/** r,
    ${BASE_DIR}/shared/writable/** rwk,

    /tmp/** rw,

    deny /proc/** rw,
    deny /sys/** rw,
    deny /root/** rw,
}
EOF

    apparmor_parser -r "/etc/apparmor.d/php-fpm-${SITE_USER}" || true
    aa-enforce "php-fpm-${SITE_USER}" || true
}

setup_php_stack() {
    setup_ssh
    setup_php_pool
    setup_apparmor
}
