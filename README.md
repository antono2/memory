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

	released := particles.release(handle)
	assert released
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

## Object pool

`ObjectPool[T]` adds lazy creation, prewarming, and reset-on-release behavior on
top of checked leases. Its factory runs only when no reusable value is available
and the fixed capacity has not been reached.

```v
import generic_pool

struct Buffer {
mut:
	data []u8
}

fn make_buffer() Buffer {
	return Buffer{data: []u8{cap: 4096}}
}

fn reset_buffer(buffer Buffer) Buffer {
	mut reset := buffer
	reset.data.clear()
	return reset
}

fn main() {
	mut buffers := generic_pool.new_object_pool[Buffer](16, 4, make_buffer,
		reset_buffer) or { panic(err) }

	handle := buffers.acquire() or { panic(err) }
	mut buffer := buffers.get_mut(handle) or { panic('stale buffer handle') }
	buffer.data << [u8(1), 2, 3]
	released := buffers.release(handle)
	assert released

	// The next acquisition reuses the reset buffer.
	reused := buffers.acquire() or { panic(err) }
	assert (buffers.get(reused) or { panic('stale buffer handle') }).data.len == 0
}
```

The reset callback receives the released value and returns the value to cache.
This works uniformly for structs, primitive values, and aliases. The object pool
also provides `prewarm()`, `release_all()`, counts, and a handle snapshot.

## Range allocator

`RangeAllocator` manages aligned offsets inside a fixed-size resource without
owning the resource itself. It uses deterministic first fit, returns checked
allocation records, and coalesces adjacent ranges when they are released.

```v
import generic_pool

fn main() {
	mut block := generic_pool.new_range_allocator(256 * 1024 * 1024)
	vertex_memory := block.allocate(48 * 1024, 256) or { panic(err) }

	println('bind at offset ${vertex_memory.offset}')
	println('exclusive end ${vertex_memory.end()}')

	released := block.release(vertex_memory)
	assert released
	assert block.free_bytes() == block.capacity()
}
```

The returned `offset` and `size` can index a byte buffer directly or be passed
to APIs such as `vkBindBufferMemory`. The allocator accepts any positive
alignment, detects alignment overflow, rejects stale/foreign/double releases,
and reports allocation count, free-range count, and largest free range.

Allocation and release are O(number of free ranges). This intentionally favors
a compact, inspectable implementation; specialized strategies can be added
behind separate types when benchmarks justify them.

## Examples

Runnable actor, retained-buffer, and aligned-range examples are included:

```sh
v run examples/object_pool
v run examples/buffer_pool
v run examples/range_allocator
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

- aligned linear arenas
- transient ring and frame allocation
- optional Vulkan device-memory suballocation examples
- deterministic stress tests and allocation/fragmentation benchmarks

## License

This project is available under the [MIT License](LICENSE).
