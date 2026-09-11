# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Make the published VPM package the primary installation path and retain
  manual source-checkout instructions for contributors.

## 1.1.0 - 2026-09-11

- Restore `antono2.memory` as the canonical module, import, repository, and
  installed-directory identity.
- Add a deterministic power-of-two `BuddyAllocator` with checked allocation
  records, recursive coalescing, occupancy statistics, tests, and an example.
- Add an independent bitmap-model stress test for deterministic first-fit range
  allocation under fragmentation.
- Add deterministic object-pool lifecycle stress coverage.
- Add reproducible optimized churn benchmarks for every allocation strategy,
  including fragmentation and occupancy diagnostics.
- Replay an identical bounded allocation trace for first-fit and buddy benchmark
  comparisons, with success, failure, peak-use, and trace-integrity diagnostics.
- Run the allocator test suite and canonical `antono2.memory` public-import
  examples on Linux, macOS, and Windows in CI.
- Add a task-oriented allocator selection guide covering lifetime, release
  order, and fragmentation tradeoffs.

## 1.0.3 - 2026-09-10

- Record the superseded short-name packaging experiment performed before VPM
  publication.

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
