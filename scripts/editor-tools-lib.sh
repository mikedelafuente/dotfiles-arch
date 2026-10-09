#!/usr/bin/env bash
# Explicit editor recipes. Selection consumes facts; installers gather them separately.
editor_tool_recipe() {
  case "$1" in
    nvim) echo 'neovim 0.12.0 neovim/neovim-releases' ;;
    tree-sitter) echo 'tree-sitter-cli 0.26.1 tree-sitter/tree-sitter' ;;
    tmux) echo 'tmux 3.2.0 -' ;;
    lazydocker) echo 'lazydocker 0.20.0 jesseduffield/lazydocker' ;;
    *) return 1 ;;
  esac
}

# Read-only source/update-owner decision. Never migrate an existing source.
editor_tool_selection() {
  local distro="$1" app="$2" owner="$3" installed="$4" candidate="$5"
  local _package minimum repo recipe
  case "$distro" in arch|ubuntu) ;; *) return 1 ;; esac
  recipe="$(editor_tool_recipe "$app")" || return 1
  read -r _package minimum repo <<<"$recipe"
  case "$owner" in
    native)
      core_cli_version_at_least "$installed" "$minimum" || {
        print_error_message "$app requires $minimum+; update the native package or explicitly resolve its source (preserved)" >&2
        return 1
      }
      echo native ;;
    upstream) [[ "$repo" != - ]] || return 1; echo upstream ;;
    none)
      if core_cli_version_at_least "$candidate" "$minimum"; then
        echo native
      elif [[ "$repo" != - ]]; then
        echo upstream
      else
        print_error_message "No compatible native $app candidate ($minimum+ required)" >&2
        return 1
      fi ;;
    *) print_error_message "Source conflict: $app has unknown/conflicting ownership; preserved" >&2; return 1 ;;
  esac
}

# Parse actual stable executable output, not presence or a prerelease version prefix.
editor_tool_version() {
  local app="$1" output="$2" pattern
  case "$app" in
    nvim) pattern='^NVIM v([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    tree-sitter) pattern='^tree-sitter ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    lazydocker) pattern='^Version: ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])' ;;
    tmux)
      [[ "$output" =~ ^tmux\ ([0-9]+)\.([0-9]+)[a-z]?($|[[:space:]]) ]] || return 1
      printf '%s.%s.0\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return 0 ;;
    *) return 1 ;;
  esac
  [[ "$output" =~ $pattern ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

editor_installed_version() {
  local app="$1" binary="$2" output
  if [[ "$app" == tmux ]]; then
    output="$("$binary" -V)" || return 1
  else
    output="$("$binary" --version)" || return 1
  fi
  editor_tool_version "$app" "$output"
}

# Validate supplied GitHub release metadata. Only stable amd64 assets with a digest.
editor_release_asset() {
  local app="$1" metadata="$2" _package minimum repo recipe tag version asset fields url digest
  recipe="$(editor_tool_recipe "$app")" || return 1
  read -r _package minimum repo <<<"$recipe"
  tag="$(jq -er 'select(.prerelease == false and .draft == false) | .tag_name' <<<"$metadata")" || return 1
  [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || return 1
  version="${BASH_REMATCH[1]}"
  core_cli_version_at_least "$version" "$minimum" || return 1
  case "$app" in
    nvim) asset=nvim-linux-x86_64.tar.gz ;;
    tree-sitter) asset=tree-sitter-linux-x64.gz ;;
    lazydocker) asset="lazydocker_${version}_Linux_x86_64.tar.gz" ;;
    *) return 1 ;;
  esac
  fields="$(jq -er --arg name "$asset" '
    [.assets[] | select(.name == $name)] | select(length == 1) | .[0] |
    select(.digest | type == "string") | [.browser_download_url, .digest] | @tsv
  ' <<<"$metadata")" || return 1
  read -r url digest <<<"$fields"
  [[ "$url" == "https://github.com/$repo/releases/download/$tag/$asset" \
    && "$digest" =~ ^sha256:([a-f0-9]{64})$ ]] || return 1
  printf '%s %s %s\n' "$version" "$url" "${BASH_REMATCH[1]}"
}

# Read-only preflight of the managed release tree and command link. No adoption.
editor_upstream_layout_allowed() {
  local app="$1" root="$2" launcher="$3" _package _minimum repo recipe version
  recipe="$(editor_tool_recipe "$app")" || return 1
  read -r _package _minimum repo <<<"$recipe"
  [[ "$repo" != - ]] || return 1
  core_cli_link_allowed "$root/current" "$root/current" || return 1
  if [[ -e "$root" || -L "$root" ]]; then
    [[ -d "$root" && ! -L "$root" && -f "$root/.dfa-source" && ! -L "$root/.dfa-source" \
      && "$(cat "$root/.dfa-source")" == "$repo" && -L "$root/current" ]] || return 1
    version="$(readlink "$root/current")" || return 1
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ \
      && -d "$root/$version" && ! -L "$root/$version" \
      && -d "$root/$version/bin" && ! -L "$root/$version/bin" \
      && -f "$root/$version/bin/$app" && ! -L "$root/$version/bin/$app" ]] || return 1
  fi
  core_cli_link_allowed "$root/current/bin/$app" "$launcher"
}

