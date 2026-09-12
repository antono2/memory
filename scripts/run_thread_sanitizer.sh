#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules_dir=$(mktemp -d "${TMPDIR:-/tmp}/v-memory-tsan-modules.XXXXXX")
trap 'rm -rf "$modules_dir"' EXIT HUP INT TERM
sanitizer_compiler=${V_SANITIZER_CC:-clang}

if ! command -v "$sanitizer_compiler" >/dev/null 2>&1; then
	echo "sanitizer compiler not found: $sanitizer_compiler" >&2
	exit 1
fi

TSAN_OPTIONS=${TSAN_OPTIONS:-halt_on_error=1:second_deadlock_stack=1}
export TSAN_OPTIONS

mkdir -p "$modules_dir/antono2"
ln -s "$repo_dir" "$modules_dir/antono2/memory"

# V 0.5.2's default Boehm GC signal handler conflicts with ThreadSanitizer.
# The allocator wrappers do not depend on a specific GC, so disable it for this
# focused race check instead of suppressing ThreadSanitizer diagnostics.
VMODULES="$modules_dir" v -gc none -cc "$sanitizer_compiler" \
	-cflags -fsanitize=thread \
	-cflags -fno-omit-frame-pointer \
	-ldflags -fsanitize=thread \
	test "$repo_dir/concurrent"
