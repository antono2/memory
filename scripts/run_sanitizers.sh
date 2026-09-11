#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
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

cd "$repo_dir"
v -cc "$sanitizer_compiler" \
	-cflags -fsanitize=address,undefined \
	-cflags -fno-omit-frame-pointer \
	-ldflags -fsanitize=address,undefined \
	test .