# Preserve per-file links used by link-dotfiles, identical copies, and user additions.
editor_config_allowed() {
  local source="$1" target="$2" file relative
  if [[ -d "$source" && ! -L "$target" ]]; then
    [[ ! -e "$target" || -d "$target" ]] || return 1
    while IFS= read -r -d '' file; do
      relative="${file#"$source"/}"
      editor_config_allowed "$file" "$target/$relative" || return 1
    done < <(find "$source" -type f -print0)
    return 0
  fi
  core_cli_link_allowed "$source" "$target" \
    || { [[ -f "$source" && -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; }
}

link_editor_config() {
  local source="$1" target="$2" file relative
  editor_config_allowed "$source" "$target" || {
    print_error_message "Editor config conflict: $target; preserved"; return 1;
  }
  if [[ -d "$source" && ! -L "$target" ]]; then
    while IFS= read -r -d '' file; do
      relative="${file#"$source"/}"
      link_editor_config "$file" "$target/$relative" || return 1
    done < <(find "$source" -type f -print0)
  elif [[ ! -e "$target" && ! -L "$target" ]]; then
    link_core_cli_config "$source" "$target" || return 1
  fi
}

# Normalize numeric package candidates, including tmux's letter patch releases.
editor_package_version() {
  local version="${1#*:}" pattern='^([0-9]+)\.([0-9]+)(\.([0-9]+))?[a-z]?([-+].*)?$'
  [[ ! "$version" =~ (dev|nightly|alpha|beta|rc) && "$version" =~ $pattern ]] || return 1
  printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-0}"
}

editor_native_candidate() {
  local package="$1" metadata candidate
  case "$WORKSTATION_DISTRO" in
    arch)
      metadata="$(LC_ALL=C pacman -Si "$package" 2>/dev/null)" || return 1
      candidate="$(sed -n 's/^Version[[:space:]]*:[[:space:]]*//p' <<<"$metadata")" ;;
    ubuntu)
      metadata="$(LC_ALL=C apt-cache policy "$package")" || return 1
      candidate="$(sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' <<<"$metadata")" ;;
    *) return 1 ;;
  esac
  # No candidate is a supplied absence, not an acquisition failure.
  [[ -n "$candidate" && "$candidate" != '(none)' ]] || return 0
  editor_package_version "$candidate"
}

# Gather installed ownership and executable version before source selection.
ensure_editor_tool() {
  local app="$1" package minimum _repo recipe owner=none version='' candidate='' launcher resolved selected
  local root="$USER_HOME_DIR/.local/share/dotfiles-arch/editor-tools/$app"
  recipe="$(editor_tool_recipe "$app")" || return 1
  read -r package minimum _repo <<<"$recipe"
  launcher="$(type -P "$app" || true)"
  resolved="$(readlink -f "${launcher:-/nonexistent}" || true)"
  if [[ -e "$root" || -L "$root" ]]; then
    if native_package_installed "$package" \
      || ! editor_upstream_layout_allowed "$app" "$root" "$USER_HOME_DIR/.local/bin/$app" \
      || [[ "$resolved" != "$(readlink -f "$root/current/bin/$app")" ]]; then
      owner=unknown
    else
      owner=upstream
    fi
  elif native_package_installed "$package"; then
    owner=native
    [[ "$resolved" == "$(readlink -f "/usr/bin/$app")" ]] || owner=unknown
    if [[ -e "$USER_HOME_DIR/.local/bin/$app" || -L "$USER_HOME_DIR/.local/bin/$app" ]]; then
      [[ "$(readlink -f "$USER_HOME_DIR/.local/bin/$app")" == "$resolved" ]] || owner=unknown
    fi
  elif [[ -n "$launcher" || -e "/usr/bin/$app" || -L "/usr/bin/$app" \
    || -e "$USER_HOME_DIR/.local/bin/$app" || -L "$USER_HOME_DIR/.local/bin/$app" ]]; then
    owner=unknown
  fi
  if [[ "$owner" == native || "$owner" == upstream ]]; then
    version="$(editor_installed_version "$app" "$resolved")" || {
      print_error_message "Cannot verify stable $app version; existing installation preserved"; return 1;
    }
  elif [[ "$owner" == none ]]; then
    candidate="$(editor_native_candidate "$package")" || {
      print_error_message "Cannot read native $package candidate; refresh native package metadata first"; return 1;
    }
  fi
  selected="$(editor_tool_selection "$WORKSTATION_DISTRO" "$app" "$owner" "$version" "$candidate")" || return 1
  if [[ "$selected" == upstream ]]; then
    install_editor_release "$app" || return 1
  else
    ensure_native_pkgs "$package" || return 1
    native_package_installed "$package" || return 1
    hash -r
    launcher="$(type -P "$app" || true)"
    [[ -n "$launcher" && "$(readlink -f "$launcher")" == "$(readlink -f "/usr/bin/$app")" ]] || return 1
    version="$(editor_installed_version "$app" "$launcher")" || return 1
    core_cli_version_at_least "$version" "$minimum" || {
      print_error_message "$app requires $minimum+ after native installation"; return 1;
    }
  fi
}

