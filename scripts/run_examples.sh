#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-memory-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM

mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/memory"

for example in object_pool buffer_pool range_allocator linear_allocator ring_allocator; do
	VMODULES="$modules_dir" v run "$repo_dir/examples/$example"
done
