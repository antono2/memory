#!/usr/bin/env sh
# Runs allocator tests against this checkout using an isolated V module path.
# Removes the temporary module links on exit without changing installed modules.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-memory-test-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM

mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/memory"

VMODULES="$modules_dir" v test "$repo_dir"
