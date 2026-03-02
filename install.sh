#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="sipherxyz"
REPO_NAME="vesper-internal-release"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"
LATEST_RELEASE_API="${API_URL}/releases/latest"
DOWNLOAD_DIR="${HOME}/.vesper/downloads"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf "%b\n" "${BLUE}>${NC} $1"; }
success() { printf "%b\n" "${GREEN}>${NC} $1"; }
warn() { printf "%b\n" "${YELLOW}!${NC} $1"; }
error() { printf "%b\n" "${RED}x${NC} $1"; exit 1; }

DOWNLOAD_TOOL=""
if command -v curl >/dev/null 2>&1; then
  DOWNLOAD_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOAD_TOOL="wget"
else
  error "Either curl or wget is required"
fi

download_file() {
  local url="$1"
  local output_path="${2:-}"
  local with_progress="${3:-false}"

  if [ "$DOWNLOAD_TOOL" = "curl" ]; then
    if [ -n "$output_path" ]; then
      if [ "$with_progress" = "true" ]; then
        curl -fL --progress-bar -o "$output_path" "$url"
      else
        curl -fsSL -o "$output_path" "$url"
      fi
    else
      curl -fsSL "$url"
    fi
  else
    if [ -n "$output_path" ]; then
      if [ "$with_progress" = "true" ]; then
        wget --show-progress -q -O "$output_path" "$url"
      else
        wget -q -O "$output_path" "$url"
      fi
    else
      wget -q -O - "$url"
    fi
  fi
}

extract_tag_name() {
  echo "$1" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

extract_asset_field() {
  local json="$1"
  local asset_name="$2"
  local field_name="$3"

  awk -v asset_name="$asset_name" -v field_name="$field_name" '
    {
      if ($0 ~ "\"name\"[[:space:]]*:[[:space:]]*\"" asset_name "\"") {
        in_asset = 1
      } else if (in_asset && $0 ~ /\"name\"[[:space:]]*:/) {
        in_asset = 0
      }

      if (in_asset && $0 ~ "\"" field_name "\"[[:space:]]*:") {
        if (match($0, /"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
          value = substr($0, RSTART, RLENGTH)
          sub(/^"[^"]*"[[:space:]]*:[[:space:]]*"/, "", value)
          sub(/"$/, "", value)
          print value
          exit
        }
      }
    }
  ' <<< "$json"
}

calculate_sha256() {
  local path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi

  return 1
}

refresh_path() {
  local dir=""
  for dir in "$HOME/.local/bin" "$HOME/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
      PATH="$dir:$PATH"
    fi
  done
  export PATH
  hash -r
}

install_claude_if_needed() {
  refresh_path
  if command -v claude >/dev/null 2>&1; then
    success "Found Claude CLI: $(command -v claude)"
    return 0
  fi

  info "Claude CLI not found. Installing from https://code.claude.com/docs/en/overview ..."
  if download_file "https://claude.ai/install.sh" | bash; then
    refresh_path
    if command -v claude >/dev/null 2>&1; then
      success "Claude CLI installed: $(command -v claude)"
    else
      warn "Claude installer ran, but 'claude' is not in PATH yet. Restart your terminal if needed."
    fi
  else
    warn "Failed to install Claude CLI automatically. Install manually via https://code.claude.com/docs/en/overview"
  fi
}

install_ai_gateway_if_needed() {
  refresh_path
  if command -v ai-gateway >/dev/null 2>&1; then
    success "Found ai-gateway CLI: $(command -v ai-gateway)"
    return 0
  fi

  info "ai-gateway CLI not found. Installing from https://github.com/sipherxyz/ai-gateway-cli ..."
  if download_file "https://ai-gateway.atherlabs.com/install.sh" | bash; then
    refresh_path
    if command -v ai-gateway >/dev/null 2>&1; then
      success "ai-gateway CLI installed: $(command -v ai-gateway)"
    else
      warn "ai-gateway installer ran, but 'ai-gateway' is not in PATH yet. Restart your terminal if needed."
    fi
  else
    warn "Failed to install ai-gateway automatically. Install manually via https://github.com/sipherxyz/ai-gateway-cli"
  fi
}

ensure_ai_gateway_login_if_needed() {
  refresh_path
  if ! command -v ai-gateway >/dev/null 2>&1; then
    warn "Skipping ai-gateway login check because ai-gateway is not available."
    return 0
  fi

  info "Checking ai-gateway login status..."
  local status_output=""
  if status_output="$(ai-gateway status 2>&1)"; then
    :
  fi

  if printf "%s" "$status_output" | grep -Eqi "not[[:space:]-]*logged|not[[:space:]-]*authenticated|login required|sign[[:space:]-]*in required"; then
    info "ai-gateway is not logged in. Running 'ai-gateway login'..."
    if ai-gateway login; then
      success "ai-gateway login completed."
    else
      warn "ai-gateway login did not complete. You can run 'ai-gateway login' manually."
    fi
  else
    success "ai-gateway status does not indicate a missing login."
  fi
}

install_required_cli_dependencies() {
  echo ""
  info "Checking required CLI dependencies (claude, ai-gateway)..."
  install_claude_if_needed
  install_ai_gateway_if_needed
  ensure_ai_gateway_login_if_needed
}

OS_NAME="$(uname -s)"
ARCH_NAME="$(uname -m)"

case "$OS_NAME" in
  Darwin) OS_TYPE="darwin" ;;
  Linux) OS_TYPE="linux" ;;
  *) error "Unsupported operating system: ${OS_NAME}" ;;
