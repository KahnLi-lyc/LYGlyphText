#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
if [[ $# == 1 && ( "$1" == docs || "$1" == format ) ]]; then
    exec python3 "$project_root/scripts/check_repository.py" "$1"
elif [[ $# == 1 && "$1" == build ]] || [[ $# == 2 && "$1" == test ]]; then
    exec python3 "$project_root/scripts/verify_ios.py" "$@"
fi
echo 'Usage: scripts/verify.sh docs|format|build|test <UDID>' >&2
exit 2
