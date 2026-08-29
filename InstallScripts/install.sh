#!/usr/bin/env sh
set -eu

PAX_REPO_OWNER="SH-ENTERTAINMENT"
PAX_REPO_NAME="pax"
PAX_INSTALL_DIR="${PAX_INSTALL_DIR:-$HOME/.pax/bin}"
PAX_SKIP_FUSE_INSTALL="${PAX_SKIP_FUSE_INSTALL:-0}"

info() { printf '[pax] %s\n' "$1"; }
warn() { printf '[pax] warning: %s\n' "$1" >&2; }
fail() { printf '[pax] error: %s\n' "$1" >&2; exit 1; }

detect_os() {
    case "$(uname -s)" in
        Linux) echo "unknown-linux-gnu" ;;
        Darwin) echo "apple-darwin" ;;
        *) fail "unsupported operating system: $(uname -s)" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "aarch64" ;;
        *) fail "unsupported architecture: $(uname -m)" ;;
    esac
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "required command '$1' was not found"
}

confirm() {
    prompt="$1"
    if [ -r /dev/tty ]; then
        printf '[pax] %s [y/N] ' "$prompt" > /dev/tty
        read -r reply < /dev/tty || reply=""
    else
        reply=""
    fi
    case "$reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

fuse3_pkg_install_cmd() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get update -qq && apt-get install -y fuse3"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf install -y fuse3"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman -Sy --noconfirm fuse3"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper --non-interactive install fuse3"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk update && apk add fuse3"
    else
        return 1
    fi
}

fuse3_manual_hint() {
    pkg_cmd="$(fuse3_pkg_install_cmd 2>/dev/null)" || {
        echo "install fuse3 using your distribution's package manager"
        return 0
    }
    echo "sudo sh -c '${pkg_cmd}'"
}

auto_install_fuse3() {
    [ "$PAX_SKIP_FUSE_INSTALL" = "1" ] && return 1

    pkg_cmd="$(fuse3_pkg_install_cmd 2>/dev/null)" || return 1

    if [ "$(id -u)" -eq 0 ]; then
        info "attempting to install fuse3 automatically..."
        sh -c "$pkg_cmd" && return 0
        return 1
    fi

    if command -v sudo >/dev/null 2>&1; then
        info "pax needs fuse3 to support 'pax mount' / 'pax unmount'."
        if confirm "Install it now using sudo? This will run: ${pkg_cmd}"; then
            info "requesting sudo permission to install fuse3..."
            sudo sh -c "$pkg_cmd" && return 0
            return 1
        else
            info "skipping automatic fuse3 install (declined)."
            return 1
        fi
    fi

    return 1
}

check_runtime_deps() {
    binary="$1"

    if command -v fusermount3 >/dev/null 2>&1 || command -v fusermount >/dev/null 2>&1; then
        return 0
    fi

    warn "fuse3 is required for 'pax mount' / 'pax unmount' but is not installed."
    if auto_install_fuse3; then
        info "fuse3 installed successfully."
    else
        warn "could not install fuse3 automatically."
        warn "install it manually with: $(fuse3_manual_hint)"
    fi

    if command -v ldd >/dev/null 2>&1; then
        missing="$(ldd "$binary" 2>/dev/null | grep "not found" || true)"
        if [ -n "$missing" ]; then
            warn "pax is still missing shared libraries and may not run correctly:"
            printf '%s\n' "$missing" | while IFS= read -r line; do
                printf '[pax]   %s\n' "$line"
            done
        fi
    fi
}

require_cmd curl
require_cmd tar
require_cmd mkdir

OS_TRIPLE="$(detect_os)"
ARCH="$(detect_arch)"
TARGET="${ARCH}-${OS_TRIPLE}"

info "detecting latest release for ${TARGET}..."
API_URL="https://api.github.com/repos/${PAX_REPO_OWNER}/${PAX_REPO_NAME}/releases/latest"
RELEASE_JSON="$(curl -fsSL "$API_URL")" || fail "failed to query GitHub releases API"

VERSION="$(printf '%s' "$RELEASE_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/')"
[ -n "$VERSION" ] || fail "could not determine the latest pax version"

