# Generic pools and allocators for V

[![CI](https://github.com/antono2/v_generic_pool/actions/workflows/ci.yml/badge.svg)](https://github.com/antono2/v_generic_pool/actions/workflows/ci.yml)

`generic_pool` provides small, documented, and tested building blocks
for reusing objects and managing bounded resources in V.

The first implementation is `SlotPool[T]`: a fixed-capacity pool with constant-
time insertion and release. It returns generation-checked handles instead of
pointers that could become stale or move when an array grows.

The project is also a collection of directly runnable examples. Future releases
will add linear, free-range, and ring allocation, followed by optional Vulkan
suballocation examples built on the same dependency-free core.

## Install

```sh
v install https://github.com/antono2/v_generic_pool
```

Then import it using its VPM name:

```v
import generic_pool
```

## Slot pool

Create a pool once, insert values until it reaches its fixed capacity, and use
the returned handle for later access or release:

```v
import generic_pool

struct Particle {
mut:
	x f32
	y f32
}

fn main() {
	mut particles := generic_pool.new_slot_pool[Particle](128) or { panic(err) }
	handle := particles.insert(Particle{x: 10, y: 20}) or { panic(err) }

	mut particle := particles.get_mut(handle) or { panic('stale particle handle') }
	particle.x += 1

	assert particles.release(handle)
	assert particles.get(handle) == none
}
```

### Guarantees

- `insert`, `get`, and `release` are O(1).
- The pool never grows after construction.
- Releasing or clearing a slot invalidates its earlier handles.
- A stale, forged, or already released handle is rejected.
- `clear()` invalidates all active handles without reallocating the pool.
- The implementation is not internally synchronized. Externally synchronize
  access shared between threads.

Pointers returned by `get()` and `get_mut()` must not be retained after their
handle is released or the pool is cleared. Doing so bypasses handle validation.

The generation counter can eventually wrap after 4,294,967,295 releases of the
same slot. Generation zero is reserved and skipped.

## Examples

The actor example demonstrates several typed pools and type-specific behavior:

```sh
v run examples/object_pool
```

When working from a source checkout rather than an installed V module, run
`./scripts/run_examples.sh`; the script creates an isolated module path and does
not modify the user's installed modules.

## Verify

```sh
v fmt -verify .
v vet .
v test .
./scripts/run_examples.sh
```

## Roadmap

- factory/reset-callback object pools
- aligned linear arenas
- coalescing free-range allocation
- transient ring and frame allocation
- optional Vulkan device-memory suballocation examples
- deterministic stress tests and allocation/fragmentation benchmarks

## License

This project is available under the [MIT License](LICENSE).
