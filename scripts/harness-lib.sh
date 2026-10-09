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
    [[ "$npm_owned" == false && "$claude_native" == false ]] || return 1
    [[ ( "$harness:$distro:$launcher" == opencode:arch:/usr/bin/opencode ) \
      || ( "$harness:$distro:$launcher" == claude:ubuntu:/usr/bin/claude ) ]] || return 1
    echo native
  elif [[ "$claude_native" == true ]]; then
    [[ "$harness" == claude && "$npm_owned" == false ]] || return 1
    echo claude-native
  elif [[ "$npm_owned" == true || -z "$launcher" ]]; then
    if [[ -z "$launcher" && "$harness:$distro" == opencode:arch ]]; then
      echo native
    elif [[ "$harness:$distro" == claude:ubuntu && -z "$launcher" ]]; then
      echo claude-native
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
  if [[ "$harness:$WORKSTATION_DISTRO" == claude:ubuntu ]] && native_package_installed claude-code; then
    [[ "$launcher" == /usr/bin/claude && ! -e "$USER_HOME_DIR/.local/share/claude" ]] || return 1
    check_claude_apt_owner || return 1
    native=true
  fi
  if [[ "$harness" == claude ]] && claude_native_owns_launcher "$USER_HOME_DIR/.local/share/claude" "$launcher"; then
    # A hidden npm copy remains a second owner even when native wins PATH.
    if command -v npm &>/dev/null; then
      root="$(npm root -g)" || return 1
      [[ ! -e "$root/$package/package.json" ]] || {
        print_error_message 'Claude native/npm source conflict; both retained' >&2; return 1;
      }
    fi
    harness_update_owner "$WORKSTATION_DISTRO" "$harness" "$native" "$launcher" false true
    return $?
  fi
  if command -v npm &>/dev/null; then
    root="$(npm root -g)" || return 1
    root="$(readlink -f "$root")" || return 1
    # Never adopt a root/system prefix, even if its CLI appears on PATH.
    if [[ "$root" == "$USER_HOME_DIR/"* ]]; then
      package_dir="$(readlink -f "$root/$package" || true)"
      [[ "$native" != true || ! -f "$package_dir/package.json" ]] || return 1
      npm_harness_owns_launcher "$package_dir" "$launcher" && npm_owned=true
      [[ -n "$launcher" || ! -f "$package_dir/package.json" ]] || {
        print_error_message "$harness npm package has no selected launcher; retained" >&2; return 1;
      }
    fi
  fi
  harness_update_owner "$WORKSTATION_DISTRO" "$harness" "$native" "$launcher" "$npm_owned" "$claude_native"
}

