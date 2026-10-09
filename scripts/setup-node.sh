#!/bin/bash

# --------------------------
# Setup user-owned NVM and Node.js for rolling Arch / Ubuntu 26.04
# --------------------------
# NVM lives at ~/.config/nvm (same path as home/.bashrc).
# Verified upstream files are staged without running an installer or editing rc files.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "NVM and Node.js"

if [[ "$EUID" == 0 || -n "${SUDO_USER:-}" ]]; then
  print_error_message "Run Node setup as the workstation user, without sudo"
  exit 1
fi

NVM_DIR="$(nvm_dir)"
export NVM_DIR
for existing in "$NVM_DIR" "$USER_HOME_DIR/.nvm"; do
  if [[ -e "$existing" || -L "$existing" ]]; then
    if [[ ! -d "$existing" || ! -O "$existing" || -L "$existing" ]]; then
      print_error_message "NVM source/ownership conflict: $existing; preserved"
      exit 1
    fi
    for file in nvm.sh nvm-exec bash_completion; do
      if [[ -L "$existing/$file" ]] || { [[ -e "$existing/$file" ]] && [[ ! -O "$existing/$file" ]]; }; then
        print_error_message "NVM file source/ownership conflict: $existing/$file; preserved"
        exit 1
      fi
    done
  fi
done
# Preserve another Node owner rather than silently installing a second runtime.
if [[ ! -s "$NVM_DIR/nvm.sh" && ! -s "$USER_HOME_DIR/.nvm/nvm.sh" ]] && command -v node &>/dev/null; then
  print_error_message "Existing Node has another source; retain its owner or explicitly migrate to NVM"
  exit 1
fi
ensure_core_cli curl
ensure_core_cli coreutils
ensure_native_pkgs ca-certificates tar
# Migrate legacy ~/.nvm if present
if [[ ! -s "$NVM_DIR/nvm.sh" && -s "$USER_HOME_DIR/.nvm/nvm.sh" ]]; then
  load_nvm || exit 1
else
  load_nvm || true
fi
mkdir -p "$NVM_DIR"

# Setup owns the pinned NVM files; aliases, runtimes, and npm packages stay user-owned.
if ! core_cli_version_at_least "$(nvm --version 2>/dev/null || true)" 0.40.3; then
  NVM_VERSION=0.40.3
  NVM_ARCHIVE_SHA256=5f4d6aaa04a177dc93c985e31dbc411ab6b8c6e1e21d8015dbc1372625fcd1d0

  print_action_message "Installing NVM ${NVM_VERSION} into $NVM_DIR"
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL "https://codeload.github.com/nvm-sh/nvm/tar.gz/refs/tags/v${NVM_VERSION}" -o "$stage/nvm.tar.gz"
  actual_sha="$(sha256sum "$stage/nvm.tar.gz" | awk '{print $1}')"
  if [[ "$actual_sha" != "$NVM_ARCHIVE_SHA256" ]]; then
    print_error_message "NVM archive checksum mismatch; existing files preserved"
    exit 1
  fi
  tar -xzf "$stage/nvm.tar.gz" -C "$stage" -- "nvm-$NVM_VERSION/nvm.sh" "nvm-$NVM_VERSION/nvm-exec" "nvm-$NVM_VERSION/bash_completion"
  for file in nvm.sh nvm-exec bash_completion; do
    [[ ! -L "$NVM_DIR/$file" ]] || { print_error_message "NVM file symlink conflict: $file"; exit 1; }
  done
  install -m 644 "$stage/nvm-$NVM_VERSION/nvm.sh" "$stage/nvm-$NVM_VERSION/bash_completion" "$NVM_DIR/"
  install -m 755 "$stage/nvm-$NVM_VERSION/nvm-exec" "$NVM_DIR/"
else
  print_info_message "NVM already installed at $NVM_DIR"
fi

if ! load_nvm; then
  print_error_message "NVM not available after install ($NVM_DIR/nvm.sh missing)"
  exit 1
fi

if nvm use default >/dev/null 2>&1; then
  print_info_message "Keeping the saved NVM default; Node updates: nvm install --lts, then select the default explicitly"
else
  # A broken user-selected default is a conflict, not permission to replace it.
  if [[ -e "$NVM_DIR/alias/default" ]]; then
    print_error_message "Saved NVM default is unavailable; preserved. Resolve it with nvm before rerunning"
    exit 1
  fi
  print_info_message "Installing Node.js LTS via NVM"
  nvm install --lts
  nvm alias default 'lts/*'
fi

for command in node npm; do
  launcher="$(readlink -f "$(type -P "$command")")"
  if [[ "$launcher" != "$NVM_DIR/"* || ! -O "$launcher" ]]; then
    print_error_message "Node/npm ownership conflict: $command must be user-owned inside $NVM_DIR"
    exit 1
  fi
done
npm_root="$(npm root -g)"
if [[ "$npm_root" != "$NVM_DIR/"* || ! -O "$npm_root" ]]; then
  print_error_message "npm prefix conflict: global packages must stay user-owned inside $NVM_DIR"
  exit 1
fi
node_version="$(node --version)"
if [[ ! "$node_version" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
  || ! core_cli_version_at_least "${BASH_REMATCH[1]}" 22.0.0; then
  print_error_message "Node 22+ required; saved default preserved. Select a compatible LTS with nvm"
  exit 1
fi

print_info_message "Node.js version: $(node --version)"
print_info_message "npm version: $(npm --version)"
print_info_message "NVM version: $(nvm --version)"
print_info_message "NVM_DIR=$NVM_DIR (loaded from ~/.bashrc in new shells)"

print_tool_setup_complete "NVM and Node.js"
