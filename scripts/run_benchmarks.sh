#!/usr/bin/env sh
# Runs optimized allocator benchmarks using a temporary module path.
# Accepts an operation count or --quick for the shorter CI workload.
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-memory-bench-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM

operations=${1:-1000000}
if [ "$operations" = '--quick' ]; then
	operations=50000
fi

mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/memory"

VMODULES="$modules_dir" v -prod run "$repo_dir/benchmarks" "$operations"
