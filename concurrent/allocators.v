// Module concurrent provides synchronized allocation-metadata wrappers.
//
// The wrappers protect allocator bookkeeping. They do not synchronize access
// to the backing memory represented by returned offsets, and callers must still
// coordinate the lifetime and use of that resource.
module concurrent

import antono2.memory
import sync

// RangeAllocator serializes mutations of a memory.RangeAllocator and permits
// concurrent read-only statistics and ownership checks.
//
// Keep the pointer returned by new_range_allocator() and pass it as `mut` to
// worker threads. Do not copy the wrapper after construction.
pub struct RangeAllocator {
	mutex &sync.RwMutex @[required]
mut:
	inner &memory.RangeAllocator @[required]
}

// new_range_allocator creates a synchronized first-fit range allocator.
pub fn new_range_allocator(capacity u64) &RangeAllocator {
	return &RangeAllocator{
		mutex: sync.new_rwmutex()
		inner: memory.new_range_allocator(capacity)
	}
}

// capacity returns the fixed size of the managed resource.
pub fn (allocator &RangeAllocator) capacity() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.capacity()
}

// used_bytes returns the sum of all live allocation sizes.
pub fn (allocator &RangeAllocator) used_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.used_bytes()
}

// free_bytes returns the number of bytes not currently allocated.
pub fn (allocator &RangeAllocator) free_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.free_bytes()
}

// allocation_count returns the number of live allocations.
pub fn (allocator &RangeAllocator) allocation_count() int {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.allocation_count()
}

// allocate reserves one aligned range while holding the write lock.
pub fn (mut allocator RangeAllocator) allocate(size u64, alignment u64) !memory.RangeAllocation {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.allocate(size, alignment)
}

// contains reports whether allocation is live and belongs to this allocator.
pub fn (allocator &RangeAllocator) contains(allocation memory.RangeAllocation) bool {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.contains(allocation)
}

// release returns a live allocation to the free-range set.
pub fn (mut allocator RangeAllocator) release(allocation memory.RangeAllocation) bool {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.release(allocation)
}

// reset releases every allocation. The caller must ensure that no thread still
// uses the associated backing-memory ranges.
pub fn (mut allocator RangeAllocator) reset() {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	allocator.inner.reset()
}

// stats returns one consistent occupancy and fragmentation snapshot.
pub fn (allocator &RangeAllocator) stats() memory.RangeStats {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.stats()
}

// BuddyAllocator serializes mutations of a memory.BuddyAllocator and permits
// concurrent read-only statistics and ownership checks.
//
// Keep the pointer returned by new_buddy_allocator() and pass it as `mut` to
// worker threads. Do not copy the wrapper after construction.
pub struct BuddyAllocator {
	mutex &sync.RwMutex @[required]
mut:
	inner &memory.BuddyAllocator @[required]
}

// new_buddy_allocator creates a synchronized power-of-two buddy allocator.
pub fn new_buddy_allocator(capacity u64, minimum_block_size u64) !&BuddyAllocator {
	inner := memory.new_buddy_allocator(capacity, minimum_block_size)!
	return &BuddyAllocator{
		mutex: sync.new_rwmutex()
		inner: inner
	}
}

// capacity returns the fixed size of the managed arena.
pub fn (allocator &BuddyAllocator) capacity() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.capacity()
}

// min_block_size returns the smallest block this allocator can reserve.
pub fn (allocator &BuddyAllocator) min_block_size() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.min_block_size()
}

// used_bytes returns bytes reserved by live buddy blocks.
pub fn (allocator &BuddyAllocator) used_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.used_bytes()
}

// payload_bytes returns the sum of requested live allocation sizes.
pub fn (allocator &BuddyAllocator) payload_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.payload_bytes()
}

// free_bytes returns capacity not reserved by live buddy blocks.
pub fn (allocator &BuddyAllocator) free_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.free_bytes()
}

// allocation_count returns the number of live allocations.
pub fn (allocator &BuddyAllocator) allocation_count() int {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.allocation_count()
}

// allocate reserves one buddy block while holding the write lock.
pub fn (mut allocator BuddyAllocator) allocate(size u64, alignment u64) !memory.BuddyAllocation {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.allocate(size, alignment)
}

// contains reports whether allocation is live and belongs to this allocator.
pub fn (allocator &BuddyAllocator) contains(allocation memory.BuddyAllocation) bool {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.contains(allocation)
}

// release returns a live block and recursively coalesces free buddies.
pub fn (mut allocator BuddyAllocator) release(allocation memory.BuddyAllocation) bool {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.release(allocation)
}

// reset releases every allocation. The caller must ensure that no thread still
// uses the associated backing-memory ranges.
pub fn (mut allocator BuddyAllocator) reset() {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	allocator.inner.reset()
}

// stats returns one consistent occupancy and fragmentation snapshot.
pub fn (allocator &BuddyAllocator) stats() memory.BuddyStats {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.stats()
}
