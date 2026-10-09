#!/usr/bin/env bash
# Harness source decisions use supplied facts; no package operations here.
harness_npm_package() {
  case "$1" in
    claude) echo @anthropic-ai/claude-code ;;
    codex) echo @openai/codex ;;
    pi) echo @earendil-works/pi-coding-agent ;;
    opencode) echo opencode-ai ;;
    *) return 1 ;;
  esac
}

# distro, harness, native-package-installed, resolved-launcher, npm-owned, Claude-native-owned
harness_update_owner() {
  local distro="$1" harness="$2" native="$3" launcher="$4" npm_owned="$5" claude_native="$6"
  case "$distro" in arch|ubuntu) ;; *) return 1 ;; esac
  harness_npm_package "$harness" >/dev/null || return 1
  if [[ "$native" == true ]]; then
    [[ "$harness" == opencode && "$distro" == arch && "$launcher" == /usr/bin/opencode \
      && "$npm_owned" == false ]] || return 1
    echo native
  elif [[ "$claude_native" == true ]]; then
    [[ "$harness" == claude && "$npm_owned" == false ]] || return 1
    echo claude-native
  elif [[ "$npm_owned" == true || -z "$launcher" ]]; then
    if [[ -z "$launcher" && "$harness:$distro" == opencode:arch ]]; then
      echo native
    else
      echo npm
    fi
  else
    print_error_message "Source conflict: $harness launcher has no recognized update owner; retained" >&2
    return 1
  fi
}

# Runtime fact gathering is separate from read-only selection checks.
harness_installed_owner() {
  local harness="$1" launcher package root package_dir native=false npm_owned=false claude_native=false
  package="$(harness_npm_package "$harness")" || return 1
  launcher="$(type -P "$harness" || true)"
  [[ -z "$launcher" ]] || launcher="$(readlink -f "$launcher")" || return 1
  if [[ "$harness:$WORKSTATION_DISTRO" == opencode:arch ]] && native_package_installed opencode; then
    native=true
  fi
  if [[ "$harness" == claude ]] && claude_native_owns_launcher "$USER_HOME_DIR/.local/share/claude" "$launcher"; then
    harness_update_owner "$WORKSTATION_DISTRO" "$harness" "$native" "$launcher" false true
    return $?
  fi
  if command -v npm &>/dev/null; then
    root="$(npm root -g)" || return 1
    root="$(readlink -f "$root")" || return 1
    # Never adopt a root/system prefix, even if its CLI appears on PATH.
    if [[ "$root" == "$USER_HOME_DIR/"* ]]; then
      package_dir="$(readlink -f "$root/$package" || true)"
      npm_harness_owns_launcher "$package_dir" "$launcher" && npm_owned=true
    fi
  fi
  harness_update_owner "$WORKSTATION_DISTRO" "$harness" "$native" "$launcher" "$npm_owned" "$claude_native"
}

ensure_harness_cli() {
  local harness="$1" owner package root allowed
  [[ "$EUID" != 0 ]] || { print_error_message 'Run harness setup as the user, without sudo'; return 1; }
  # A recognized native Claude needs neither NVM nor npm.
  local launcher
  launcher="$(type -P "$harness" || true)"
  if [[ "$harness" == claude ]] && claude_native_owns_launcher \
    "$USER_HOME_DIR/.local/share/claude" "$(readlink -f "$launcher" || true)"; then
    return 0
  fi
  load_nvm || true
  launcher="$(type -P "$harness" || true)"
  owner="$(harness_installed_owner "$harness")" || return 1
  if [[ "$owner" == native ]]; then
    ensure_native_pkgs opencode || return $?
  elif [[ -z "$launcher" ]]; then
    command -v npm &>/dev/null || { print_error_message 'npm missing; run setup-node.sh first'; return 1; }
    root="$(readlink -f "$(npm root -g)")" || return 1
    [[ "$root" == "$USER_HOME_DIR/"* ]] || { print_error_message 'npm prefix is not user-owned; retained'; return 1; }
    package="$(harness_npm_package "$harness")" || return 1
    case "$harness" in
      claude|opencode)
        allowed="$(npm config get allow-scripts --location=user)" || return $?
        case "$allowed" in undefined|null) allowed='' ;; esac
        case ",$allowed," in
          *",$package,"*) ;;
          *) npm config set "allow-scripts=${allowed:+$allowed,}$package" --location=user || return $? ;;
        esac ;;

    esac
    if [[ "$harness" == pi ]]; then
      npm install -g --ignore-scripts "$package" || return $?
    else
      npm install -g "$package" || return $?
    fi
  fi
  command -v "$harness" &>/dev/null || { print_error_message "$harness installation failed"; return 1; }
  [[ "$(harness_installed_owner "$harness")" == "$owner" ]] || return 1
}

