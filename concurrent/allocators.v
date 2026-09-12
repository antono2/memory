// Module concurrent preserves the v1.2 synchronized allocator API.
// New code can use memory.SynchronizedRangeAllocator and
// memory.SynchronizedBuddyAllocator directly from `antono2.memory`.
module concurrent

import antono2.memory

// RangeAllocator is the compatibility name for
// memory.SynchronizedRangeAllocator.
pub type RangeAllocator = memory.SynchronizedRangeAllocator

// new_range_allocator forwards to memory.new_synchronized_range_allocator.
pub fn new_range_allocator(capacity u64) &RangeAllocator {
	return memory.new_synchronized_range_allocator(capacity)
}

// BuddyAllocator is the compatibility name for
// memory.SynchronizedBuddyAllocator.
pub type BuddyAllocator = memory.SynchronizedBuddyAllocator

// new_buddy_allocator forwards to memory.new_synchronized_buddy_allocator.
pub fn new_buddy_allocator(capacity u64, minimum_block_size u64) !&BuddyAllocator {
	return memory.new_synchronized_buddy_allocator(capacity, minimum_block_size)
}
