#!/usr/bin/env bash
# Deployment helper: clone and set permissions

deploy_project() {
    local project="$1"
    local tag="$2"

    [[ -z "$project" || -z "$tag" ]] && \
        die "Usage: deploy <project> <git-tag>"

    BASE_DIR="${USER_HOME_BASE}/${project}"
    META="$BASE_DIR/.project.conf"

    [[ -f "$META" ]] || die "Metadata tidak ditemukan"
    # shellcheck disable=SC1090
    source "$META"

    # Ensure SITE_USER is defined (fallback to project name)
    SITE_USER="${SITE_USER:-$project}"

    RELEASES="$BASE_DIR/releases"
    SHARED="$BASE_DIR/shared"
    CURRENT="$BASE_DIR/current"
    ENV_FILE="$SHARED/.env"
    PUBLIC_ROOT="/var/www/${project}"

    mkdir -p "$RELEASES"
    mkdir -p /var/www

    TS=$(date +%Y%m%d%H%M%S)
    NEW_RELEASE="$RELEASES/$TS-$tag"

    # clone as site user into the target release directory (avoid nested bash -c quoting)
    run_as_user "$project" git clone --branch "$tag" --depth=1 "$GIT_REPO" "$NEW_RELEASE"

    # verify clone created the release dir
    [[ -d "$NEW_RELEASE" ]] || die "Gagal clone repo ke $NEW_RELEASE"

    # --- TAHAP DINAMIS: CLEANUP & SYMLINK ---
    # Fungsi ini membaca variabel dari .project.conf yang baru di-source
    process_deployment_steps "$NEW_RELEASE" || die "Gagal proses deployment steps"

    # Pre-deploy validation: verify nginx and php-fpm configs before switching symlink
    nginx -t || die "Nginx config test failed"

    # Robust detection of PHP-FPM binary (try several common names and locations)
    php_fpm_bin=""
    for candidate in "php-fpm${PHP_VER}" "php${PHP_VER}-fpm" "php-fpm"; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            php_fpm_bin=$(command -v "${candidate}")
            break
        fi
    done
    if [[ -z "${php_fpm_bin}" ]]; then
        for p in /usr/sbin/php*-fpm /usr/bin/php*-fpm; do
            if [[ -x "${p}" ]]; then
                php_fpm_bin="${p}"
                break
            fi
        done
    fi
    if [[ -n "${php_fpm_bin}" ]]; then
        "${php_fpm_bin}" -t || die "PHP-FPM config test failed for ${php_fpm_bin}"
    fi

    # ensure permissions and symlink
    # If $CURRENT exists as a plain directory (from initial setup),
    if [[ -d "$CURRENT" && ! -L "$CURRENT" ]]; then
        echo "Info: $CURRENT exists as directory; replacing it with symlink to new release"
        # Safety check: ensure we're operating on the expected current path
        [[ -n "$BASE_DIR" && "$CURRENT" == "$BASE_DIR/current" ]] || die "Safety: unexpected CURRENT path: $CURRENT"

        # Remove all entries inside current (files, dirs, symlinks)
        if find "$CURRENT" -mindepth 1 -maxdepth 1 -print -exec rm -rf {} +; then
            echo "Info: Bersih -> $CURRENT"
        else
            die "Gagal menghapus isi $CURRENT"
        fi

        # Remove the now-empty current directory so ln -sfn can create a symlink
        if rmdir "$CURRENT"; then
            echo "Info: Menghapus direktori $CURRENT untuk digantikan symlink"
        else
            die "Gagal menghapus direktori $CURRENT"
        fi
    fi

    ln -sfn "$NEW_RELEASE" "$CURRENT"

    # Hardening: ensure public dir perms and ownership, and central webroot ownership
    if [[ -d "$BASE_DIR/current/public" ]]; then
        chown -R "${SITE_USER}:www-data" "$BASE_DIR/current/public" || true
        chmod -R 750 "$BASE_DIR/current/public" || true
    fi
    chown root:www-data "$PUBLIC_ROOT" 2>/dev/null || true
    chmod 755 "$PUBLIC_ROOT" 2>/dev/null || true
    if [[ -d "$BASE_DIR/current/public" ]]; then
        ln -sfn "$BASE_DIR/current/public" "$PUBLIC_ROOT"
    else
        echo "Warning: ${BASE_DIR}/current/public not found; skipping ${PUBLIC_ROOT} symlink"
    fi

    chmod 711 /home
    chmod 711 "$BASE_DIR"
    chmod 711 "$RELEASES"

    # Berikan akses ke Nginx melalui grup, bukan 'others'
    chown -R "${SITE_USER}:www-data" "$NEW_RELEASE"
    find "$NEW_RELEASE" -type d -exec chmod 750 {} \;
    find "$NEW_RELEASE" -type f -exec chmod 640 {} \;

    # Shared
    chmod 750 "$SHARED" || die "Gagal chmod shared"
    chmod 600 "$ENV_FILE" || die "Gagal chmod .env"

    # Public (read-only for nginx)
    if [[ -d "$NEW_RELEASE/public" ]]; then
        find "$NEW_RELEASE/public" -type d -exec chmod 755 {} \; || die "Gagal chmod folder dalam public dirs"
        find "$NEW_RELEASE/public" -type f -exec chmod 644 {} \; || die "Gagal chmod file dalam public dirs"
    else
        echo "Warning: $NEW_RELEASE/public tidak ditemukan; melewati langkah chmod untuk public files"
    fi

    # Folder public tetap harus bisa dibaca nginx (only if exists)
    if [[ -e "$PUBLIC_ROOT" ]]; then
        chmod 750 "$PUBLIC_ROOT"
    else
        echo "Warning: ${PUBLIC_ROOT} missing; skipping chmod"
    fi

    echo "Deploy sukses: $project @ $tag"
}

process_deployment_steps() {
    local target_dir="$1"
    
    # 1. Hapus File/Folder secara Dinamis
    if [[ -n "${DELETE_PATHS:-}" ]]; then
        IFS=',' read -ra PATHS_TO_DELETE <<< "$DELETE_PATHS"
        for item in "${PATHS_TO_DELETE[@]}"; do
            local full_path="${target_dir}/${item}"
            if [[ -e "$full_path" || -L "$full_path" ]]; then
                rm -rf "$full_path"
                echo "Log: Terhapus -> $item"
            fi
        done
    fi

    # 2. Buat Symlink (Bisa File atau Folder)
    if [[ -n "${SYMLINK_PATHS:-}" ]]; then
        IFS=',' read -ra LINKS <<< "$SYMLINK_PATHS"
        for pair in "${LINKS[@]}"; do
            # Memisahkan source dan target berdasarkan titik dua (:)
            local src_rel="${pair%%:*}"
            local dest_rel="${pair#*:}"
            
            local src_full="${BASE_DIR}/${src_rel}"
            local dest_full="${target_dir}/${dest_rel}"

            # Validasi: Source harus ada agar symlink tidak 'broken'
            if [[ ! -e "$src_full" ]]; then
                echo "Warning: Source symlink $src_rel tidak ditemukan. Melewati..."
                continue
            fi

            # Pastikan direktori induk tujuan sudah ada
            mkdir -p "$(dirname "$dest_full")"
            
            # Buat symlink secara paksa (force) agar terupdate jika sudah ada
            ln -sfn "$src_full" "$dest_full"
            echo "Log: Linked -> $src_rel ke $dest_rel"
        done
    fi
}