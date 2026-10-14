# API stability and support

Beginning with v1.4.0, `antono2.memory` follows semantic versioning for its
public root-module API.

## Stable surface

The following are compatibility commitments within the 1.x release series:

- public type, function and method names in `antono2.memory`
- public allocation and statistics fields
- documented allocation order, release order, validation and reset behavior
- acceptance of every configuration and request described as valid
- rejection of stale, forged, foreign or out-of-order records where documented

New types, methods and fields may be added in a minor release. Removing or
incompatibly changing stable behavior requires a new major release. When
practical, an API scheduled for removal will first be deprecated for at least
one minor release.

## Not a serialized or binary interface

Handles and allocation records are process-local capability values. Their
private ownership and generation fields must not be forged, persisted, sent to
another process or reconstructed from public offsets and sizes. Struct memory
layout, private fields, internal data structures, allocation identifiers and
exact error wording are implementation details.

Use error propagation for allocation failure; do not branch on the complete
error string. Public statistics are diagnostic snapshots and do not reserve or
guarantee a later allocation.

## Threading

`SlotPool`, `ObjectPool`, `RangeAllocator`, `LinearAllocator`, `RingAllocator`,
`BuddyAllocator` and `RetirementQueue` require external synchronization when shared between
threads. `SynchronizedRangeAllocator` and `SynchronizedBuddyAllocator` protect
their allocation metadata with reader/writer mutexes.

Synchronization does not protect the backing host memory, mapped file, shared
memory, Vulkan memory or other resource represented by an offset. Applications
must coordinate use, release, reset and destruction of that resource.

Pool accessors return pointers whose use may outlive a method call. For that
reason, the package does not claim that wrapping individual pool methods in a
mutex would make pointer access thread-safe.

## Supported compiler

The minimum tested compiler for v1.4.x is V 0.5.2. Every release is tested on
Linux, macOS and Windows with that compiler. V itself is evolving, so support
for later compiler releases is verified and adjusted in subsequent package
releases rather than assumed.

The additive workspace and retirement APIs also have a pinned Linux current-V
profile in `compatibility.json`, exercised in ordinary and explicit
`-new-compiler` modes. This does not change the minimum compiler or imply native
V3 runtime coverage on Windows or macOS. See [validation](docs/validation.md).

## Workspace and completion ownership

`handles_into()` returns the same kind of handle snapshot as `handles()` using
caller-owned output storage. Reusing output capacity does not extend a lease.
Workspace references and slices must stop being used before release or reset;
copied arrays may allocate according to V's value semantics.

`RetirementQueue` adds bounded bookkeeping for a single caller-owned completion
domain. Its token ordering, failure atomicity and FIFO readiness are part of the
stable root API. Completion evidence, unique resource ownership, cleanup and
shutdown remain with the caller. Token ordering belongs to that domain and must
not silently wrap. There is no reset that bypasses pending work.
See [workspace lifetimes](docs/workspaces.md) and [retirement](docs/retirement.md).
