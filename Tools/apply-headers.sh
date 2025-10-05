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

# Return 0 if the file already has our SPDX header in the first 30 lines
has_spdx_header() {
  LC_ALL=C head -n 30 "$1" | grep -q 'SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0' || return 1
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

# Strip an existing top comment block if it already contains an SPDX line,
# then prepend the fresh header. If no SPDX header is found, just prepend.
apply_header() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"

  local base
  base="$(basename "$file")"

  if has_spdx_header "$file"; then
    # Remove the leading comment block up to and including the first blank line
    # only if that block contains our SPDX line.
    awk '
      BEGIN{spdx=0; inhead=1}
      NR<=30 && /SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0/ { spdx=1 }
      {
        if(inhead){
          if($0 ~ /^\/\/|^$/){
            if($0 ~ /^$/){ inhead=0 }
            next
          } else {
            inhead=0
          }
        }
        print $0
      }
      END{ if(spdx==0) exit 2 }
    ' "$file" > "$tmp" || {
      # If awk exit 2 (no SPDX in head), fall back to full file content
      cat "$file" > "$tmp"
    }
  else
    cat "$file" > "$tmp"
  fi

  {
    make_header "$base"
    echo
    cat "$tmp"
  } > "$file".with_header && mv "$file".with_header "$file"
  rm -f "$tmp"
}

# Expand input paths into a list of target files
collect_targets() {
  local -a out=()
  if [[ "$#" -eq 0 ]]; then
    # No args: operate on git-tracked files matching our globs
    for g in "${DEFAULT_GLOBS[@]}"; do
      while IFS= read -r f; do
        [[ -f "$f" ]] && out+=("$f")
      done < <(git ls-files "$g" 2>/dev/null || true)
    done
  else
    # Args present: walk them and pick matching files
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

  # Iterate without using mapfile, works on macOS Bash 3.x
  while IFS= read -r f; do
    any=1
    # Skip empty lines
    [[ -z "$f" ]] && continue

    # Skip non-text files defensively
    if file -b "$f" | grep -qi 'text'; then
      apply_header "$f"
      ((updated++))
      echo "  ✓ $f"
    else
      echo "  - Skipped non-text: $f"
    fi
  done < <(collect_targets "$@")

  if [[ "$any" -eq 0 ]]; then
    echo "No matching files found." >&2
    exit 0
  fi

  echo "Done. Updated $updated files."
}

main "$@"
