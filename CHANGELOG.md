# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Update repository metadata and installation instructions for the new
  `antono2/memory` name while retaining the `generic_pool` import name.
- Document the production-shaped Vulkan block-suballocation integration in
  `antono2.vkmemalloc`.

## 0.2.0 - 2026-09-10

- Convert the actor demonstration into the importable `generic_pool`
  module.
- Add the fixed-capacity, generation-checked `SlotPool[T]`.
- Add a bounded `ObjectPool[T]` with lazy creation, prewarming, reset callbacks,
  and bulk release.
- Add an aligned, coalescing `RangeAllocator` for suballocating offsets in host
  buffers, mapped files, shared memory, and GPU memory blocks.
- Add an O(1) aligned `LinearAllocator` for frame- and phase-scoped temporary
  ranges, including payload, padding, remaining, and peak-use statistics.
- Add a FIFO `RingAllocator` for staging buffers and streaming allocations,
  including aligned wraparound, checked releases, and occupancy statistics.
- Move the actor demonstration to `examples/object_pool`.
- Add automated formatting, vetting, tests, and example execution.
