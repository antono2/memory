// Synchronized allocator variants for sharing allocation metadata between
// threads. Synchronization does not cover the backing memory represented by
// returned offsets; callers remain responsible for that resource's lifetime
// and use.
module memory

import sync

// SynchronizedRangeAllocator protects a RangeAllocator with a reader/writer
// mutex. Mutations are serialized, while independent queries can run under a
// shared read lock.
//
// Keep the pointer returned by new_synchronized_range_allocator() and pass it
// as `mut` to worker threads. Do not copy the wrapper after construction.
pub struct SynchronizedRangeAllocator {
	mutex &sync.RwMutex @[required]
mut:
	inner &RangeAllocator @[required]
}

// new_synchronized_range_allocator creates a thread-safe first-fit range
// allocator.
pub fn new_synchronized_range_allocator(capacity u64) &SynchronizedRangeAllocator {
	return &SynchronizedRangeAllocator{
		mutex: sync.new_rwmutex()
		inner: new_range_allocator(capacity)
	}
}

// capacity returns the fixed size of the managed resource.
pub fn (allocator &SynchronizedRangeAllocator) capacity() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.capacity()
}

// used_bytes returns the sum of all live allocation sizes.
pub fn (allocator &SynchronizedRangeAllocator) used_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.used_bytes()
}

// free_bytes returns the number of bytes not currently allocated.
pub fn (allocator &SynchronizedRangeAllocator) free_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.free_bytes()
}

// allocation_count returns the number of live allocations.
pub fn (allocator &SynchronizedRangeAllocator) allocation_count() int {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.allocation_count()
}

// allocate reserves one aligned range while holding the write lock.
pub fn (mut allocator SynchronizedRangeAllocator) allocate(size u64, alignment u64) !RangeAllocation {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.allocate(size, alignment)
}

// contains reports whether allocation is live and belongs to this allocator.
pub fn (allocator &SynchronizedRangeAllocator) contains(allocation RangeAllocation) bool {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.contains(allocation)
}

// release returns a live allocation to the free-range set.
pub fn (mut allocator SynchronizedRangeAllocator) release(allocation RangeAllocation) bool {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.release(allocation)
}

// reset releases every allocation. The caller must ensure that no thread still
// uses the associated backing-memory ranges.
pub fn (mut allocator SynchronizedRangeAllocator) reset() {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	allocator.inner.reset()
}

// stats returns one consistent occupancy and fragmentation snapshot.
pub fn (allocator &SynchronizedRangeAllocator) stats() RangeStats {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.stats()
}

// SynchronizedBuddyAllocator protects a BuddyAllocator with a reader/writer
// mutex. Mutations are serialized, while independent queries can run under a
// shared read lock.
//
// Keep the pointer returned by new_synchronized_buddy_allocator() and pass it
// as `mut` to worker threads. Do not copy the wrapper after construction.
pub struct SynchronizedBuddyAllocator {
	mutex &sync.RwMutex @[required]
mut:
	inner &BuddyAllocator @[required]
}

// new_synchronized_buddy_allocator creates a thread-safe power-of-two buddy
// allocator.
pub fn new_synchronized_buddy_allocator(capacity u64, minimum_block_size u64) !&SynchronizedBuddyAllocator {
	inner := new_buddy_allocator(capacity, minimum_block_size)!
	return &SynchronizedBuddyAllocator{
		mutex: sync.new_rwmutex()
		inner: inner
	}
}

// capacity returns the fixed size of the managed arena.
pub fn (allocator &SynchronizedBuddyAllocator) capacity() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.capacity()
}

// min_block_size returns the smallest block this allocator can reserve.
pub fn (allocator &SynchronizedBuddyAllocator) min_block_size() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.min_block_size()
}

// used_bytes returns bytes reserved by live buddy blocks.
pub fn (allocator &SynchronizedBuddyAllocator) used_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.used_bytes()
}

// payload_bytes returns the sum of requested live allocation sizes.
pub fn (allocator &SynchronizedBuddyAllocator) payload_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.payload_bytes()
}

// free_bytes returns capacity not reserved by live buddy blocks.
pub fn (allocator &SynchronizedBuddyAllocator) free_bytes() u64 {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.free_bytes()
}

// allocation_count returns the number of live allocations.
pub fn (allocator &SynchronizedBuddyAllocator) allocation_count() int {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.allocation_count()
}

// allocate reserves one buddy block while holding the write lock.
pub fn (mut allocator SynchronizedBuddyAllocator) allocate(size u64, alignment u64) !BuddyAllocation {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.allocate(size, alignment)
}

// contains reports whether allocation is live and belongs to this allocator.
pub fn (allocator &SynchronizedBuddyAllocator) contains(allocation BuddyAllocation) bool {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.contains(allocation)
}

// release returns a live block and recursively coalesces free buddies.
pub fn (mut allocator SynchronizedBuddyAllocator) release(allocation BuddyAllocation) bool {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	return allocator.inner.release(allocation)
}

// reset releases every allocation. The caller must ensure that no thread still
// uses the associated backing-memory ranges.
pub fn (mut allocator SynchronizedBuddyAllocator) reset() {
	allocator.mutex.lock()
	defer {
		allocator.mutex.unlock()
	}
	allocator.inner.reset()
}

// stats returns one consistent occupancy and fragmentation snapshot.
pub fn (allocator &SynchronizedBuddyAllocator) stats() BuddyStats {
	allocator.mutex.rlock()
	defer {
		allocator.mutex.runlock()
	}
	return allocator.inner.stats()
}
