# Changelog

All notable changes to this project will be documented in this file.

## 1.0.2 - 2026-09-10

- Correct pre-VPM source installation instructions for V 0.5.2, which requires
  dotted modules to be cloned into their canonical nested module path.

## 1.0.1 - 2026-09-10

- Use the canonical `antono2.memory` VPM name and import path so V installs the
  module under `~/.vmodules/antono2/memory`.
- Document the canonical VPM installation and import names.

## 1.0.0 - 2026-09-10

- Rename the V module from `generic_pool`; this release used the short `memory`
  import and was superseded by v1.0.1 before VPM publication. Projects retaining
  the old import can pin v0.2.0.
- Update repository metadata and installation instructions for the
  `antono2/memory` name.
- Document the production-shaped Vulkan block-suballocation integration in
  `antono2.vkmemalloc`.
- Document the Vulkan persistent upload-ring integration built on
  `RingAllocator`.

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
