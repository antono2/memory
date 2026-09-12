module memory

fn test_synchronized_range_allocator_exposes_root_api() {
	mut allocator := new_synchronized_range_allocator(128)
	allocation := allocator.allocate(24, 16) or { panic(err) }
	assert allocation.offset == 0
	assert allocator.contains(allocation)
	assert allocator.used_bytes() == 24
	assert allocator.free_bytes() == 104
	assert allocator.allocation_count() == 1
	assert allocator.stats().largest_free_range == 104
	assert allocator.release(allocation)
	assert allocator.stats().largest_free_range == 128
}

fn test_synchronized_buddy_allocator_exposes_root_api() {
	mut allocator := new_synchronized_buddy_allocator(128, 8) or { panic(err) }
	allocation := allocator.allocate(17, 16) or { panic(err) }
	assert allocation.offset == 0
	assert allocation.block_size == 32
	assert allocator.contains(allocation)
	assert allocator.min_block_size() == 8
	assert allocator.used_bytes() == 32
	assert allocator.payload_bytes() == 17
	assert allocator.free_bytes() == 96
	assert allocator.allocation_count() == 1
	assert allocator.release(allocation)
	assert allocator.stats().largest_free_block == 128
}

fn test_synchronized_allocators_reset_live_allocations() {
	mut ranges := new_synchronized_range_allocator(64)
	range_allocation := ranges.allocate(8, 1) or { panic(err) }
	ranges.reset()
	assert !ranges.contains(range_allocation)
	assert ranges.free_bytes() == ranges.capacity()

	mut buddies := new_synchronized_buddy_allocator(64, 8) or { panic(err) }
	buddy_allocation := buddies.allocate(8, 8) or { panic(err) }
	buddies.reset()
	assert !buddies.contains(buddy_allocation)
	assert buddies.free_bytes() == buddies.capacity()
}
