#!/usr/bin/env sh
# Compatibility entry for the V validation runner.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "${VEXE:-v}" run "$script_dir/run_validation.vsh" tests "$@"
