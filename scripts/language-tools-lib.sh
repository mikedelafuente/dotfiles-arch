#!/usr/bin/env bash
# Language recipes use native packages; user toolchains keep their own updater.
# Pure package selection, including headers that Ubuntu splits into -dev packages.
language_packages() {
  case "$1:$2" in
    arch:build) echo 'base-devel openssl zlib libffi libyaml pkgconf sqlite' ;;
    ubuntu:build) echo 'build-essential libssl-dev zlib1g-dev libffi-dev libyaml-dev pkg-config sqlite3 libsqlite3-dev' ;;
    arch:python) echo 'python python-pip python-pynvim' ;;
    ubuntu:python) echo 'python3 python3-pip python3-venv python3-pynvim python3-dev' ;;
    arch:go) echo 'go gopls' ;;
    ubuntu:go) echo 'golang-go gopls' ;;
    arch:rust|ubuntu:rust) echo rustup ;;
    arch:php) echo 'php php-gd php-intl php-sqlite php-pgsql composer' ;;
    ubuntu:php) echo 'php-cli php-curl php-gd php-intl php-mbstring php-xml php-mysql php-sqlite3 php-pgsql' ;;
    arch:ruby) echo 'ruby sqlite base-devel' ;;
    ubuntu:ruby) echo 'ruby ruby-dev sqlite3 libsqlite3-dev build-essential libyaml-dev' ;;
    *) return 1 ;;
  esac
}

ensure_language_packages() {
  local selection
  local -a packages
  selection="$(language_packages "$WORKSTATION_DISTRO" "$1")" || return 1
  read -r -a packages <<<"$selection"
  ensure_native_pkgs "${packages[@]}"
}

# Unversioned package names select the latest available from the native source.
language_command_package() {
  case "$1" in arch|ubuntu) ;; *) return 1 ;; esac
  case "$2" in
    python3) [[ "$1" == arch ]] && echo python || echo python3 ;;
    go) [[ "$1" == arch ]] && echo go || echo golang-go ;;
    gopls|composer|ruby) echo "$2" ;;
    php) [[ "$1" == arch ]] && echo php || echo php-cli ;;
    *) return 1 ;;
  esac
}

language_command_version() {
  local command="$1" output="$2" pattern
  case "$command" in
    python3) pattern='^Python ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    go)
      [[ "$output" =~ ^go\ version\ go([0-9]+)\.([0-9]+)(\.([0-9]+))?(-X:[a-zA-Z0-9_,]+)?\ [a-z0-9]+/[a-z0-9]+$ ]] || return 1
      printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-0}"
      return 0 ;;
    gopls) pattern='^golang.org/x/tools/gopls v([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    php) pattern='^PHP ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    composer) pattern='^Composer version ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    ruby) pattern='^ruby ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    rustc|cargo) pattern="^$command ([0-9]+\\.[0-9]+\\.[0-9]+)(-(nightly|beta)(\\.[0-9]+)?)?(\$|[[:space:]])" ;;
    *) return 1 ;;
  esac
  [[ "$output" =~ $pattern ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# Supplied ownership/default/version facts. Only a missing default is initialized.
rust_toolchain_selection() {
  case "$1" in arch|ubuntu) ;; *) return 1 ;; esac
  case "$2" in
    none) echo initialize; return 0 ;;
    native-rustup|user-rustup)
      [[ -n "$3" ]] || { echo initialize; return 0; } ;;
    native) ;;
    *) print_error_message 'Rust source conflict; existing toolchain retained' >&2; return 1 ;;
  esac
  [[ "$4" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$5" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  echo retain
}

php_configuration_paths() {
  local version="$2"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  case "$1" in
    arch) echo '/etc/php/php.ini /etc/php/conf.d' ;;
    ubuntu) printf '/etc/php/%s/cli/php.ini /etc/php/%s/cli/conf.d\n' "${version%.*}" "${version%.*}" ;;
    *) return 1 ;;
  esac
}

language_installed_version() {
  local command="$1" output
  case "$command" in
    go|gopls) output="$("$command" version)" || return 1 ;;
    *) output="$("$command" --version)" || return 1 ;;
  esac
  language_command_version "$command" "$output"
}

