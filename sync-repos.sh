#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="${ROOT_DIR}/repos"

# Spec format:
#   name|repo_url|mapped_repo_dir|copy_mode|source_dirs|exclude_dirs
#
# copy_mode:
#   selected    Copy comma-separated directories from source_dirs to ROOT_DIR.
#               Nested directories are supported, for example abc/def copies def.
#   all_subdirs Copy every immediate child directory from the cloned repo to ROOT_DIR.
#               exclude_dirs is only used by this mode.
#
# exclude_dirs:
#   Comma-separated directory basenames or relative paths. .git is always excluded.
REPO_SPECS=(
  "openclash|https://github.com/vernesong/OpenClash.git|openclash|selected|luci-app-openclash|"
  "passwall|https://github.com/xiaorouji/openwrt-passwall-packages.git|passwall|all_subdirs||.github"
  "cupsd|https://github.com/gdck/luci-app-cupsd.git|cupsd|all_subdirs||"
)

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

validate_relative_path() {
  local path="$1"
  local part

  [[ -n "$path" ]] || die "empty relative path"
  [[ "$path" != /* ]] || die "absolute paths are not allowed: $path"

  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || die "empty path segment is not allowed: $path"
    [[ "$part" != "." && "$part" != ".." ]] || die "unsafe path segment in: $path"
  done
}

ensure_repo() {
  local name="$1"
  local url="$2"
  local repo_dir="$3"
  local current_branch
  local default_branch
  local branch

  mkdir -p "$REPOS_DIR"

  if [[ -d "$repo_dir/.git" ]]; then
    log "Updating $name in ${repo_dir#$ROOT_DIR/}"
    git -C "$repo_dir" fetch --prune origin

    current_branch="$(git -C "$repo_dir" symbolic-ref --short -q HEAD || true)"
    default_branch="$(git -C "$repo_dir" remote show origin | sed -n 's/.*HEAD branch: //p')"
    branch="${current_branch:-$default_branch}"

    if [[ -n "$branch" ]]; then
      git -C "$repo_dir" checkout "$branch"
      git -C "$repo_dir" pull --ff-only origin "$branch"
    else
      git -C "$repo_dir" pull --ff-only
    fi
    return
  fi

  if [[ -e "$repo_dir" ]]; then
    die "$repo_dir exists but is not a git repository"
  fi

  log "Cloning $name into ${repo_dir#$ROOT_DIR/}"
  git clone "$url" "$repo_dir"
}

copy_dir_to_root() {
  local src_dir="$1"
  local dest_name="$2"
  local dest_dir="$ROOT_DIR/$dest_name"

  validate_relative_path "$dest_name"
  [[ -d "$src_dir" ]] || die "source directory not found: $src_dir"
  [[ "$dest_dir" == "$ROOT_DIR/"* ]] || die "unsafe destination: $dest_dir"

  log "Copying ${src_dir#$ROOT_DIR/} -> ${dest_dir#$ROOT_DIR/}"
  rm -rf "$dest_dir"
  cp -a "$src_dir" "$dest_dir"
}

is_excluded_dir() {
  local rel_path="$1"
  local base_name="$2"
  local exclude_csv="$3"
  local exclude
  local excludes

  [[ "$base_name" == ".git" ]] && return 0

  IFS=',' read -r -a excludes <<< "$exclude_csv"
  for exclude in "${excludes[@]}"; do
    exclude="$(trim "$exclude")"
    [[ -n "$exclude" ]] || continue
    exclude="${exclude%/}"
    [[ "$base_name" == "$exclude" || "$rel_path" == "$exclude" ]] && return 0
  done

  return 1
}

copy_selected_dirs() {
  local repo_dir="$1"
  local source_csv="$2"
  local source_path
  local source_dirs
  local src_dir
  local dest_name

  IFS=',' read -r -a source_dirs <<< "$source_csv"
  for source_path in "${source_dirs[@]}"; do
    source_path="$(trim "$source_path")"
    source_path="${source_path%/}"
    validate_relative_path "$source_path"

    src_dir="$repo_dir/$source_path"
    dest_name="${source_path##*/}"
    copy_dir_to_root "$src_dir" "$dest_name"
  done
}

copy_all_subdirs() {
  local repo_dir="$1"
  local exclude_csv="$2"
  local child
  local base_name

  shopt -s nullglob dotglob
  for child in "$repo_dir"/*; do
    [[ -d "$child" ]] || continue

    base_name="${child##*/}"
    if is_excluded_dir "$base_name" "$base_name" "$exclude_csv"; then
      log "Skipping ${child#$ROOT_DIR/}"
      continue
    fi

    copy_dir_to_root "$child" "$base_name"
  done
  shopt -u nullglob dotglob
}

main() {
  local spec
  local name
  local url
  local mapped_dir
  local copy_mode
  local source_dirs
  local exclude_dirs
  local repo_dir

  for spec in "${REPO_SPECS[@]}"; do
    IFS='|' read -r name url mapped_dir copy_mode source_dirs exclude_dirs <<< "$spec"

    validate_relative_path "$mapped_dir"
    repo_dir="$REPOS_DIR/$mapped_dir"

    ensure_repo "$name" "$url" "$repo_dir"

    case "$copy_mode" in
      selected)
        copy_selected_dirs "$repo_dir" "$source_dirs"
        ;;
      all_subdirs)
        copy_all_subdirs "$repo_dir" "$exclude_dirs"
        ;;
      *)
        die "unknown copy mode for $name: $copy_mode"
        ;;
    esac
  done
}

main "$@"
