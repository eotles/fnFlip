#!/usr/bin/env bash
# apply-headers.sh
# Ensure all Swift source files carry a consistent header.
# Usage:
#   ./Tools/apply-headers.sh            # apply to all git-tracked Swift files
#   ./Tools/apply-headers.sh path1 ...  # apply to specific files or directories

set -euo pipefail

# --- Configuration -----------------------------------------------------------
PROJECT_NAME="fnFlip"
AUTHOR_NAME="Erkin Ötleş"
CURRENT_YEAR="$(date +%Y)"

# File globs to include by default (git tracked only)
DEFAULT_GLOBS=("*.swift" "*.swiftscript")

# Folders to ignore if paths are given
IGNORE_DIRS=(
  ".git"
  "Pods"
  "Carthage"
  "DerivedData"
  "build"
  ".build"
  "Tools/dist"
)

# --- Helpers ----------------------------------------------------------------
is_ignored_dir() {
  local p="$1"
  for d in "${IGNORE_DIRS[@]}"; do
    if [[ "$p" == *"/$d/"* || "$(basename "$p")" == "$d" ]]; then
      return 0
    fi
  done
  return 1
}

# Return 0 if the file already has our SPDX header in the first ~40 lines
has_spdx_header() {
  LC_ALL=C head -n 40 "$1" | grep -q 'SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0' || return 1
}

has_shebang_first_line() {
  LC_ALL=C head -n 1 "$1" | grep -q '^#!' || return 1
}

# Build the header text for a given filename
make_header() {
  local fname="$1"
  cat <<EOF
//
//  ${fname}
//  ${PROJECT_NAME}
//
//  Copyright (c) ${CURRENT_YEAR} ${AUTHOR_NAME}
//  Licensed under: MIT + Commons Clause (see LICENSE in repo root)
//  SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//
EOF
}

apply_header() {
  local file="$1"

  # If header already present, do nothing
  if has_spdx_header "$file"; then
    echo "  = Already has header: $file"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  local base
  base="$(basename "$file")"

  if has_shebang_first_line "$file"; then
    # Keep the shebang on line 1, insert header after it
    {
      head -n 1 "$file"
      echo
      make_header "$base"
      echo
      tail -n +2 "$file"
    } > "$tmp"
  else
    {
      make_header "$base"
      echo
      cat "$file"
    } > "$tmp"
  fi

  mv "$tmp" "$file"
}

# Expand input paths into a list of target files
collect_targets() {
  local -a out=()
  if [[ "$#" -eq 0 ]]; then
    # No args, operate on git-tracked files matching our globs
    for g in "${DEFAULT_GLOBS[@]}"; do
      while IFS= read -r f; do
        [[ -f "$f" ]] && out+=("$f")
      done < <(git ls-files "$g" 2>/dev/null || true)
    done
  else
    # Args present, walk them and pick matching files
    for p in "$@"; do
      if [[ -d "$p" ]]; then
        if is_ignored_dir "$p"; then
          continue
        fi
        while IFS= read -r f; do
          case "$f" in
            *.swift|*.swiftscript) out+=("$f") ;;
          esac
        done < <(find "$p" -type f \( -name "*.swift" -o -name "*.swiftscript" \) \
                 $(printf ' %s ' $(for d in "${IGNORE_DIRS[@]}"; do echo -n " -not -path */$d/*"; done)) )
      elif [[ -f "$p" ]]; then
        case "$p" in
          *.swift|*.swiftscript) out+=("$p") ;;
        esac
      fi
    done
  fi

  # De-duplicate and print one per line
  printf '%s\n' "${out[@]}" | awk 'NF && !seen[$0]++'
}

# --- Main -------------------------------------------------------------------
main() {
  local updated=0
  local any=0

  while IFS= read -r f; do
    any=1
    [[ -z "$f" ]] && continue

    if file -b "$f" | grep -qi 'text'; then
      apply_header "$f"
      ((updated++))
    else
      echo "  - Skipped non-text: $f"
    fi
  done < <(collect_targets "$@")

  if [[ "$any" -eq 0 ]]; then
    echo "No matching files found." >&2
    exit 0
  fi

  echo "Done. Processed $updated files."
}

main "$@"