# Preflight all commands before installing any prerequisite or changing config.
# Real paths account for Ubuntu's versioned executables and alternatives.
language_native_preflight() {
  local command="$1" package expected launcher installed=false
  package="$(language_command_package "$WORKSTATION_DISTRO" "$command")" || return 1
  native_package_installed "$package" && installed=true
  expected="$(readlink -m "/usr/bin/$command")" || return 1
  launcher="$(type -P "$command" || true)"
  [[ -z "$launcher" ]] || launcher="$(readlink -f "$launcher")" || return 1
  if ! core_cli_source_allowed "$installed" "$launcher" "$expected" \
    || { [[ "$installed" == false ]] && [[ -e "$expected" || -L "$expected" ]]; }; then
    print_error_message "Source conflict: $command must be owned by $package; existing source retained" >&2
    return 1
  fi
  if [[ -n "$launcher" ]] && ! language_native_file_owned "$launcher"; then
    print_error_message "Source conflict: $command resolves outside native package ownership; retained" >&2
    return 1
  fi
  if [[ -n "$launcher" ]]; then
    language_installed_version "$command" >/dev/null || {
      print_error_message "Cannot read $command version; retained" >&2; return 1;
    }
  fi
}

ensure_language_runtime() {
  local app="$1" command version
  shift
  [[ "$EUID" != 0 ]] || { print_error_message 'Run language setup as the user, without sudo'; return 1; }
  for command in "$@"; do language_native_preflight "$command" || return 1; done
  ensure_language_packages build || return $?
  ensure_language_packages "$app" || return $?
  hash -r
  for command in "$@"; do
    language_native_preflight "$command" || return 1
    version="$(language_installed_version "$command")" || return 1
    print_info_message "$command $version; native updates: dfa-update-system"
  done
}

# Gather Rust ownership separately from the supplied-fact decision above.
language_rust_owner() {
  local rustup_path rustc_path cargo_path native=false package
  rustup_path="$(type -P rustup || true)"
  rustc_path="$(type -P rustc || true)"
  cargo_path="$(type -P cargo || true)"
  for package in rust rustc cargo; do
    native_package_installed "$package" && native=true
  done
  if [[ -n "$rustup_path" ]]; then
    rustup_path="$(readlink -f "$rustup_path")" || return 1
    [[ "$native" == false ]] || { echo conflict; return 0; }
    if [[ "$rustup_path" == /usr/bin/rustup ]] && native_package_installed rustup; then
      echo native-rustup
    elif [[ "$rustup_path" == "${CARGO_HOME:-$USER_HOME_DIR/.cargo}/bin/rustup" && -O "$rustup_path" ]]; then
      native_package_installed rustup && { echo conflict; return 0; }
      echo user-rustup
    else
      echo conflict; return 0
    fi
    # Rustup's rustc/cargo must be its proxies, not shadowing installations.
    [[ "$rustc_path" -ef "$rustup_path" && "$cargo_path" -ef "$rustup_path" ]] || return 1
  elif [[ "$native" == true && "$rustc_path" == /usr/bin/rustc && "$cargo_path" == /usr/bin/cargo ]]; then
    echo native
  elif [[ "$native" == false && -z "$rustc_path" && -z "$cargo_path" ]]; then
    native_package_installed rustup && { echo conflict; return 0; }
    echo none
  else
    echo conflict
  fi
}

# Prefer the genuine user updater only for a missing Ubuntu manager.
rust_manager_selection() {
  case "$1:$2" in
    ubuntu:none) echo user-rustup ;;
    arch:none) echo native-rustup ;;
    arch:native-rustup|ubuntu:native-rustup|arch:user-rustup|ubuntu:user-rustup|arch:native|ubuntu:native) echo "$2" ;;
    *) return 1 ;;
  esac
}

