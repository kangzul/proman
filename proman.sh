#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# source libraries
. "${SCRIPT_DIR}/lib/common.sh"
. "${SCRIPT_DIR}/lib/database.sh"
. "${SCRIPT_DIR}/lib/php.sh"
. "${SCRIPT_DIR}/lib/nginx.sh"
. "${SCRIPT_DIR}/lib/users.sh"
. "${SCRIPT_DIR}/lib/deploy.sh"

prompt_basic() {
    read -rp "Nama project: " RAW_NAME
    read -rp "Domain: " DOMAIN

    validate_domain "$DOMAIN"

    SITE_USER=$(normalize_name "$RAW_NAME")
    validate_project "$SITE_USER"

    BASE_DIR="${WEB_ROOT_BASE}/${SITE_USER}"

    id "$SITE_USER" &>/dev/null && die "Project sudah ada"
}

prompt_features() {
    read -rp "Buat database? (yes/no): " WITH_DB
    [[ "$WITH_DB" =~ ^(yes|no)$ ]] || die "Input salah"

    read -rp "Jenis web (php/static): " WEB_TYPE
    [[ "$WEB_TYPE" =~ ^(php|static)$ ]] || die "Input salah"
}

summary() {
    echo
    echo "======================================"
    echo "PROJECT SIAP DEPLOY"
    echo "User Linux  : ${SITE_USER}"
    echo "Domain      : ${DOMAIN}"
    echo "Database    : ${DB_NAME}"
    echo "DB User     : ${DB_USER}"
    echo "DB Password : (saved to ${BASE_DIR}/shared/.env)"
    echo
    echo "SSH Deploy Public Key"
    echo "${SSH_PUB_KEY}"
    echo "======================================"
}

add_project() {
    prompt_basic
    prompt_features

    prepare_linux_user
    prepare_directories

    if [[ "$WITH_DB" == "yes" ]]; then
        setup_database
        generate_env
    fi

    if [[ "$WEB_TYPE" == "php" ]]; then
        setup_php_stack
        setup_nginx_php
    else
        setup_nginx_static
    fi

    write_metadata
    summary
}

# MAIN SCRIPT LOGIC

COMMAND="${1:-}"

case "$COMMAND" in
  add)
    require_root
    add_project
    ;;
  delete)
    require_root
    delete_project "$2"
    ;;
  list)
    list_project
    ;;
  deploy)
    shift
    deploy_project "$@"
    ;;
  *)
    die "Usage: $0 {add|delete|list|deploy}"
    ;;
esac