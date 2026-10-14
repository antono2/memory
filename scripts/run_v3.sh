#!/usr/bin/env sh
# Verifies the pinned compiler, ordinary mode, strict V3 and repeated public builds.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-memory-v3-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM
v_compiler=${VEXE:-v}
mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/memory"
export VMODULES="$modules_dir"
python3 "$repo_dir/scripts/compatibility.py" --profile v3
python3 "$repo_dir/scripts/doctor.py" --v "$v_compiler" --profile v3 --modules "$modules_dir"
"$v_compiler" test "$repo_dir"
"$v_compiler" -new-compiler test "$repo_dir"
for example in workspaces deferred_ring deferred_jobs; do
	for pass in 1 2; do
		"$v_compiler" -new-compiler -o "$modules_dir/$example" "$repo_dir/examples/$example"
		"$modules_dir/$example"
	done
done
"$v_compiler" -new-compiler -prod run "$repo_dir/benchmarks" 50000
