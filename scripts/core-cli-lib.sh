#!/usr/bin/env bash
# Explicit recipes for the shared shell/CLI slice. No arbitrary name translation.
# Read-only result: package, executable, source/update owner, minimum version.
core_cli_recipe() {
  local distro="$1" app="$2" package command minimum=0.0.0 owner=native
  case "$distro" in arch|ubuntu) ;; *) return 1 ;; esac
  case "$app" in
    git) package=git; command=git; minimum=2.35.0 ;;
    git-delta) package=git-delta; command="delta"; minimum=0.16.0 ;;
    curl|wget|xsel|htop|ncdu|tree|jq|iw|btop|duf|stow|shellcheck|fastfetch|zoxide|coreutils|less|gnupg|bash-completion)
      package="$app"; command="$app"
      case "$app" in
        coreutils) command=sha256sum ;; gnupg) command=gpg ;;
        bash-completion) command=- ;;
      esac ;;
    bash) package=bash; command=bash; minimum=4.0.0 ;;
    openssh) package=openssh; command=ssh; [[ "$distro" != ubuntu ]] || package=openssh-client ;;
    util-linux) package=util-linux; command=col; [[ "$distro" != ubuntu ]] || package=bsdextrautils ;;
    wl-clipboard) package=wl-clipboard; command=wl-copy ;;
    net-tools) package=net-tools; command=netstat ;;
    eza) package=eza; command=eza; minimum=0.18.0 ;;
    starship) package=starship; command=starship; minimum=1.22.0 ;;
    fzf) package=fzf; command=fzf; minimum=0.48.0 ;;
    ripgrep) package=ripgrep; command=rg; minimum=13.0.0 ;;
    fd) package=fd; command=fd; minimum=8.0.0
      [[ "$distro" != ubuntu ]] || { package=fd-find; command=fdfind; } ;;
    bat) package=bat; command=bat; minimum=0.23.0
      [[ "$distro" != ubuntu ]] || command=batcat ;;
    glow) package=glow; command=glow; minimum=1.0.0
      [[ "$distro" != ubuntu ]] || owner=charm ;;
    github-cli) package=github-cli; command=gh; minimum=2.0.0
      [[ "$distro" != ubuntu ]] || package=gh ;;
    tldr) package=tldr; command=tldr
      [[ "$distro" != ubuntu ]] || package=tealdeer ;;
    lazygit) package=lazygit; command=lazygit; minimum=0.40.0 ;;
    *) print_error_message "No core CLI recipe for $app" >&2; return 1 ;;
  esac
  printf '%s %s %s %s\n' "$package" "$command" "$owner" "$minimum"
}