esac

case "$ARCH_NAME" in
  x86_64|amd64) ARCH="x64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) error "Unsupported architecture: ${ARCH_NAME}" ;;
esac

ASSET_NAME=""
if [ "$OS_TYPE" = "darwin" ]; then
  if [ "$ARCH" = "arm64" ]; then
    ASSET_NAME="Vesper-arm64.dmg"
  else
    ASSET_NAME="Vesper-x64.dmg"
  fi
elif [ "$OS_TYPE" = "linux" ]; then
  if [ "$ARCH" != "x64" ]; then
    error "Linux installer currently supports x64 only. Detected: ${ARCH_NAME}"
  fi
  ASSET_NAME="Vesper-x86_64.AppImage"
fi

echo ""
info "Detected platform: ${OS_TYPE}-${ARCH}"
info "Looking for release asset: ${ASSET_NAME}"

mkdir -p "$DOWNLOAD_DIR"

info "Fetching latest release metadata..."
release_json="$(download_file "$LATEST_RELEASE_API")"
tag_name="$(extract_tag_name "$release_json")"

if [ -z "$tag_name" ]; then
  error "Could not determine latest release tag from GitHub API"
fi

asset_url="$(extract_asset_field "$release_json" "$ASSET_NAME" "browser_download_url")"
asset_digest="$(extract_asset_field "$release_json" "$ASSET_NAME" "digest")"

if [ -z "$asset_url" ]; then
  error "Asset ${ASSET_NAME} was not found in latest release (${tag_name})."
fi

info "Latest release: ${tag_name}"
installer_path="${DOWNLOAD_DIR}/${ASSET_NAME}"

info "Downloading ${ASSET_NAME}..."
download_file "$asset_url" "$installer_path" true

if [ ! -f "$installer_path" ]; then
  error "Download failed: file not found at ${installer_path}"
fi

expected_checksum=""
if [[ "$asset_digest" == sha256:* ]]; then
  expected_checksum="${asset_digest#sha256:}"
elif [ -n "$asset_digest" ]; then
  expected_checksum="$asset_digest"
fi

if [ -n "$expected_checksum" ]; then
  info "Verifying SHA-256 checksum..."
  actual_checksum="$(calculate_sha256 "$installer_path" || true)"

  if [ -z "$actual_checksum" ]; then
    warn "No SHA-256 tool found (sha256sum/shasum). Skipping checksum verification."
  elif [ "$actual_checksum" != "$expected_checksum" ]; then
    rm -f "$installer_path"
    error "Checksum verification failed\n  Expected: ${expected_checksum}\n  Actual:   ${actual_checksum}"
  else
    success "Checksum verified"
  fi
else
  warn "No checksum digest published for this asset. Skipping verification."
fi