ensure_harness_cli() {
  local harness="$1" owner package root allowed
  [[ "$EUID" != 0 ]] || { print_error_message 'Run harness setup as the user, without sudo'; return 1; }
  local launcher
  load_nvm || true
  launcher="$(type -P "$harness" || true)"
  owner="$(harness_installed_owner "$harness")" || return 1
  if [[ "$owner" == native ]]; then
    package=opencode
    [[ "$harness" != claude ]] || package=claude-code
    ensure_native_pkgs "$package" || return $?
  elif [[ "$owner" == claude-native && -z "$launcher" ]]; then
    install_claude_native || return $?
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

# Verified initial native acquisition; subsequent releases belong to Claude itself.
claude_release_checksum() {
  core_cli_version_at_least "$1" 2.1.207 || return 1
  local digest
  digest="$(jq -er --arg version "$1" 'select(.version == $version) | .platforms["linux-x64"].checksum' <<<"$2")" || return 1
  [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

install_claude_native() (
  local root="$USER_HOME_DIR/.local/share/claude" launcher="$USER_HOME_DIR/.local/bin/claude"
  local base=https://downloads.claude.ai/claude-code-releases stage version digest
  [[ "$WORKSTATION_DISTRO" == ubuntu && "$EUID" != 0 && ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
  [[ ! -e "$root" && ! -L "$root" && ! -e "$launcher" && ! -L "$launcher" ]] || {
    print_error_message 'Claude native tree/launcher conflict; retained'; return 1;
  }
  core_cli_parent_links_allowed "$root/versions/new" && core_cli_parent_links_allowed "$launcher" || return 1
  # Existing APT ownership, even off PATH, is never silently replaced.
  native_package_installed claude-code && return 1
  ensure_native_pkgs curl ca-certificates gnupg jq || return 1
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  version="$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$base/stable")" || return 1
  core_cli_version_at_least "$version" 2.1.207 || return 1
  stage_work_app_key claude "$stage" '' || return 1
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$base/$version/manifest.json" -o "$stage/manifest.json" || return 1
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$base/$version/manifest.json.sig" -o "$stage/manifest.json.sig" || return 1
  gpg --homedir "$stage/gnupg" --batch --verify "$stage/manifest.json.sig" "$stage/manifest.json" || return 1
  digest="$(claude_release_checksum "$version" "$(cat "$stage/manifest.json")")" || return 1
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$base/$version/linux-x64/claude" -o "$stage/claude" || return 1
  printf '%s  %s\n' "$digest" "$stage/claude" | sha256sum -c - || return 1
  chmod 755 "$stage/claude" || return 1
  # Use the verified vendor binary's documented installer, pinned to this version;
  # never download or execute install.sh and never force a conflicting launcher.
  "$stage/claude" install "$version" || return 1
  claude_native_owns_launcher "$root" "$(readlink -f "$launcher")" || return 1
  printf '%s  %s\n' "$digest" "$root/versions/$version" | sha256sum -c - || return 1
  hash -r
)

# Supplied effective environment/JSON facts. Auto-check opt-out still permits manual updates.
claude_update_policy() {
  local disabled="$1" settings="$2" value
  [[ "$disabled" != 1 ]] || { echo defer; return 0; }
  value="$(jq -er 'if type != "object" then error("settings object required") else .env.DISABLE_UPDATES // "0" end | tostring' <<<"$settings")" || return 1
  if [[ "$value" == 1 ]]; then echo defer; else echo update; fi
}

# Conservatively respect any visible opt-out; Claude enforces server-managed and
# CLI-only policy that cannot be inferred here. Do not rewrite any setting.
claude_updates_allowed() {
  local file policy directory
  policy="$(claude_update_policy "${DISABLE_UPDATES:-}" '{}')" || return 1
  [[ "$policy" != defer ]] || return 2
  local -a files=("$USER_HOME_DIR/.claude/settings.json" /etc/claude-code/managed-settings.json)
  directory="$PWD"
  while [[ "$directory" != / ]]; do
    files+=("$directory/.claude/settings.json" "$directory/.claude/settings.local.json")
    directory="$(dirname "$directory")"
  done
  while IFS= read -r file; do files+=("$file"); done < <(find /etc/claude-code/managed-settings.d -maxdepth 1 -name '*.json' -type f 2>/dev/null)
  for file in "${files[@]}"; do
    [[ ! -e "$file" && ! -L "$file" ]] && continue
    [[ -f "$file" && -r "$file" ]] || return 1
    policy="$(claude_update_policy '' "$(cat "$file")")" || return 1
    [[ "$policy" != defer ]] || return 2
  done
}

# Retain an existing official scoped stable/latest Claude APT owner only.
check_claude_apt_owner() (
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  native_package_installed claude-code || return 0
  local sources key stage
  sources="$(work_app_apt_source claude)" || return 1
  [[ -n "$sources" ]] || { print_error_message 'Claude APT source/update-owner gap; preserved'; return 1; }
  read -r _ key <<<"$sources"
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  stage_work_app_key claude "$stage" "$key" || return 1
  work_app_apt_candidate claude "$(apt-cache policy claude-code)" >/dev/null || return 1
)

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

# Existing desktop package update trust is checked without rerunning installation.
check_chatgpt_apt_owner() (
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  native_package_installed chatgpt || return 0
  local sources key stage
  sources="$(work_app_apt_source chatgpt)" || return 1
  [[ -n "$sources" ]] || { print_error_message 'ChatGPT APT source/update-owner gap; preserved'; return 1; }
  read -r _ key <<<"$sources"
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  stage_work_app_key chatgpt "$stage" "$key" || return 1
  work_app_apt_candidate chatgpt "$(apt-cache policy chatgpt)" >/dev/null || return 1
)
