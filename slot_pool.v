module generic_pool

// Handle identifies one occupied slot at a specific generation.
//
// Handles are intentionally opaque. Keep the complete value returned by
// insert() and pass it back to contains(), get(), get_mut(), or release().
pub struct Handle {
	index      int
	generation u32
	owner      voidptr
}

struct Slot[T] {
mut:
	value      T
	generation u32 = 1
	occupied   bool
	next_free  int = -1
}

// SlotPool is a fixed-capacity, generation-checked pool of values.
//
// It uses an intrusive free list, making insert() and release() O(1). The pool
// does not grow, so addresses returned by get() and get_mut() remain stable
// until their slot is released or the pool is cleared.
pub struct SlotPool[T] {
mut:
	slots     []Slot[T]
	free_head int = -1
	used      int
}

// new_slot_pool creates an empty pool with exactly capacity slots.
pub fn new_slot_pool[T](capacity int) !&SlotPool[T] {
	if capacity < 0 {
		return error('slot pool capacity must not be negative')
	}
	mut slots := []Slot[T]{len: capacity}
	for i in 0 .. capacity {
		slots[i].generation = 1
		slots[i].next_free = if i + 1 < capacity { i + 1 } else { -1 }
	}
	return &SlotPool[T]{
		slots:     slots
		free_head: if capacity > 0 { 0 } else { -1 }
	}
}

// capacity returns the fixed number of slots owned by the pool.
pub fn (pool &SlotPool[T]) capacity() int {
	return pool.slots.len
}

// len returns the number of currently occupied slots.
pub fn (pool &SlotPool[T]) len() int {
	return pool.used
}

// is_empty reports whether the pool has no occupied slots.
pub fn (pool &SlotPool[T]) is_empty() bool {
	return pool.used == 0
}

// is_full reports whether every slot is occupied.
pub fn (pool &SlotPool[T]) is_full() bool {
	return pool.used == pool.slots.len
}

// insert occupies one free slot and returns its generation-checked handle.
// It returns an error when the fixed-capacity pool is full.
pub fn (mut pool SlotPool[T]) insert(value T) !Handle {
	if pool.free_head < 0 {
		return error('slot pool is full')
	}
	index := pool.free_head
	mut slot := &pool.slots[index]
	pool.free_head = slot.next_free
	slot.next_free = -1
	slot.value = value
	slot.occupied = true
	pool.used++
	return Handle{
		index:      index
		generation: slot.generation
		owner:      pool
	}
}

// contains reports whether handle currently identifies an occupied slot.
pub fn (pool &SlotPool[T]) contains(handle Handle) bool {
	if handle.owner != voidptr(pool) || handle.index < 0 || handle.index >= pool.slots.len {
		return false
	}
	slot := &pool.slots[handle.index]
	return slot.occupied && slot.generation == handle.generation
}

// get returns a pointer to the value identified by handle, or none when the
// handle is stale, forged, foreign, or already released. Do not retain the
// pointer after releasing its handle or clearing the pool.
pub fn (pool &SlotPool[T]) get(handle Handle) ?&T {
	if !pool.contains(handle) {
		return none
	}
	return &pool.slots[handle.index].value
}

// get_mut returns a mutable pointer to the value identified by handle, or none
// when the handle is stale, forged, foreign, or already released. Do not retain
// the pointer after releasing its handle or clearing the pool.
pub fn (mut pool SlotPool[T]) get_mut(handle Handle) ?&T {
	if !pool.contains(handle) {
		return none
	}
	return &pool.slots[handle.index].value
}

// release returns a slot to the free list. It returns false for a stale,
// forged, or already released handle and leaves the pool unchanged.
pub fn (mut pool SlotPool[T]) release(handle Handle) bool {
	if !pool.contains(handle) {
		return false
	}
	mut slot := &pool.slots[handle.index]
	slot.value = T{}
	slot.occupied = false
	slot.generation = next_generation(slot.generation)
	slot.next_free = pool.free_head
	pool.free_head = handle.index
	pool.used--
	return true
}

// clear releases every occupied slot and invalidates all of its active handles
// without reallocating the pool.
pub fn (mut pool SlotPool[T]) clear() {
	for i in 0 .. pool.slots.len {
		mut slot := &pool.slots[i]
		if slot.occupied {
			slot.value = T{}
			slot.generation = next_generation(slot.generation)
		}
		slot.occupied = false
		slot.next_free = if i + 1 < pool.slots.len { i + 1 } else { -1 }
	}
	pool.free_head = if pool.slots.len > 0 { 0 } else { -1 }
	pool.used = 0
}

fn next_generation(generation u32) u32 {
	next := generation + 1
	return if next == 0 { u32(1) } else { next }
}