ASSET_NAME="pax-${VERSION}-${TARGET}"
DOWNLOAD_URL="https://github.com/${PAX_REPO_OWNER}/${PAX_REPO_NAME}/releases/download/v${VERSION}/${ASSET_NAME}"
CHECKSUMS_URL="https://github.com/${PAX_REPO_OWNER}/${PAX_REPO_NAME}/releases/download/v${VERSION}/SHA256SUMS"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

info "downloading pax v${VERSION} for ${TARGET}..."
curl -fsSL "$DOWNLOAD_URL" -o "$WORK_DIR/pax" || fail "failed to download $DOWNLOAD_URL"
curl -fsSL "$CHECKSUMS_URL" -o "$WORK_DIR/SHA256SUMS" || fail "failed to download SHA256SUMS"

info "verifying checksum..."
EXPECTED_SUM="$(grep "$ASSET_NAME" "$WORK_DIR/SHA256SUMS" | awk '{print $1}')"
[ -n "$EXPECTED_SUM" ] || fail "no checksum entry found for $ASSET_NAME"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SUM="$(sha256sum "$WORK_DIR/pax" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    ACTUAL_SUM="$(shasum -a 256 "$WORK_DIR/pax" | awk '{print $1}')"
else
    fail "neither sha256sum nor shasum is available to verify the download"
fi

[ "$EXPECTED_SUM" = "$ACTUAL_SUM" ] || fail "checksum mismatch: expected $EXPECTED_SUM, got $ACTUAL_SUM"

info "installing to ${PAX_INSTALL_DIR}..."
mkdir -p "$PAX_INSTALL_DIR"
chmod +x "$WORK_DIR/pax"
mv "$WORK_DIR/pax" "$PAX_INSTALL_DIR/pax"

check_runtime_deps "$PAX_INSTALL_DIR/pax"

try_symlink_to_shared_bin() {
    for dir in /usr/local/bin "$HOME/.local/bin"; do
        [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || continue
        [ -w "$dir" ] || continue
        ln -sf "$PAX_INSTALL_DIR/pax" "$dir/pax" 2>/dev/null || continue
        info "linked pax into $dir (already on most shells' PATH)"
        return 0
    done
    return 1
}

add_posix_path_line() {
    profile_file="$1"
    line="export PATH=\"${PAX_INSTALL_DIR}:\$PATH\""
    mkdir -p "$(dirname "$profile_file")" 2>/dev/null || true
    touch "$profile_file" 2>/dev/null || return 0
    if ! grep -qF "$PAX_INSTALL_DIR" "$profile_file" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$profile_file"
        info "updated $profile_file"
    fi
}

add_fish_path_line() {
    profile_file="$1"
    line="fish_add_path ${PAX_INSTALL_DIR}"
    mkdir -p "$(dirname "$profile_file")" 2>/dev/null || true
    touch "$profile_file" 2>/dev/null || return 0
    if ! grep -qF "$PAX_INSTALL_DIR" "$profile_file" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$profile_file"
        info "updated $profile_file"
    fi
}

add_csh_path_line() {
    profile_file="$1"
    line="setenv PATH \"${PAX_INSTALL_DIR}:\$PATH\""
    mkdir -p "$(dirname "$profile_file")" 2>/dev/null || true
    touch "$profile_file" 2>/dev/null || return 0
    if ! grep -qF "$PAX_INSTALL_DIR" "$profile_file" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$profile_file"
        info "updated $profile_file"
    fi
}

if try_symlink_to_shared_bin; then
    :
else
    warn "could not write to /usr/local/bin or ~/.local/bin, falling back to shell profile files"
    add_posix_path_line "$HOME/.profile"
    add_posix_path_line "$HOME/.bashrc"
    add_posix_path_line "$HOME/.bash_profile"
    add_posix_path_line "$HOME/.zshrc"
    add_fish_path_line "$HOME/.config/fish/config.fish"
    add_csh_path_line "$HOME/.cshrc"
    add_csh_path_line "$HOME/.tcshrc"
fi

info "pax v${VERSION} installed successfully."
info "restart your terminal, or run: export PATH=\"${PAX_INSTALL_DIR}:\$PATH\""
"$PAX_INSTALL_DIR/pax" version || true