# Only numeric release components supplied by the caller; never eval version text.
core_cli_version_at_least() {
  local version="$1" minimum="$2" i
  local -a actual required
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$minimum" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a actual <<<"$version"
  IFS=. read -r -a required <<<"$minimum"
  for i in 0 1 2; do
    [[ ${#actual[i]} -lt 10 && ${#required[i]} -lt 10 ]] || return 1
    ((10#${actual[i]} >= 10#${required[i]})) || return 1
    ((10#${actual[i]} == 10#${required[i]})) || return 0
  done
}

# Supplied resolved launcher/package facts. Missing is installable; shadowing is not.
core_cli_source_allowed() {
  local installed="$1" launcher="$2" expected="$3"
  [[ -z "$launcher" || ( "$installed" == true && "$launcher" == "$expected" ) ]]
}

# Read-only link decision: absent or the same resolved target. Never adopt user files.
core_cli_parent_links_allowed() {
  local parent
  parent="$(dirname "$1")"
  while [[ "$parent" != / ]]; do
    # Refuse writes through user directory links or non-directory ancestors.
    [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || return 1
    parent="$(dirname "$parent")"
  done
}

core_cli_link_allowed() {
  core_cli_parent_links_allowed "$2" || return 1
  [[ ! -e "$2" && ! -L "$2" ]] \
    || { [[ -L "$2" ]] && [[ "$(readlink -f "$1")" == "$(readlink -f "$2")" ]]; }
}

link_core_cli_config() {
  local source="$1" target="$2"
  core_cli_link_allowed "$source" "$target" || {
    print_error_message "Config conflict: $target; preserved"; return 1;
  }
  mkdir -p "$(dirname "$target")" || return $?
  [[ -L "$target" ]] || ln -s "$source" "$target"
}

# Install one explicit native recipe; preflight launchers and version before mutation.
ensure_core_cli() {
  local app="$1" package command owner minimum launcher expected installed=false version
  local recipe
  recipe="$(core_cli_recipe "$WORKSTATION_DISTRO" "$app")" || return 1
  read -r package command owner minimum <<<"$recipe"
  native_package_installed "$package" && installed=true
  if [[ "$command" != - ]]; then
    expected="$(readlink -m "/usr/bin/$command")"
    launcher="$(type -P "$command" || true)"
    [[ -z "$launcher" ]] || launcher="$(readlink -f "$launcher")"
    if ! core_cli_source_allowed "$installed" "$launcher" "$expected" \
      || { [[ "$installed" == false ]] && [[ -e "$expected" || -L "$expected" ]]; }; then
      print_error_message "Source conflict: $app is not selected from $package ($owner); preserved"
      return 1
    fi
    # Do not install an Ubuntu compatibility link over any existing fd/bat command.
    if [[ "$command" == fdfind || "$command" == batcat ]]; then
      launcher="$(type -P "$app" || true)"
      [[ -z "$launcher" ]] || launcher="$(readlink -f "$launcher")"
      if ! core_cli_source_allowed "$installed" "$launcher" "$expected" \
        || ! core_cli_link_allowed "$expected" "$USER_HOME_DIR/.local/bin/$app"; then
        print_error_message "Command conflict: $app; preserved"; return 1
      fi
    fi
    if [[ "$installed" == true && "$minimum" != 0.0.0 ]]; then
      version="$("$expected" --version)" || return 1
      if [[ ! "$version" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] \
        || ! core_cli_version_at_least "${BASH_REMATCH[1]}" "$minimum"; then
        print_error_message "$app requires $minimum+; update through $owner packages (existing installation retained)"
        return 1
      fi
    fi
  fi
  [[ "$owner" != charm ]] || ensure_charm_source || return 1
  ensure_native_pkgs "$package" || return $?
  [[ "$command" != - ]] || return 0
  [[ -x "$expected" ]] || { print_error_message "Missing $package command: $expected"; return 1; }
  if [[ "$minimum" != 0.0.0 ]]; then
    version="$("$expected" --version)" || return 1
    if [[ ! "$version" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] \
      || ! core_cli_version_at_least "${BASH_REMATCH[1]}" "$minimum"; then
      print_error_message "$app requires $minimum+; update owner: $owner packages"; return 1
    fi
  fi
  if [[ "$command" == fdfind || "$command" == batcat ]]; then
    link_core_cli_config "$expected" "$USER_HOME_DIR/.local/bin/$app" || return 1
    export PATH="$USER_HOME_DIR/.local/bin:$PATH"
    hash -r
  fi
}

# Charm's official APT recipe. Stage and verify the key before privileged writes.
ensure_charm_source() (
  local source=/etc/apt/sources.list.d/dfa-charm.list key=/etc/apt/keyrings/dfa-charm.gpg
  local fingerprint=ED927B38BE981E53CA09153D03BBF595D4DFD35C stage existing
  local line="deb [arch=amd64 signed-by=$key] https://repo.charm.sh/apt/ * *"
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  printf '%s\n' "$line" >"$stage/source"
  # Recognize the upstream recipe as another compatible, known APT owner.
  # Preserve it verbatim; unknown or duplicate registrations require resolution.
  while IFS= read -r existing; do
    if [[ "$existing" == /etc/apt/sources.list.d/charm.list && ! -e "$source" ]]; then
      source="$existing"
      key=/etc/apt/keyrings/charm.gpg
      printf 'deb [signed-by=%s] https://repo.charm.sh/apt/ * *\n' "$key" >"$stage/source"
    elif [[ "$existing" != "$source" ]]; then
      print_error_message "Charm source conflict: $existing; preserved"; return 1
    fi
  done < <(grep -rl 'repo\.charm\.sh' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)
  if [[ -e "$source" || -L "$source" ]]; then
    if [[ -L "$source" ]] || ! cmp -s "$source" "$stage/source"; then
      print_error_message "Charm source conflict: $source; preserved"; return 1
    fi
  fi
  ensure_native_pkgs curl ca-certificates gnupg || return $?
  mkdir -m 700 "$stage/gnupg" || return 1
  if [[ -e "$key" || -L "$key" ]]; then
    [[ ! -L "$key" ]] || { print_error_message "Charm key symlink conflict: $key"; return 1; }
    gpg --homedir "$stage/gnupg" --batch --show-keys --with-colons "$key" >"$stage/key-info" || return 1
  else
    curl --proto '=https' --tlsv1.2 -fsSL https://repo.charm.sh/apt/gpg.key -o "$stage/key.asc" || return 1
    gpg --homedir "$stage/gnupg" --batch --show-keys --with-colons "$stage/key.asc" >"$stage/key-info" || return 1
  fi
  [[ "$(awk -F: '$1 == "pub" {n++} $1 == "fpr" && !seen++ {f=$10} END {if (n == 1) print f}' "$stage/key-info")" == "$fingerprint" ]] || {
    print_error_message "Charm signing key fingerprint mismatch; source unchanged"; return 1;
  }
  if [[ ! -e "$key" ]]; then
    gpg --homedir "$stage/gnupg" --batch --dearmor --output "$stage/key.gpg" "$stage/key.asc" || return 1
    sudo install -d -m 755 /etc/apt/keyrings || return 1
    sudo install -m 644 "$stage/key.gpg" "$key" || return 1
  fi
  [[ -e "$source" ]] || sudo install -m 644 "$stage/source" "$source" || return 1
)
