#!/usr/bin/env bash
# Database related helpers. Requires common.sh to be sourced first.

setup_database() {
    DB_NAME="db_${SITE_USER}"
    DB_USER="db_user_${SITE_USER}"
    DB_PASS=$(random_pass)

    mysql_exec "
    CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
    GRANT SELECT,INSERT,UPDATE,DELETE,EXECUTE ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
    FLUSH PRIVILEGES;
    "
}

generate_env() {
    mkdir -p "${BASE_DIR}/shared"
    cat <<EOF > "${BASE_DIR}/shared/.env"
#CI_ENVIRONMENT = development

app.baseURL = 'https://${DOMAIN}'
app.forceGlobalSecureRequests = true

database.default.hostname = localhost
database.default.database = ${DB_NAME}
database.default.username = ${DB_USER}
database.default.password = ${DB_PASS}
database.default.DBDriver = MySQLi
database.default.charset = utf8mb4
database.default.DBCollat = utf8mb4_unicode_ci
EOF
    chmod 640 "${BASE_DIR}/shared/.env"
    chown "${SITE_USER}:${SITE_USER}" "${BASE_DIR}/shared/.env"
}