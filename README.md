# Memory management building blocks for V

[![CI](https://github.com/antono2/memory/actions/workflows/ci.yml/badge.svg)](https://github.com/antono2/memory/actions/workflows/ci.yml)

`memory` provides small, documented, and tested building blocks for reusing
objects and managing bounded memory and resource ranges in V.

The library includes checked slot and object pools plus range, linear, and ring
allocators. Each implementation is dependency-free and accompanied by a
directly runnable example. Optional Vulkan suballocation examples can build on
the same core without making the general-purpose module Vulkan-specific.

## Install

```sh
v install https://github.com/antono2/memory
```

Then import it using its module name:

```v
import memory
```

The 1.x release line uses `memory` as both the repository and V import name.
Projects that still import `generic_pool` should pin the 0.2.0 release until
they are ready to update their imports.

## Slot pool

Create a pool once, insert values until it reaches its fixed capacity, and use
the returned handle for later access or release:

```v
import memory

struct Particle {
mut:
	x f32
	y f32
}

fn main() {
	mut particles := memory.new_slot_pool[Particle](128) or { panic(err) }
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
import memory

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
	mut buffers := memory.new_object_pool[Buffer](16, 4, make_buffer,
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
import memory

fn main() {
	mut block := memory.new_range_allocator(256 * 1024 * 1024)
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

## Linear allocator

`LinearAllocator` provides O(1) aligned bump allocation for data that shares a
lifetime. Individual ranges are not released; `reset()` invalidates all of them
at once while preserving the peak-use statistic.

```v
import memory

fn main() {
	mut frame_arena := memory.new_linear_allocator(4 * 1024 * 1024)
	vertices := frame_arena.allocate(96 * 1024, 16) or { panic(err) }
	uniforms := frame_arena.allocate(256, 256) or { panic(err) }

	println('vertex offset ${vertices.offset}')
	println('uniform offset ${uniforms.offset}')
	println('alignment padding ${frame_arena.stats().padding}')

	frame_arena.reset()
	assert !frame_arena.contains(vertices)
}
```

Consumed bytes include alignment gaps; payload and padding are also reported
separately. Failed allocations never advance the cursor. This makes the type
useful for frame uploads, parsers, request-scoped storage, and scratch buffers.

## Ring allocator

`RingAllocator` reuses a fixed-size range for contiguous allocations retired in
the same order they were created. It is designed for staging buffers, streaming
data, and resources whose lifetime follows a GPU submission or producer queue.

```v
import memory

fn main() {
	mut uploads := memory.new_ring_allocator(64 * 1024 * 1024)
	frame_0 := uploads.allocate(4 * 1024, 256) or { panic(err) }
	frame_1 := uploads.allocate(8 * 1024, 256) or { panic(err) }

	// Retire allocations when their submissions complete.
	frame_0_released := uploads.release(frame_0)
	assert frame_0_released
	frame_1_released := uploads.release(frame_1)
	assert frame_1_released
}
```

Payloads never cross the end of the managed range. If an allocation wraps, the
unused suffix is counted as padding and reclaimed with that allocation. Release
is strictly FIFO: attempting to release a newer live allocation returns
`false` without changing allocator state. Statistics expose payload, padding,
free space, peak occupancy, allocation count, and the largest currently usable
contiguous region.

## Vulkan integration

[`antono2.vkmemalloc`](https://github.com/antono2/vulkan_memory_allocator) is a
directly usable Vulkan integration built on `RangeAllocator`. It suballocates
compatible buffers from memory-type-specific `VkDeviceMemory` blocks, keeps
images isolated for Vulkan granularity safety, honors dedicated-allocation
metadata, and provides a real device smoke example. Its `UploadRing` builds on
this module's `RingAllocator` to provide persistently mapped staging slices that
are retired in GPU submission order.

```sh
v install antono2.vkmemalloc
```

The Vulkan module owns API-specific handles and policy while this module remains
dependency-free and useful for host memory, files, parsers, resource tables,
and other bounded allocation domains.

## Examples

Runnable actor, retained-buffer, free-range, frame-arena, and streaming-upload
examples are included:

```sh
v run examples/object_pool
v run examples/buffer_pool
v run examples/range_allocator
v run examples/linear_allocator
v run examples/ring_allocator
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

- allocation and fragmentation benchmarks
- specialized allocation policies driven by benchmark results
- additional integrations that keep platform APIs outside the core module

## License

This project is available under the [MIT License](LICENSE).
