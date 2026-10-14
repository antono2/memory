// Bounded FIFO bookkeeping for values held until caller-reported completion.
// The caller owns the completion domain, resource disposal and synchronization.
module memory

struct RetirementEntry[T] {
	value T
	after u64
}

// RetirementQueue holds values until an ordered completion frontier reaches
// their tokens. Use one queue per completion domain. It does not observe actual
// jobs, fences or timelines; reporting completion is the caller's responsibility.
// Bookkeeping storage is fixed at construction. Payload copies may allocate.
// The queue is not synchronized and does not destroy or reset resources.
pub struct RetirementQueue[T] {
mut:
	entries   []RetirementEntry[T]
	head      int
	count     int
	completed u64
	last      u64
}

// new_retirement_queue creates capacity entries. Zero capacity is valid but
// cannot accept values; negative capacity is rejected.
pub fn new_retirement_queue[T](capacity int) !&RetirementQueue[T] {
	if capacity < 0 {
		return error('retirement queue capacity must not be negative')
	}
	return &RetirementQueue[T]{
		entries: []RetirementEntry[T]{len: capacity}
	}
}

// capacity returns the fixed number of entries, not a bound on payload memory.
pub fn (queue &RetirementQueue[T]) capacity() int {
	return queue.entries.len
}

// len returns the number of pending and ready entries still held by the queue.
pub fn (queue &RetirementQueue[T]) len() int {
	return queue.count
}

// is_empty reports whether the queue holds no entries.
pub fn (queue &RetirementQueue[T]) is_empty() bool {
	return queue.count == 0
}

// is_full reports whether enqueue would exceed the entry capacity.
pub fn (queue &RetirementQueue[T]) is_full() bool {
	return queue.count == queue.entries.len
}

// completed_token returns the caller-reported frontier, initially zero.
pub fn (queue &RetirementQueue[T]) completed_token() u64 {
	return queue.completed
}

// enqueue holds value until after is completed. Tokens must be greater than the
// completed frontier and nondecreasing across successful enqueues, including
// after the queue empties. Equal tokens group values from the same submission.
// On failure the queue is unchanged and responsibility remains with the caller.
// On success the caller must not separately recycle the same resource. V does
// not enforce unique ownership of T or detect duplicate resource submissions.
pub fn (mut queue RetirementQueue[T]) enqueue(value T, after u64) ! {
	if after <= queue.completed || after < queue.last {
		return error('retirement token must be pending and nondecreasing')
	}
	if queue.is_full() {
		return error('retirement queue is full')
	}
	// Avoid overflowing int when a large queue wraps around its storage.
	until_end := queue.entries.len - queue.head
	index := if queue.count >= until_end {
		queue.count - until_end
	} else {
		queue.head + queue.count
	}
	queue.entries[index] = RetirementEntry[T]{
		value: value
		after: after
	}
	queue.last = after
	queue.count++
}

// advance_completed reports that every operation through token has completed.
// Equal reports are harmless; backward reports fail without changing the queue.
// Out-of-order job completion must first be converted into a contiguous frontier
// by the caller. Tokens never wrap; create a new domain after safely draining.
pub fn (mut queue RetirementQueue[T]) advance_completed(token u64) ! {
	if token < queue.completed {
		return error('completed token must not move backward')
	}
	queue.completed = token
}

// try_take_ready removes the oldest ready value, or returns none. The caller
// assumes responsibility for destruction/recycling, including disposal failures.
// Emptying the queue does not reset the completion frontier or token ordering.
pub fn (mut queue RetirementQueue[T]) try_take_ready() ?T {
	if queue.count == 0 || queue.entries[queue.head].after > queue.completed {
		return none
	}
	value := queue.entries[queue.head].value
	queue.entries[queue.head] = RetirementEntry[T]{}
	queue.head = (queue.head + 1) % queue.entries.len
	queue.count--
	return value
}
