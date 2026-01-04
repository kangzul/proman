#!/usr/bin/env bash
# Nginx site templates for php and static sites

setup_nginx_php() {
    cat <<'EOF' > "${NGINX_AVAIL}/${SITE_USER}.conf"
server {
    listen 80;
    server_name ${DOMAIN};
    #include snippets/ssl-strong.conf;
    root ${BASE_DIR}/current/public;
    index index.php;

    #ssl_certificate /etc/nginx/ssl/folder/fullchain.pem;
    #ssl_certificate_key /etc/nginx/ssl/folder/key.pem;

    access_log /var/log/nginx/${SITE_USER}.access.log;
    error_log  /var/log/nginx/${SITE_USER}.error.log;

    if ($is_env_scan) {
        return 444;
    }

    if ($is_backdoor_scan) {
        return 444;
    }

    client_max_body_size 10M;

    location / {
        limit_req zone=one burst=10 nodelay;
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ ^/index\.php(/|$) {
        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $document_root;

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

    nginx -t || die "Config nginx error"
    systemctl reload nginx
}

setup_nginx_static() {
    cat <<'EOF' > "${NGINX_AVAIL}/${SITE_USER}.conf"
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

    if ($is_env_scan) {
        return 444;
    }

    if ($is_backdoor_scan) {
        return 444;
    }

    location / {
        try_files $uri $uri/ =404;
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

    nginx -t || die "Config nginx error"
    systemctl reload nginx
}
