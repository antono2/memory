#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-generic-pool-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM

mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/generic_pool"

VMODULES="$modules_dir" v run "$repo_dir/examples/object_pool"
