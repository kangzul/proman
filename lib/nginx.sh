#!/usr/bin/env bash
# Nginx site templates for php and static sites

setup_nginx_php() {
    cat <<EOF > "${NGINX_AVAIL}/${SITE_USER}.conf"
server {
    listen 80;
    server_name ${DOMAIN};
    #include snippets/ssl-strong.conf;
    root ${WEB_ROOT_BASE}/${SITE_USER};
    index index.php;

    #ssl_certificate /etc/nginx/ssl/folder/fullchain.pem;
    #ssl_certificate_key /etc/nginx/ssl/folder/key.pem;

    access_log /var/log/nginx/${SITE_USER}.access.log;
    error_log  /var/log/nginx/${SITE_USER}.error.log;

    if (\$is_env_scan) {
        return 444;
    }

    if (\$is_backdoor_scan) {
        return 444;
    }

    client_max_body_size 10M;

    location / {
        limit_req zone=one burst=10 nodelay;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ ^/index\.php(/|$) {
        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$document_root;

        fastcgi_pass unix:/run/php/php-${SITE_USER}.sock;
        fastcgi_index index.php;

        fastcgi_connect_timeout 10s;
        fastcgi_send_timeout 30s;
        fastcgi_read_timeout 30s;

        fastcgi_buffer_size 32k;
        fastcgi_buffers 8 16k;
        fastcgi_busy_buffers_size 64k;
    }

    location ~ \.php$ { return 404; }

    location ~* ^/(assets|css|js|images|fonts)/.*\.(css|js|png|jpg|jpeg|gif|ico|woff2?|ttf|svg|webp)$ {
        expires 30d;
        access_log off;
        log_not_found off;
        add_header Cache-Control "public, immutable";
    }

    location ~* \.(env|log|sql|bak|git|svn|htaccess|htpasswd)$ {
        deny all;
    }

    location ~ \. { deny all; }
}
EOF
    ln -sfn "${NGINX_AVAIL}/${SITE_USER}.conf" "${NGINX_ENABLED}/${SITE_USER}.conf"

    PUBLIC_ROOT="${WEB_ROOT_BASE}/${SITE_USER}"
    mkdir -p "${WEB_ROOT_BASE}"
    # Ensure the release public directory exists so the symlink won't be dangling
    mkdir -p "${BASE_DIR}/current/public"
    chown -R "${SITE_USER}:${SITE_USER}" "${BASE_DIR}/current/public" || true
    chmod -R 750 "${BASE_DIR}/current/public" || true
    ln -sfn "${BASE_DIR}/current/public" "${PUBLIC_ROOT}"

    # Hardening: ensure public dir ownership and permissions
    if [[ -d "${BASE_DIR}/current/public" ]]; then
        chown -R "${SITE_USER}:www-data" "${BASE_DIR}/current/public" || true
        chmod -R 750 "${BASE_DIR}/current/public" || true
    fi

    # Ensure central webroot directory ownership and permissions
    chown root:www-data "${WEB_ROOT_BASE}" 2>/dev/null || true
    chmod 755 "${WEB_ROOT_BASE}" 2>/dev/null || true

    # Ensure user home base is not world-readable
    chmod 711 "${USER_HOME_BASE}" 2>/dev/null || true

    nginx -t || die "Config nginx error"
    system_reload nginx
}

setup_nginx_static() {
    cat <<EOF > "${NGINX_AVAIL}/${SITE_USER}.conf"
server {
    listen 80;
    server_name ${DOMAIN};
    #include snippets/ssl-strong.conf;

    root ${BASE_DIR}/current/public;
    index index.html;

    #ssl_certificate /etc/nginx/ssl/folder/fullchain.pem;
    #ssl_certificate_key /etc/nginx/ssl/folder/key.pem;

    access_log /var/log/nginx/${SITE_USER}.access.log;
    error_log  /var/log/nginx/${SITE_USER}.error.log;

    if (\$is_env_scan) {
        return 444;
    }

    if (\$is_backdoor_scan) {
        return 444;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?)$ {
        expires 30d;
        access_log off;
    }

    location ~ /\. {
        deny all;
    }
}
EOF
    ln -sfn "${NGINX_AVAIL}/${SITE_USER}.conf" "${NGINX_ENABLED}/${SITE_USER}.conf"

    # Ensure public webroot symlink from central webroot to user's project public
    PUBLIC_ROOT="${WEB_ROOT_BASE}/${SITE_USER}"
    mkdir -p "${WEB_ROOT_BASE}"
    # Ensure the release public directory exists so the symlink won't be dangling
    mkdir -p "${BASE_DIR}/current/public"
    chown -R "${SITE_USER}:${SITE_USER}" "${BASE_DIR}/current/public" || true
    chmod -R 750 "${BASE_DIR}/current/public" || true
    ln -sfn "${BASE_DIR}/current/public" "${PUBLIC_ROOT}"

    # Hardening: ensure public dir ownership and permissions
    if [[ -d "${BASE_DIR}/current/public" ]]; then
        chown -R "${SITE_USER}:www-data" "${BASE_DIR}/current/public" || true
        chmod -R 750 "${BASE_DIR}/current/public" || true
    fi

    # Ensure central webroot directory ownership and permissions
    chown root:www-data "${WEB_ROOT_BASE}" 2>/dev/null || true
    chmod 755 "${WEB_ROOT_BASE}" 2>/dev/null || true

    # Ensure user home base is not world-readable
    chmod 711 "${USER_HOME_BASE}" 2>/dev/null || true

    nginx -t || die "Config nginx error"
    system_reload nginx
}
