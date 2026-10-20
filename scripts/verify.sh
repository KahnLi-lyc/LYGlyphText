#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# == 1 ]] || { echo 'Usage: scripts/verify.sh docs|format' >&2; exit 2; }
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$project_root/scripts/check_repository.py" "$1"