# Supplied package/launcher facts: never substitute an unrelated ChatGPT wrapper.
chatgpt_update_owner() {
  local distro="$1" installed="$2" launcher="$3" apt_source_valid="$4"
  case "$distro" in arch|ubuntu) ;; *) return 1 ;; esac
  [[ -z "$launcher" || ( "$installed" == true && "$launcher" == /usr/bin/chatgpt ) ]] || return 1
  case "$distro" in
    arch) echo aur ;;
    ubuntu)
      [[ "$installed" == false || "$apt_source_valid" == true ]] || {
        print_error_message 'ChatGPT source conflict: signed OpenAI APT updates are missing; retained' >&2; return 1;
      }
      echo apt ;;
  esac
}

chatgpt_apt_source() {
  cat <<'EOF'
X-Repolib-Name: ChatGPT
Types: deb
URIs: https://persistent.oaistatic.com/codex-app-prod/linux/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/chatgpt-archive-keyring.gpg
EOF
}

# Validate supplied contents, permitting comments and blank lines from the vendor.
chatgpt_apt_source_valid() {
  cmp -s <(printf '%s\n' "$1" | sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d') <(chatgpt_apt_source)
}

ensure_chatgpt_desktop() (
  local package=chatgpt-desktop installed=false source_valid=false launcher owner
  local source=/etc/apt/sources.list.d/chatgpt.sources key=/usr/share/keyrings/chatgpt-archive-keyring.gpg
  local stage existing fingerprint=3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4
  [[ "$WORKSTATION_DISTRO" != ubuntu ]] || package=chatgpt
  native_package_installed "$package" && installed=true
  launcher="$(type -P chatgpt || true)"
  [[ -z "$launcher" || "$launcher" == /usr/bin/chatgpt ]] || {
    print_error_message 'ChatGPT launcher conflict; retained'; return 1;
  }
  # The official Arch package is also retainable, without migrating an AUR install.
  if [[ "$WORKSTATION_DISTRO" == arch ]] && native_package_installed chatgpt; then
    [[ "$launcher" == /usr/bin/chatgpt ]] || return 1
    return 0
  fi
  if [[ -f "$source" && ! -L "$source" ]] && chatgpt_apt_source_valid "$(cat "$source")"; then
    source_valid=true
  fi
  owner="$(chatgpt_update_owner "$WORKSTATION_DISTRO" "$installed" "$launcher" "$source_valid")" || return 1
  if [[ "$owner" == aur ]]; then
    ensure_yay_installed || return $?
    ensure_yay_pkgs chatgpt-desktop || return $?
  else
    stage="$(mktemp -d)" || return 1
    trap 'rm -rf "$stage"' EXIT
    chatgpt_apt_source >"$stage/source"
    while IFS= read -r existing; do
      [[ "$existing" == "$source" ]] || { print_error_message "ChatGPT source conflict: $existing; retained"; return 1; }
    done < <(grep -rl 'persistent\.oaistatic\.com/codex-app-prod/linux/deb' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)
    if [[ -e "$source" || -L "$source" ]]; then
      [[ "$source_valid" == true ]] || { print_error_message "ChatGPT source conflict: $source; retained"; return 1; }
    elif [[ -e /etc/default/chatgpt ]]; then
      print_error_message 'ChatGPT repository preference exists without a source; retained (possible update opt-out)'; return 1
    fi
    ensure_native_pkgs gnupg ca-certificates || return $?
    mkdir -m 700 "$stage/gnupg" || return 1
    local input="$DF_SCRIPT_DIR/keys/chatgpt.asc"
    [[ ! -e "$key" && ! -L "$key" ]] || input="$key"
    [[ ! -L "$input" ]] || { print_error_message 'ChatGPT key symlink conflict'; return 1; }
    gpg --homedir "$stage/gnupg" --batch --show-keys --with-colons "$input" >"$stage/key-info" || return 1
    [[ "$(awk -F: '$1 == "pub" {n++} $1 == "fpr" && !seen++ {f=$10} END {if (n == 1) print f}' "$stage/key-info")" == "$fingerprint" ]] || {
      print_error_message 'ChatGPT signing key mismatch; retained'; return 1;
    }
    if [[ ! -e "$key" ]]; then
      gpg --homedir "$stage/gnupg" --batch --dearmor --output "$stage/key.gpg" "$input" || return 1
      sudo install -d -m 755 /usr/share/keyrings || return 1
      sudo install -m 644 "$stage/key.gpg" "$key" || return 1
    fi
    if [[ ! -e "$source" ]]; then
      sudo install -d -m 755 /etc/apt/sources.list.d || return 1
      sudo install -m 644 "$stage/source" "$source" || return 1
    fi
    ensure_native_pkgs chatgpt || return $?
  fi
  [[ "$(type -P chatgpt || true)" == /usr/bin/chatgpt ]] || { print_error_message 'ChatGPT installation failed'; return 1; }
)
