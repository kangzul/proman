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

    # ensure permissions and symlink
    ln -sfn "$NEW_RELEASE" "$CURRENT"
    ln -sfn "$BASE_DIR/current/public" "$PUBLIC_ROOT"

    chmod 711 /home
    chmod 711 "$BASE_DIR"
    chmod 711 "$RELEASES"

    # Release private
    find "$NEW_RELEASE" -type d -exec chmod 750 {} \;
    find "$NEW_RELEASE" -type f -exec chmod 640 {} \;

    # Shared
    chmod 750 "$SHARED" || true
    chmod 640 "$ENV_FILE" || true

    # Public (read-only for nginx)
    find "$NEW_RELEASE/public" -type d -exec chmod 755 {} \; || true
    find "$NEW_RELEASE/public" -type f -exec chmod 644 {} \; || true

    # /var/www boundary
    chown -h "$project:$project" "$PUBLIC_ROOT" || true
    chmod 755 "$PUBLIC_ROOT" || true

    echo "Deploy sukses: $project @ $tag"
}