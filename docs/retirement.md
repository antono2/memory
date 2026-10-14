# Completion-driven resource retirement

`RetirementQueue[T]` holds values until the caller reports that every operation
through a completion token has finished. It has fixed entry capacity and FIFO
retrieval. The application provides completion evidence and destroys or recycles
each returned resource.

The lifecycle is:

```text
resource acquired -> registered/submitted -> pending -> completion observed
                  -> take ready value -> recycle/dispose -> reuse
```

Submitting work does not mean that its inputs are reusable. The queue performs
no polling, waiting, scheduling, destruction or synchronization.

## Token contract

- A new queue starts with completion frontier zero; retirement tokens start at one.
- Enqueue tokens must be greater than the completed frontier and nondecreasing
  across successful enqueues. Equal tokens group resources from one operation.
- Completion reports may stay equal or advance, and may exceed the newest queued
  token. They must never move backward.
- A completion report asserts that **every operation through that token** is
  finished. The largest individually completed job number is not sufficient.
- Draining does not reset token ordering. Tokens do not wrap. After draining and
  ending every outstanding use, construct a new queue for a new completion domain.
- Each queue represents one ordered domain. Independent GPU queues, timelines or
  unrelated worker streams need separate queues or explicit caller aggregation.

`enqueue(value, after)` fails without changing the queue for invalid tokens or
exhaustion. Failed enqueue leaves resource responsibility with the caller. A
successful enqueue transfers that responsibility by convention; V cannot enforce
unique ownership of arbitrary values. Do not queue duplicate disposal of one
resource. `advance_completed(token)` rejects backward reports without mutation.
`try_take_ready()` returns the oldest ready value or none, removing its reference
from the queue. The caller now owns any cleanup failure and must retain the value
for retry itself.

There is no reset or destroy-all operation that could accidentally bypass pending
work. During shutdown, stop producers, wait for actual outstanding work, report
completion, drain and dispose, then destroy backing resources. If the device or
worker fails, follow its API's recovery rules; do not invent completion evidence.

## Backpressure and error paths

Zero capacity is valid but always full. Negative capacity is rejected. Ready
values still occupy entries until taken. Bound the number of outstanding entries
and explicitly drain, wait, retry or reject when full. The queue's bookkeeping
storage never grows after construction; copied payloads can still allocate or
hold arbitrary amounts of memory.

Register a job's pooled lease before starting work when possible, so a rejected
registration can return an unsubmitted lease immediately. For ring allocation,
establish queue capacity and token validity before reserving a range: the newest
allocation cannot generally be rolled back while older FIFO allocations remain.
The streaming recipe uses one producer that generates its own tokens. Sharing
that sequence requires one external synchronization boundary around reservation,
registration and token generation.

Run `examples/deferred_ring` for simulated streaming completion, wraparound,
backpressure and shutdown. Run `examples/deferred_jobs` for completion order
2, 1, 3: completion of job 2 alone must release nothing while job 1 is pending.
The same bounded token/frontier bookkeeping serves both numeric ranges and typed
pool leases; only completion detection and recycling remain specific to each
application. That shared mechanism motivates the public queue.

`RingAllocator` still has its own dynamically managed record array. A fixed
retirement queue does not make the entire streaming workflow allocation-free.

## Vulkan integration

In a Vulkan adapter, derive tokens from an ordered submission stream and advance
the frontier only after the associated fence or timeline value has actually
completed. Preserve all Vulkan synchronization and mapped-memory requirements.
The core queue intentionally has no Vulkan dependency. Existing `UploadRing`
allocations must still be retired in allocation order, and their backing memory
must outlive pending GPU work.
