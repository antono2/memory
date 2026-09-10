module memory

// ObjectFactory creates one value when an ObjectPool has no reusable value
// available.
pub type ObjectFactory[T] = fn () T

// ObjectReset prepares a released value for its next acquisition.
pub type ObjectReset[T] = fn (value T) T

// ObjectPool lazily creates and reuses up to capacity values.
//
// Acquired values use the same generation- and owner-checked Handle as
// SlotPool. The pool is not internally synchronized.
pub struct ObjectPool[T] {
	factory ObjectFactory[T] @[required]
	reset   ObjectReset[T]   @[required]
mut:
	leases    &SlotPool[T] @[required]
	available []T
	created   int
}

// new_object_pool creates a bounded object pool. preallocated values are
// created immediately and the remaining capacity is created lazily.
pub fn new_object_pool[T](capacity int, preallocated int, factory ObjectFactory[T], reset ObjectReset[T]) !&ObjectPool[T] {
	if capacity < 0 {
		return error('object pool capacity must not be negative')
	}
	if preallocated < 0 {
		return error('object pool preallocated count must not be negative')
	}
	if preallocated > capacity {
		return error('object pool preallocated count exceeds capacity')
	}
	leases := new_slot_pool[T](capacity)!
	mut pool := &ObjectPool[T]{
		factory:   factory
		reset:     reset
		leases:    leases
		available: []T{cap: capacity}
	}
	pool.prewarm(preallocated)!
	return pool
}

// capacity returns the maximum number of simultaneously acquired values.
pub fn (pool &ObjectPool[T]) capacity() int {
	return pool.leases.capacity()
}

// len returns the number of currently acquired values.
pub fn (pool &ObjectPool[T]) len() int {
	return pool.leases.len()
}

// available_count returns the number of created values ready for acquisition.
pub fn (pool &ObjectPool[T]) available_count() int {
	return pool.available.len
}

// created_count returns the number of values created by the factory. It is
// bounded by capacity and does not decrease when values are released.
pub fn (pool &ObjectPool[T]) created_count() int {
	return pool.created
}

// is_empty reports whether no values are currently acquired.
pub fn (pool &ObjectPool[T]) is_empty() bool {
	return pool.leases.is_empty()
}

// is_full reports whether every lease slot is occupied.
pub fn (pool &ObjectPool[T]) is_full() bool {
	return pool.leases.is_full()
}

// prewarm ensures that at least target values have been created. It does not
// acquire any values and returns an error when target exceeds capacity.
pub fn (mut pool ObjectPool[T]) prewarm(target int) ! {
	if target < 0 {
		return error('object pool prewarm target must not be negative')
	}
	if target > pool.capacity() {
		return error('object pool prewarm target exceeds capacity')
	}
	for pool.created < target {
		pool.available << pool.factory()
		pool.created++
	}
}

// acquire returns a handle for one reused or newly created value. It returns an
// error when all capacity is currently acquired.
pub fn (mut pool ObjectPool[T]) acquire() !Handle {
	if pool.leases.is_full() {
		return error('object pool is exhausted')
	}
	mut value := T{}
	if pool.available.len > 0 {
		value = pool.available.pop()
	} else {
		value = pool.factory()
		pool.created++
	}
	return pool.leases.insert(value)
}

// contains reports whether handle identifies a value acquired from this pool.
pub fn (pool &ObjectPool[T]) contains(handle Handle) bool {
	return pool.leases.contains(handle)
}

// get returns a pointer to the acquired value, or none for an invalid handle.
// Do not retain the pointer after releasing the handle or calling release_all().
pub fn (pool &ObjectPool[T]) get(handle Handle) ?&T {
	return pool.leases.get(handle)
}

// get_mut returns a mutable pointer to the acquired value, or none for an
// invalid handle. Do not retain it after release or release_all().
pub fn (mut pool ObjectPool[T]) get_mut(handle Handle) ?&T {
	return pool.leases.get_mut(handle)
}

// handles returns a snapshot of every currently acquired handle.
pub fn (pool &ObjectPool[T]) handles() []Handle {
	return pool.leases.handles()
}

// release resets an acquired value and makes it available for reuse. It
// returns false for stale, forged, foreign, or already released handles.
pub fn (mut pool ObjectPool[T]) release(handle Handle) bool {
	mut value := pool.leases.take(handle) or { return false }
	value = pool.reset(value)
	pool.available << value
	return true
}

// release_all resets and releases every currently acquired value. It returns
// the number of values released.
pub fn (mut pool ObjectPool[T]) release_all() int {
	handles := pool.leases.handles()
	mut released := 0
	for handle in handles {
		if pool.release(handle) {
			released++
		}
	}
	return released
}