# Stage and validate a full release before switching the command/runtime together.
install_editor_release() (
  local app="$1" _package _minimum repo recipe metadata release version url digest stage current
  local base="$USER_HOME_DIR/.local/share/dotfiles-arch/editor-tools"
  local root="$base/$app" launcher="$USER_HOME_DIR/.local/bin/$app"
  [[ ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || {
    print_error_message "Add $USER_HOME_DIR/.local/bin to PATH before upstream editor setup"; return 1;
  }
  editor_upstream_layout_allowed "$app" "$root" "$launcher" || {
    print_error_message "Upstream $app ownership/link conflict; preserved"; return 1;
  }
  recipe="$(editor_tool_recipe "$app")" || return 1
  read -r _package _minimum repo <<<"$recipe"
  metadata="$(curl --proto '=https' --tlsv1.2 -fsSL "https://api.github.com/repos/$repo/releases/latest")" || return 1
  release="$(editor_release_asset "$app" "$metadata")" || {
    print_error_message "No verified compatible stable $app release; preserved"; return 1;
  }
  read -r version url digest <<<"$release"
  if [[ -d "$root" ]]; then
    current="$(editor_installed_version "$app" "$root/current/bin/$app")" || return 1
    if core_cli_version_at_least "$current" "$version"; then
      return 0
    fi
    [[ ! -e "$root/$version" && ! -L "$root/$version" ]] || {
      print_error_message "Release directory conflict: $root/$version; preserved"; return 1;
    }
  fi
  mkdir -p "$base" || return 1
  stage="$(mktemp -d "$base/.${app}.XXXXXX")" || return 1
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$stage/artifact" || return 1
  printf '%s  %s\n' "$digest" "$stage/artifact" | sha256sum -c - || return 1
  mkdir -p "$stage/install/$version/bin" || return 1
  # Python's data filter rejects archive traversal and escaping links. Extract only
  # the named Neovim runtime tree, or the one regular lazydocker binary.
  python3 - "$app" "$stage/artifact" "$stage/install/$version" <<'PY' || return 1
import gzip
from pathlib import Path
import shutil
import sys
import tarfile

app, artifact, destination = sys.argv[1:]
dest = Path(destination)
if app == "tree-sitter":
    with gzip.open(artifact, "rb") as source, (dest / "bin/tree-sitter").open("wb") as out:
        shutil.copyfileobj(source, out)
else:
    with tarfile.open(artifact, "r:gz") as archive:
        if app == "nvim":
            members = archive.getmembers()
            if any(m.name.split("/")[0] != "nvim-linux-x86_64" for m in members):
                raise ValueError("Unexpected Neovim archive layout")
            archive.extractall(dest / "unpacked", members=members, filter="data")
            tree = dest / "unpacked/nvim-linux-x86_64"
            (dest / "bin").rmdir()
            for path in tree.iterdir():
                path.rename(dest / path.name)
            tree.rmdir()
            (dest / "unpacked").rmdir()
        elif app == "lazydocker":
            member = archive.getmember("lazydocker")
            if not member.isfile():
                raise ValueError("Expected regular lazydocker binary")
            with archive.extractfile(member) as source, (dest / "bin/lazydocker").open("wb") as out:
                shutil.copyfileobj(source, out)
        else:
            raise ValueError("Unknown tool")
PY
  chmod 755 "$stage/install/$version/bin/$app" || return 1
  current="$(editor_installed_version "$app" "$stage/install/$version/bin/$app")" || return 1
  [[ "$current" == "$version" ]] || return 1
  printf '%s\n' "$repo" >"$stage/install/.dfa-source" || return 1
  ln -s "$version" "$stage/install/current" || return 1
  editor_upstream_layout_allowed "$app" "$root" "$launcher" || return 1
  if [[ -d "$root" ]]; then
    mv -T "$stage/install/$version" "$root/$version" || return 1
    mv -T "$stage/install/current" "$root/current" || return 1
  else
    mv -T "$stage/install" "$root" || return 1
  fi
  link_core_cli_config "$root/current/bin/$app" "$launcher" || return 1
  hash -r
  current="$(type -P "$app" || true)"
  [[ -n "$current" && "$(readlink -f "$current")" == "$(readlink -f "$root/current/bin/$app")" ]] || {
    print_error_message "$app requires USER_HOME_DIR/.local/bin on PATH; resolve the launcher before continuing"; return 1;
  }
  print_info_message "$app $version; update owner: dfa-update-system upstream refresh"
)

# Called inside the common updater before any successful-update stamp.
refresh_editor_tools() {
  local app root failed=0
  for app in nvim tree-sitter lazydocker; do
    root="$USER_HOME_DIR/.local/share/dotfiles-arch/editor-tools/$app"
    [[ -e "$root" || -L "$root" ]] || continue
    ensure_editor_tool "$app" || failed=1
  done
  return "$failed"
}
