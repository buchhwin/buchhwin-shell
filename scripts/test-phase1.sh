#!/usr/bin/env bash
set -euo pipefail

# Kept for existing documentation and habits; the suite lives in test.sh.
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test.sh" "$@"
