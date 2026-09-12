#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-memory-sanitizer-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM
sanitizer_compiler=${V_SANITIZER_CC:-clang}

if ! command -v "$sanitizer_compiler" >/dev/null 2>&1; then
	echo "sanitizer compiler not found: $sanitizer_compiler" >&2
	exit 1
fi

# V uses process-lifetime allocations for compiler/runtime bookkeeping, so this
# gate targets invalid accesses and undefined behavior rather than leak reports.
ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=0:halt_on_error=1}
UBSAN_OPTIONS=${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}
export ASAN_OPTIONS UBSAN_OPTIONS

mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/memory"

VMODULES="$modules_dir" v -cc "$sanitizer_compiler" \
	-cflags -fsanitize=address,undefined \
	-cflags -fno-omit-frame-pointer \
	-ldflags -fsanitize=address,undefined \
	test "$repo_dir"
