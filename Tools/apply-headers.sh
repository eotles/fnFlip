#!/usr/bin/env bash
# apply-headers.sh — normalize headers & SPDX across the repo
# Copyright (c) 2025 Erkin Ötleş
# Licensed under: MIT + Commons Clause (see LICENSE)
# SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

set -euo pipefail

YEAR="2025"
OWNER="Erkin Ötleş"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".headers_backup/${STAMP}"
mkdir -p "${BACKUP_DIR}"

read -r -d '' SWIFT_HEADER <<'EOF'
// %f
// fnFlip
//
// Copyright (c) YEAR OWNER
// Licensed under: MIT + Commons Clause (see LICENSE in repo root)
// SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0
//
EOF
SWIFT_HEADER="${SWIFT_HEADER//YEAR/$YEAR}"
SWIFT_HEADER="${SWIFT_HEADER//OWNER/$OWNER}"

read -r -d '' SH_HEADER <<'EOF'
# %f
# Copyright (c) YEAR OWNER
# Licensed under: MIT + Commons Clause (see LICENSE)
# SPDX-License-Identifier: MIT AND LicenseRef-Commons-Clause-1.0

EOF
SH_HEADER="${SH_HEADER//YEAR/$YEAR}"
SH_HEADER="${SH_HEADER//OWNER/$OWNER}"

changed=0

normalize_swift() {
  local f="$1"
  cp -p "$f" "${BACKUP_DIR}/$(basename "$f")"

  # strip existing leading // comments and blank lines
  awk '
    BEGIN { skipping=1 }
    {
      if (skipping==1) {
        if ($0 ~ /^\/\//) next
        if ($0 ~ /^[[:space:]]*$/) next
        skipping=0
        print
      } else {
        print
      }
    }
  ' "$f" > "${f}.body"

  {
    printf "%s\n" "${SWIFT_HEADER//%f/$(basename "$f")}"
    cat "${f}.body"
  } > "${f}.new"

  mv "${f}.new" "$f"
  rm -f "${f}.body"
  changed=$((changed+1))
}

normalize_sh() {
  local f="$1"
  cp -p "$f" "${BACKUP_DIR}/$(basename "$f")"

  local first
  first="$(head -n1 "$f" || true)"
  local has_shebang=0
  [[ "$first" =~ ^#! ]] && has_shebang=1

  if [[ $has_shebang -eq 1 ]]; then
    tail -n +2 "$f" > "${f}.tail"
    # strip leading # comments and blanks from the tail
    awk '
      BEGIN { skipping=1 }
      {
        if (skipping==1) {
          if ($0 ~ /^#/) next
          if ($0 ~ /^[[:space:]]*$/) next
          skipping=0
          print
        } else {
          print
        }
      }
    ' "${f}.tail" > "${f}.body"
    {
      echo "$first"
      printf "%s" "${SH_HEADER//%f/$(basename "$f")}"
      cat "${f}.body"
    } > "${f}.new"
    rm -f "${f}.tail" "${f}.body"
  else
    # no shebang
    awk '
      BEGIN { skipping=1 }
      {
        if (skipping==1) {
          if ($0 ~ /^#/) next
          if ($0 ~ /^[[:space:]]*$/) next
          skipping=0
          print
        } else {
          print
        }
      }
    ' "$f" > "${f}.body"
    {
      echo "#!/usr/bin/env bash"
      printf "%s" "${SH_HEADER//%f/$(basename "$f")}"
      cat "${f}.body"
    } > "${f}.new"
    rm -f "${f}.body"
    chmod +x "${f}.new"
  fi

  mv "${f}.new" "$f"
  changed=$((changed+1))
}

# Swift sources
while IFS= read -r -d '' f; do
  normalize_swift "$f"
done < <(find . -type f -name "*.swift" -print0)

# Shell scripts in Tools
if [ -d Tools ]; then
  while IFS= read -r -d '' f; do
    normalize_sh "$f"
  done < <(find Tools -type f \( -name "*.sh" -o -name "autopackage" -o -name "*.command" \) -print0)
fi

echo "Headers normalized. Backups saved in ${BACKUP_DIR}"
echo "Files changed: ${changed}"
