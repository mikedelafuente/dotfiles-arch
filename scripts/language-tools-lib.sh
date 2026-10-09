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
    ubuntu:php) echo 'php-cli php-curl php-gd php-intl php-mbstring php-xml php-mysql php-sqlite3 php-pgsql composer' ;;
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

# Package identity and workflow floors, rather than pinning distro versions.
language_command_recipe() {
  case "$1" in arch|ubuntu) ;; *) return 1 ;; esac
  case "$2" in
    python3) [[ "$1" == arch ]] && echo 'python 3.10.0' || echo 'python3 3.10.0' ;;
    go) [[ "$1" == arch ]] && echo 'go 1.24.0' || echo 'golang-go 1.24.0' ;;
    gopls) echo 'gopls 0.16.0' ;;
    php) [[ "$1" == arch ]] && echo 'php 8.2.0' || echo 'php-cli 8.2.0' ;;
    composer) echo 'composer 2.0.0' ;;
    ruby) echo 'ruby 3.2.0' ;;
    rustc|cargo) echo 'rustup 1.70.0' ;;
    *) return 1 ;;
  esac
}

language_command_version() {
  local command="$1" output="$2" pattern
  case "$command" in
    python3) pattern='^Python ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    go)
      [[ "$output" =~ ^go\ version\ go([0-9]+)\.([0-9]+)(\.([0-9]+))?\ [a-z0-9]+/[a-z0-9]+$ ]] || return 1
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

language_version_allowed() {
  local recipe _package minimum
  recipe="$(language_command_recipe arch "$1")" || return 1
  read -r _package minimum <<<"$recipe"
  core_cli_version_at_least "$2" "$minimum" || {
    print_error_message "$1 requires $minimum+; update through its selected owner (retained)" >&2
    return 1
  }
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
  language_version_allowed rustc "$4" && language_version_allowed cargo "$5" || return 1
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
  local command="$1" package _minimum recipe expected launcher installed=false version
  recipe="$(language_command_recipe "$WORKSTATION_DISTRO" "$command")" || return 1
  read -r package _minimum <<<"$recipe"
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
    version="$(language_installed_version "$command")" || {
      print_error_message "Cannot read compatible $command version; retained" >&2; return 1;
    }
    language_version_allowed "$command" "$version" || return 1
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
    language_version_allowed "$command" "$version" || return 1
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
      echo user-rustup
    else
      echo conflict; return 0
    fi
    # Rustup's rustc/cargo must be its proxies, not shadowing installations.
    [[ "$rustc_path" -ef "$rustup_path" && "$cargo_path" -ef "$rustup_path" ]] || return 1
  elif [[ "$native" == true && "$rustc_path" == /usr/bin/rustc && "$cargo_path" == /usr/bin/cargo ]]; then
    echo native
  elif [[ "$native" == false && -z "$rustc_path" && -z "$cargo_path" ]]; then
    echo none
  else
    echo conflict
  fi
}

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