if [ "$OS_TYPE" = "darwin" ]; then
  APP_NAME="Vesper.app"
  INSTALL_DIR="/Applications"

  if pgrep -x "Vesper" >/dev/null 2>&1; then
    info "Closing Vesper..."
    osascript -e 'tell application "Vesper" to quit' >/dev/null 2>&1 || true
    sleep 2
    if pgrep -x "Vesper" >/dev/null 2>&1; then
      warn "Vesper is still running. Force quitting..."
      pkill -9 -x "Vesper" >/dev/null 2>&1 || true
      sleep 1
    fi
  fi

  if [ -d "${INSTALL_DIR}/${APP_NAME}" ]; then
    info "Removing previous installation..."
    rm -rf "${INSTALL_DIR}/${APP_NAME}"
  fi

  info "Mounting DMG..."
  mount_point="$(hdiutil attach "$installer_path" -nobrowse -mountrandom /tmp 2>/dev/null | tail -1 | awk '{print $NF}')"

  if [ -z "$mount_point" ] || [ ! -d "$mount_point" ]; then
    rm -f "$installer_path"
    error "Failed to mount DMG"
  fi

  app_source="$(find "$mount_point" -maxdepth 1 -name '*.app' -type d | head -1)"
  if [ -z "$app_source" ]; then
    hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
    rm -f "$installer_path"
    error "No .app found in the DMG"
  fi

  info "Installing ${APP_NAME} into ${INSTALL_DIR}..."
  cp -R "$app_source" "${INSTALL_DIR}/${APP_NAME}"

  info "Cleaning up..."
  hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
  rm -f "$installer_path"

  xattr -rd com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}" >/dev/null 2>&1 || true

  install_required_cli_dependencies

  echo ""
  success "Installation complete"
  printf "%b\n" "  Installed: ${BOLD}${INSTALL_DIR}/${APP_NAME}${NC}"
  printf "%b\n" "  Launch: ${BOLD}open -a 'Vesper'${NC}"
  exit 0
fi

APP_DIR="${HOME}/.vesper/app"
APPIMAGE_PATH="${APP_DIR}/Vesper-x86_64.AppImage"
LAUNCHER_DIR="${HOME}/.local/bin"
LAUNCHER_PATH="${LAUNCHER_DIR}/vesper"

if pgrep -f 'Vesper.*AppImage' >/dev/null 2>&1; then
  info "Stopping Vesper..."
  pkill -f 'Vesper.*AppImage' >/dev/null 2>&1 || true
  sleep 1
fi

mkdir -p "$APP_DIR" "$LAUNCHER_DIR"
rm -f "$APPIMAGE_PATH"

info "Installing AppImage to ${APPIMAGE_PATH}..."
mv "$installer_path" "$APPIMAGE_PATH"
chmod +x "$APPIMAGE_PATH"

info "Creating launcher at ${LAUNCHER_PATH}..."
cat > "$LAUNCHER_PATH" <<'WRAPPER_EOF'
#!/usr/bin/env bash

APPIMAGE_PATH="$HOME/.vesper/app/Vesper-x86_64.AppImage"

if [ ! -f "$APPIMAGE_PATH" ]; then
  echo "Vesper AppImage not found at $APPIMAGE_PATH"
  exit 1
fi

export APPIMAGE="$APPIMAGE_PATH"
exec "$APPIMAGE_PATH" --no-sandbox "$@"
WRAPPER_EOF
chmod +x "$LAUNCHER_PATH"

install_required_cli_dependencies

echo ""
success "Installation complete"
printf "%b\n" "  AppImage: ${BOLD}${APPIMAGE_PATH}${NC}"
printf "%b\n" "  Launcher: ${BOLD}${LAUNCHER_PATH}${NC}"
printf "%b\n" "  Run: ${BOLD}vesper${NC}"

if ! command -v fusermount >/dev/null 2>&1; then
  warn "FUSE is not detected. Install it if AppImage fails to launch."
  printf "%b\n" "  Debian/Ubuntu: ${BOLD}sudo apt install fuse libfuse2${NC}"
  printf "%b\n" "  Fedora: ${BOLD}sudo dnf install fuse fuse-libs${NC}"
fi
