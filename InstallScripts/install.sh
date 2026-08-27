#!/usr/bin/env sh
set -eu

PAX_REPO_OWNER="SH-ENTERTAINMENT"
PAX_REPO_NAME="pax"
PAX_INSTALL_DIR="${PAX_INSTALL_DIR:-$HOME/.pax/bin}"

info() { printf '[pax] %s\n' "$1"; }
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

add_path_line() {
    profile_file="$1"
    line="export PATH=\"${PAX_INSTALL_DIR}:\$PATH\""
    [ -f "$profile_file" ] || return 0
    if ! grep -qF "$PAX_INSTALL_DIR" "$profile_file" 2>/dev/null; then
        printf '\n# Added by the pax installer\n%s\n' "$line" >> "$profile_file"
        info "updated $profile_file"
    fi
}

CURRENT_SHELL="$(basename "${SHELL:-sh}")"
case "$CURRENT_SHELL" in
    zsh) add_path_line "$HOME/.zshrc" ;;
    bash) add_path_line "$HOME/.bashrc"; add_path_line "$HOME/.bash_profile" ;;
    *) add_path_line "$HOME/.profile" ;;
esac

info "pax v${VERSION} installed successfully."
info "restart your terminal, or run: export PATH=\"${PAX_INSTALL_DIR}:\$PATH\""
"$PAX_INSTALL_DIR/pax" version || true
