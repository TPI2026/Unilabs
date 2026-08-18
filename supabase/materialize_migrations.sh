#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
encoded="$root_dir/migrations/20260818081423_appointment_platform_hardening.sql.gz.b64"
target="$root_dir/migrations/20260818081423_appointment_platform_hardening.sql"

base64 --decode "$encoded" | gzip --decompress > "$target"
sha256sum --check "$root_dir/SHA256SUMS" --ignore-missing
printf 'Materialized %s\n' "$target"
