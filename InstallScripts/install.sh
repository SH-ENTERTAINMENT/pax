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
        # shellcheck disable=SC2039
        read -r reply < /dev/tty || reply=""
    else
        # No interactive terminal available (e.g. fully non-interactive CI).
        reply=""
    fi
    case "$reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

fuse3_pkg_install_cmd() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get update -qq && apt-get install -y libfuse3-3"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf install -y fuse3-libs"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman -Sy --noconfirm fuse3"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper --non-interactive install libfuse3-3"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk update && apk add fuse3-libs"
    else
        return 1
    fi
}

fuse3_manual_hint() {
    pkg_cmd="$(fuse3_pkg_install_cmd 2>/dev/null)" || {
        echo "install libfuse3 (or fuse3) using your distribution's package manager"
        return 0
    }
    echo "sudo sh -c '${pkg_cmd}'"
}

auto_install_fuse3() {
    [ "$PAX_SKIP_FUSE_INSTALL" = "1" ] && return 1

    pkg_cmd="$(fuse3_pkg_install_cmd 2>/dev/null)" || return 1

    if [ "$(id -u)" -eq 0 ]; then
        info "attempting to install libfuse3 automatically..."
        sh -c "$pkg_cmd" >/dev/null 2>&1 && return 0
        return 1
    fi

    if command -v sudo >/dev/null 2>&1; then
        info "pax needs libfuse3 to support 'pax mount' / 'pax unmount'."
        if confirm "Install it now using sudo? This will run: ${pkg_cmd}"; then
            info "requesting sudo permission to install libfuse3..."
            sudo sh -c "$pkg_cmd" && return 0
            return 1
        else
            info "skipping automatic libfuse3 install (declined)."
            return 1
        fi
    fi

    return 1
}

refresh_ld_cache() {
    command -v ldconfig >/dev/null 2>&1 || return 0
    if [ "$(id -u)" -eq 0 ]; then
        ldconfig 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        # Reuses the sudo session opened moments ago by auto_install_fuse3,
        # so this normally does not prompt for a password again.
        sudo ldconfig 2>/dev/null || true
    fi
}

check_runtime_deps() {
    binary="$1"
    [ "$OS_TRIPLE" = "unknown-linux-gnu" ] || return 0
    command -v ldd >/dev/null 2>&1 || return 0

    missing="$(ldd "$binary" 2>/dev/null | grep "not found" || true)"
    [ -n "$missing" ] || return 0

    if printf '%s' "$missing" | grep -q "libfuse3"; then
        warn "libfuse3 is required for 'pax mount' / 'pax unmount' but is not installed."
        if auto_install_fuse3; then
            info "libfuse3 installed successfully."
            refresh_ld_cache
            missing="$(ldd "$binary" 2>/dev/null | grep "not found" || true)"
        else
            warn "could not install libfuse3 automatically."
            warn "install it manually with: $(fuse3_manual_hint)"
        fi
    fi

    [ -n "$missing" ] || return 0

    warn "pax is still missing shared libraries and may not run correctly:"
    printf '%s\n' "$missing" | while IFS= read -r line; do
        printf '[pax]   %s\n' "$line"
    done
    warn "if the library is installed but still not found, try: sudo ldconfig"
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

add_path_line() {
    profile_file="$1"
    line="export PATH=\"${PAX_INSTALL_DIR}:\$PATH\""
    [ -f "$profile_file" ] || return 0
    if ! grep -qF "$PAX_INSTALL_DIR" "$profile_file" 2>/dev/null; then
        printf '\n# Added by the pax installer\n%s\n' "$line" >> "$profile_file"
        info "updated $profile_file"
    fi
}

info "pax will be added to your PATH automatically in your shell profile."
CURRENT_SHELL="$(basename "${SHELL:-sh}")"
case "$CURRENT_SHELL" in
    zsh) add_path_line "$HOME/.zshrc" ;;
    bash) add_path_line "$HOME/.bashrc"; add_path_line "$HOME/.bash_profile" ;;
    *) add_path_line "$HOME/.profile" ;;
esac

info "pax v${VERSION} installed successfully."
info "restart your terminal, or run: export PATH=\"${PAX_INSTALL_DIR}:\$PATH\""
"$PAX_INSTALL_DIR/pax" version || true
