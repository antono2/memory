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

struct SynchronizedRangePair {
	plain  RangeAllocation
	locked RangeAllocation
}

struct SynchronizedBuddyPair {
	plain  BuddyAllocation
	locked BuddyAllocation
}

fn test_synchronized_range_allocator_matches_plain_trace() {
	mut plain := new_range_allocator(4096)
	mut locked := new_synchronized_range_allocator(4096)
	mut active := []SynchronizedRangePair{}
	alignments := [u64(1), 2, 3, 4, 8, 16, 31, 64]
	mut state := u32(0x5a11ce55)

	for _ in 0 .. 10_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len > 0 && state % 3 == 0 {
			index := int((state >> 8) % u32(active.len))
			pair := active[index]
			assert plain.release(pair.plain)
			assert locked.release(pair.locked)
			active.delete(index)
		} else {
			size := u64(1 + (state >> 12) % 193)
			alignment := alignments[int((state >> 24) % u32(alignments.len))]
			if plain_allocation := plain.allocate(size, alignment) {
				locked_allocation := locked.allocate(size, alignment) or {
					panic('synchronized range allocator diverged: ${err}')
				}
				assert locked_allocation.offset == plain_allocation.offset
				assert locked_allocation.size == plain_allocation.size
				active << SynchronizedRangePair{
					plain:  plain_allocation
					locked: locked_allocation
				}
			} else {
				if unexpected := locked.allocate(size, alignment) {
					assert false, 'synchronized allocator unexpectedly returned ${unexpected.offset}'
				}
			}
		}
		assert locked.stats() == plain.stats()
	}

	for pair in active {
		assert plain.release(pair.plain)
		assert locked.release(pair.locked)
	}
	assert locked.stats() == plain.stats()
}

fn test_synchronized_buddy_allocator_matches_plain_trace() {
	mut plain := new_buddy_allocator(4096, 8) or { panic(err) }
	mut locked := new_synchronized_buddy_allocator(4096, 8) or { panic(err) }
	mut active := []SynchronizedBuddyPair{}
	mut state := u32(0xbaddcafe)

	for _ in 0 .. 10_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len > 0 && state % 3 == 0 {
			index := int((state >> 8) % u32(active.len))
			pair := active[index]
			assert plain.release(pair.plain)
			assert locked.release(pair.locked)
			active.delete(index)
		} else {
			size := u64(1 + (state >> 12) % 257)
			alignment := u64(1) << u32((state >> 28) % 10)
			if plain_allocation := plain.allocate(size, alignment) {
				locked_allocation := locked.allocate(size, alignment) or {
					panic('synchronized buddy allocator diverged: ${err}')
				}
				assert locked_allocation.offset == plain_allocation.offset
				assert locked_allocation.size == plain_allocation.size
				assert locked_allocation.block_size == plain_allocation.block_size
				active << SynchronizedBuddyPair{
					plain:  plain_allocation
					locked: locked_allocation
				}
			} else {
				if unexpected := locked.allocate(size, alignment) {
					assert false, 'synchronized allocator unexpectedly returned ${unexpected.offset}'
				}
			}
		}
		assert locked.stats() == plain.stats()
	}

	for pair in active {
		assert plain.release(pair.plain)
		assert locked.release(pair.locked)
	}
	assert locked.stats() == plain.stats()
}
