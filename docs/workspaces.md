# Reusing temporary storage

A workspace owns arrays that are reused across operations. Start with one
retained workspace for sequential work. Use an `ObjectPool` when operations
need several independent workspaces with overlapping lifetimes.

| Lifetime | Building block | Release point |
| --- | --- | --- |
| One operation at a time | Caller-owned arrays or workspace | Clear logical contents before the next operation |
| Several overlapping operations | `ObjectPool[Workspace]` with private referenced storage | Release each lease after its last reader |
| One batch of numeric ranges | `LinearAllocator` | Reset after the entire batch completes |
| Ordered streaming ranges | `RingAllocator` | Release the oldest allocation after its consumers complete |
| Work whose completion is reported later | `RetirementQueue[T]` | Take ready values, then recycle or dispose them |

## Ownership and borrowing

The application creates storage, lends it to an operation, consumes the result,
and then releases the lease. The next operation may overwrite that storage.
Pointers and slices into a workspace must not outlive its lease. A slice is not
an independent result; explicitly clone data that must survive reuse.

`ObjectPool` checks lease identity, but cannot prevent callers from keeping
aliases, releasing while another thread reads, or inserting the same resource
twice. The application must preserve exclusive access. Method-level locking
would not protect pointers used after the lock is released.

## Values versus references in V

V may copy nested arrays when a value is assigned to a mutable local. In
particular, a reset callback of the form `mut reset := value` is not evidence
that backing storage has been retained. Use ordinary value pooling when that
copying is appropriate. For reusable mutable arrays, the examples create private
heap storage and pool small value wrappers containing a reference to it instead.
Copying the wrapper preserves that reference without copying its nested arrays.
This also works with released V 0.5.2, whose generic default-value handling does
not support directly pooling reference types in these APIs.

The factory allocates independent storage, the live lease has exclusive access,
and release ends every use before reset begins. Do not return a shared singleton
from the factory, or keep using its storage after release. Released V 0.5.2
requires a small `unsafe` reset block to mutate referenced storage through the
existing immutable-value callback. Its validity depends on exclusive ownership
and the ended lease; it does not permit arbitrary aliasing. The examples use V's
normal memory management; they do not establish
automatic cleanup for externally owned files, sockets or GPU resources.

The workspace tests check separate live storage, backing-array identity across
reuse, stale leases, independent copied results, and release on error. Capacity
alone does not establish that a buffer was not copied.

## Bounds and reset policy

Preallocate each array for a declared maximum, and reject an oversized request
before changing logical contents. Prewarm the pool for the maximum number of
leases needed on the processing path. Pool capacity bounds the number of
workspaces, not the bytes inside them: an array that grows on an exceptional
request may retain that larger capacity indefinitely.

The supplied workspace admits at most 256 items and rejects larger requests.
It clears logical lengths on release and retains capacity. Clearing is not
secure erasure: overwrite sensitive bytes explicitly according to application
requirements. The example does not silently grow, trim, retry, or allocate a
fallback buffer.

Run `./scripts/run_examples.sh` or `v run examples/workspaces` from a correctly
installed module. The example includes a retained workspace, two simultaneous
leases, exhaustion, an oversized request, and an independently owned output.

## Reusing handle snapshots

`SlotPool.handles_into(mut destination)` and
`ObjectPool.handles_into(mut destination)` replace a caller-owned array with a
snapshot of live handles. Pre-size its capacity for the pool to avoid repeated
snapshot storage allocation. Insufficient capacity is allowed and grows normally.
The snapshot uses the same traversal as `handles()`; there is no stable sorting
guarantee. Subsequent release can make copied handles stale.

## Measuring the improvement

The optimized benchmark compares identical synthetic requests with fresh,
retained and pooled workspaces, then compares fresh and caller-buffer handle
snapshots. It includes empty, variable-size, maximum-size and rejected oversized
requests. Full-size warm-up is outside the measured section. Checksums and trace
hashes enforce result equivalence; creation counts, backing-storage changes,
retained payload capacity and peak logical usage describe the work performed.

Creation counts are explicit workspace-factory calls, not malloc counts. Buffer
capacity is not resident memory. Payload copies, V runtime bookkeeping and
unrelated application code may still allocate. Timings are diagnostic, depend on
the machine and compiler, and are never universal pass/fail thresholds.
