#!/usr/bin/env bash
# Deployment helper: clone and set permissions

deploy_project() {
    local project="$1"
    local tag="$2"

    [[ -z "$project" || -z "$tag" ]] && \
        die "Usage: deploy <project> <git-tag>"

    BASE_DIR="${WEB_ROOT_BASE}/${project}"
    META="$BASE_DIR/.project.conf"

    [[ -f "$META" ]] || die "Metadata tidak ditemukan"
    # shellcheck disable=SC1090
    source "$META"

    RELEASES="$BASE_DIR/releases"
    SHARED="$BASE_DIR/shared"
    CURRENT="$BASE_DIR/current"
    ENV_FILE="$SHARED/.env"
    PUBLIC_ROOT="/var/www/${project}"

    mkdir -p "$RELEASES"
    mkdir -p /var/www

    TS=$(date +%Y%m%d%H%M%S)
    NEW_RELEASE="$RELEASES/$TS-$tag"

    # clone as site user into the target release directory
    run_as_user "$project" bash -c "git clone --branch '$tag' --depth=1 '$GIT_REPO' '$NEW_RELEASE'"

    # --- TAHAP DINAMIS: CLEANUP & SYMLINK ---
    # Fungsi ini membaca variabel dari .project.conf yang baru di-source
    process_deployment_steps "$NEW_RELEASE" || die "Gagal proses deployment steps"

    # ensure permissions and symlink
    ln -sfn "$NEW_RELEASE" "$CURRENT"
    ln -sfn "$BASE_DIR/current/public" "$PUBLIC_ROOT"

    chmod 711 /home
    chmod 711 "$BASE_DIR"
    chmod 711 "$RELEASES"

    # Berikan akses ke Nginx melalui grup, bukan 'others'
    chown -R ${SITE_USER}:www-data "$NEW_RELEASE"
    find "$NEW_RELEASE" -type d -exec chmod 750 {} \;
    find "$NEW_RELEASE" -type f -exec chmod 640 {} \;

    # Shared
    chmod 750 "$SHARED" || die "Gagal chmod shared"
    chmod 640 "$ENV_FILE" || die "Gagal chmod .env"

    # Public (read-only for nginx)
    find "$NEW_RELEASE/public" -type d -exec chmod 755 {} \; || die "Gagal chmod folder dalam public dirs"
    find "$NEW_RELEASE/public" -type f -exec chmod 644 {} \; || die "Gagal chmod file dalam public dirs"

    # Folder public tetap harus bisa dibaca nginx
    chmod 750 "$PUBLIC_ROOT"

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