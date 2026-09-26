#!/usr/bin/env bash
set -euo pipefail
test "$#" = 1
profile=$(cd "$(dirname "$0")" && pwd)
snapshot=$(mktemp)
trap 'rm -f "$snapshot"' EXIT
curl --proto '=https' --fail --silent --show-error --max-time 10 --max-filesize 16777216 --output "$snapshot" "$1"
python3 "$profile/snapshot.py" < "$snapshot"