install_user_rustup() (
  local stage checksum url=https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init
  [[ "$WORKSTATION_DISTRO" == ubuntu && "$EUID" != 0 ]] || return 1
  language_user_path_allowed "$USER_HOME_DIR" "$CARGO_HOME" && language_user_path_allowed "$USER_HOME_DIR" "$RUSTUP_HOME" || return 1
  [[ ! -e "$CARGO_HOME/bin/rustup" && ! -L "$CARGO_HOME/bin/rustup" ]] || return 1
  ensure_native_pkgs curl ca-certificates || return 1
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  checksum="$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$url.sha256")" || return 1
  [[ "$checksum" =~ ^([a-f0-9]{64})[[:space:]]+\*?(\./)?rustup-init[[:space:]]*$ ]] || return 1
  checksum="${BASH_REMATCH[1]}"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$url" -o "$stage/rustup-init" || return 1
  printf '%s  %s\n' "$checksum" "$stage/rustup-init" | sha256sum -c - || return 1
  chmod 755 "$stage/rustup-init" || return 1
  "$stage/rustup-init" -y --no-modify-path --default-toolchain none --profile minimal || return 1
)

# Only CLI configuration is touched; never enable/change an Ubuntu web SAPI.
php_modules_allowed() {
  local modules="${1,,}" extension
  for extension in ctype curl dom fileinfo filter hash mbstring openssl pcre pdo session tokenizer xml \
    iconv mysqli pdo_mysql pdo_sqlite sqlite3 gd intl pgsql pdo_pgsql; do
    grep -Fxq "$extension" <<<"$modules" || {
      print_error_message "PHP requires extension $extension; check the selected CLI configuration" >&2
      return 1
    }
  done
}

# Supplied user paths; reject escapes, directory links, and root-owned state.
language_user_path_allowed() {
  local home="$1" path="$2" parent
  [[ "$path" == "$home/"* && "$(readlink -m "$path")" == "$path" ]] || {
    print_error_message "User tooling path conflict: $path; retained" >&2; return 1;
  }
  parent="$path"
  while [[ "$parent" != "$home" ]]; do
    [[ ! -L "$parent" && ( ! -e "$parent" || ( -d "$parent" && -O "$parent" ) ) ]] || {
      print_error_message "User tooling path is linked or not user-owned: $parent; retained" >&2; return 1;
    }
    parent="$(dirname "$parent")"
  done
}

# Supplied launcher/package facts for Bundler/Rails and Composer user commands.
language_user_tool_selection() {
  local expected="$1" launcher="$2" native="$3"
  if [[ "$native" == true && "$launcher" == /usr/bin/* ]]; then
    echo native
  elif [[ -z "$launcher" || "$launcher" == "$expected" ]]; then
    echo user
  else
    print_error_message "User tool source conflict: $launcher; retained" >&2; return 1
  fi
}

language_native_file_owned() {
  local binary="$1" package
  [[ "$binary" == /usr/bin/* || "$binary" == /usr/lib/* ]] || return 1
  case "$WORKSTATION_DISTRO" in
    arch) package="$(pacman -Qoq "$binary")" || return 1 ;;
    ubuntu)
      package="$(dpkg-query -S "$binary")" || return 1
      package="${package%%: /*}" ;;
    *) return 1 ;;
  esac
  native_package_installed "$package"
}

# Supplied temporary filesystem state: missing is installable, links are conflicts.
language_user_launcher_allowed() {
  [[ ! -e "$1" && ! -L "$1" ]] || [[ -f "$1" && ! -L "$1" && -O "$1" ]]
}

ensure_user_gem() {
  local gem_name="$1" user_dir="$2" command launcher owner native=false
  language_user_path_allowed "$USER_HOME_DIR" "$user_dir/bin" || return 1
  command="$gem_name"
  [[ "$gem_name" != bundler ]] || command=bundle
  language_user_launcher_allowed "$user_dir/bin/$command" || {
    print_error_message "Gem launcher ownership conflict: $command; retained" >&2; return 1;
  }
  launcher="$(type -P "$command" || true)"
  language_native_file_owned "$launcher" && native=true
  owner="$(language_user_tool_selection "$user_dir/bin/$command" "$launcher" "$native")" || return 1
  if [[ "$owner" == user ]]; then
    if [[ ! -x "$user_dir/bin/$command" ]] \
      || ! GEM_HOME="$user_dir" GEM_PATH="$user_dir" gem list --local -i "^$gem_name$" >/dev/null; then
      gem install --user-install --bindir "$user_dir/bin" "$gem_name" --no-document || return $?
    fi
  fi
  "$command" --version || { print_error_message "$command installed but unusable"; return 1; }
  if [[ "$owner" == user ]]; then
    print_info_message "$command updates: gem update --user-install $gem_name --no-document"
  else
    print_info_message "$command updates: dfa-update-system"
  fi
}

# Supplied owner facts; a distro-managed Composer never self-updates its PHAR.
composer_source_selection() {
  local distro="$1" native="$2" launcher="$3" self_owned="$4"
  case "$distro" in arch|ubuntu) ;; *) return 1 ;; esac
  if [[ "$native" == true ]]; then
    [[ "$launcher" == /usr/bin/composer && "$self_owned" == false ]] || return 1
    echo native
  elif [[ "$self_owned" == true ]]; then
    [[ "$distro" == ubuntu && "$launcher" == self ]] || return 1
    echo self
  elif [[ -z "$launcher" ]]; then
    [[ "$distro" == ubuntu ]] && echo self || echo native
  else return 1; fi
}

composer_installed_owner() {
  local root="$USER_HOME_DIR/.local/share/dotfiles-arch/composer" path native=false owned=false
  path="$(type -P composer || true)"
  [[ -z "$path" ]] || path="$(readlink -f "$path")" || return 1
  native_package_installed composer && native=true
  if [[ -e "$root" || -L "$root" ]]; then
    core_cli_parent_links_allowed "$root/composer.phar" || return 1
    [[ -d "$root" && ! -L "$root" && -f "$root/.dfa-source" && ! -L "$root/.dfa-source" \
      && "$(cat "$root/.dfa-source")" == composer-self && -f "$root/composer.phar" \
      && ! -L "$root/composer.phar" && -O "$root/composer.phar" && -w "$root/composer.phar" ]] || return 1
    [[ "$path" == "$root/composer.phar" ]] || return 1
    owned=true; path=self
  fi
  composer_source_selection "$WORKSTATION_DISTRO" "$native" "$path" "$owned"
}

ensure_composer_cli() (
  local owner="$1" root="$USER_HOME_DIR/.local/share/dotfiles-arch/composer" stage digest
  if [[ "$owner" == native ]]; then
    ensure_native_pkgs composer || return 1
    language_native_preflight composer || return 1
    return 0
  fi
  [[ "$owner" == self && "$WORKSTATION_DISTRO" == ubuntu && "$EUID" != 0 ]] || return 1
  local setting
  for setting in "${COMPOSER_HOME:-${XDG_CONFIG_HOME:-$USER_HOME_DIR/.config}/composer}" "$USER_HOME_DIR/.composer" "${XDG_CACHE_HOME:-$USER_HOME_DIR/.cache}/composer"; do
    language_user_path_allowed "$USER_HOME_DIR" "$setting" || return 1
  done
  if [[ ! -e "$root" && ! -L "$root" ]]; then
    core_cli_parent_links_allowed "$root/composer.phar" \
      && core_cli_link_allowed "$root/composer.phar" "$USER_HOME_DIR/.local/bin/composer" || return 1
    [[ ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
    ensure_native_pkgs curl ca-certificates || return 1
    stage="$(mktemp -d)" || return 1
    trap 'rm -rf "$stage"' EXIT
    digest="$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL https://composer.github.io/installer.sig)" || return 1
    [[ "$digest" =~ ^[a-f0-9]{96}$ ]] || return 1
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL https://getcomposer.org/installer -o "$stage/setup.php" || return 1
    printf '%s  %s\n' "$digest" "$stage/setup.php" | sha384sum -c - || return 1
    mkdir "$stage/install" || return 1
    # Verified PHP installer verifies the stable PHAR and installs updater keys;
    # it does not replace the distro package or change shell startup files.
    php "$stage/setup.php" --install-dir="$stage/install" --filename=composer.phar || return 1
    chmod 755 "$stage/install/composer.phar" || return 1
    printf '%s\n' composer-self >"$stage/install/.dfa-source" || return 1
    mkdir -p "$(dirname "$root")" || return 1
    mv -T "$stage/install" "$root" || return 1
    link_core_cli_config "$root/composer.phar" "$USER_HOME_DIR/.local/bin/composer" || return 1
  fi
  language_installed_version composer >/dev/null || return 1
  [[ "$(composer_installed_owner)" == self ]] || return 1
  print_info_message 'Composer PHAR self-update owner: composer self-update (manual); existing channel/settings retained'
)
