module memory

fn test_buddy_allocator_validates_configuration() {
	if _ := new_buddy_allocator(0, 1) {
		assert false, 'zero capacity must fail'
	} else {
		assert err.msg().contains('capacity')
	}
	if _ := new_buddy_allocator(48, 4) {
		assert false, 'non-power-of-two capacity must fail'
	} else {
		assert err.msg().contains('power of two')
	}
	if _ := new_buddy_allocator(64, 3) {
		assert false, 'non-power-of-two minimum block must fail'
	} else {
		assert err.msg().contains('block size')
	}
	if _ := new_buddy_allocator(64, 128) {
		assert false, 'minimum block beyond capacity must fail'
	} else {
		assert err.msg().contains('exceeds')
	}
}

fn test_buddy_allocator_rounds_aligns_and_coalesces() {
	mut allocator := new_buddy_allocator(64, 4) or { panic(err) }
	first := allocator.allocate(5, 8) or { panic(err) }
	second := allocator.allocate(3, 4) or { panic(err) }

	assert first.offset == 0
	assert first.size == 5
	assert first.block_size == 8
	assert first.end() == 5
	assert first.block_end() == 8
	assert second.offset == 8
	assert second.block_size == 4
	assert allocator.contains(first)
	assert allocator.contains(second)

	stats := allocator.stats()
	assert stats.capacity == 64
	assert stats.reserved == 12
	assert stats.payload == 8
	assert stats.internal_fragmentation == 4
	assert stats.free == 52
	assert stats.allocation_count == 2
	assert stats.largest_free_block == 32

	assert allocator.release(first)
	assert allocator.stats().largest_free_block == 32
	assert allocator.release(second)
	assert allocator.stats().largest_free_block == 64
	assert allocator.free_bytes() == 64
}

fn test_buddy_allocator_validates_requests_and_reports_exhaustion() {
	mut allocator := new_buddy_allocator(32, 4) or { panic(err) }
	if _ := allocator.allocate(0, 1) {
		assert false, 'zero size must fail'
	} else {
		assert err.msg().contains('size')
	}
	if _ := allocator.allocate(1, 3) {
		assert false, 'non-power-of-two alignment must fail'
	} else {
		assert err.msg().contains('alignment')
	}
	whole := allocator.allocate(17, 1) or { panic(err) }
	assert whole.block_size == 32
	if _ := allocator.allocate(1, 1) {
		assert false, 'allocation beyond capacity must fail'
	} else {
		assert err.msg().contains('exhausted')
	}
	assert allocator.release(whole)
}

fn test_buddy_allocator_rejects_foreign_forged_and_stale_allocations() {
	mut first_allocator := new_buddy_allocator(32, 4) or { panic(err) }
	mut second_allocator := new_buddy_allocator(32, 4) or { panic(err) }
	allocation := first_allocator.allocate(7, 4) or { panic(err) }
	foreign := second_allocator.allocate(7, 4) or { panic(err) }

	assert !first_allocator.contains(foreign)
	assert !first_allocator.release(foreign)
	assert !first_allocator.release(BuddyAllocation{
		owner:      allocation.owner
		id:         allocation.id
		offset:     allocation.offset
		size:       allocation.size
		block_size: allocation.block_size * 2
	})
	assert first_allocator.contains(allocation)

	first_allocator.reset()
	assert !first_allocator.contains(allocation)
	assert !first_allocator.release(allocation)
	assert first_allocator.stats().largest_free_block == 32
}

fn test_buddy_allocator_deterministic_stress() {
	capacity := u64(4096)
	mut allocator := new_buddy_allocator(capacity, 8) or { panic(err) }
	mut active := []BuddyAllocation{}
	mut state := u32(0xbadd1e55)

	for step in 0 .. 10_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len > 0 && state % 3 == 0 {
			index := int((state >> 8) % u32(active.len))
			allocation := active[index]
			assert allocator.release(allocation)
			active.delete(index)
		} else {
			size := u64(1 + (state >> 12) % 193)
			alignment := u64(1) << u32((state >> 28) % 8)
			if allocation := allocator.allocate(size, alignment) {
				assert allocation.offset % alignment == 0
				assert allocation.block_size >= size
				assert is_power_of_two(allocation.block_size)
				assert allocation.block_end() <= capacity
				active << allocation
			} else if active.len > 0 {
				index := int((state >> 8) % u32(active.len))
				assert allocator.release(active[index])
				active.delete(index)
			}
		}

		if step % 50 == 0 {
			assert_buddy_allocator_invariants(allocator, active)
		}
	}

	for allocation in active {
		assert allocator.release(allocation)
	}
	assert_buddy_allocator_invariants(allocator, [])
	assert allocator.stats().largest_free_block == capacity
}

fn assert_buddy_allocator_invariants(allocator &BuddyAllocator, active []BuddyAllocation) {
	stats := allocator.stats()
	assert stats.allocation_count == active.len
	assert stats.reserved == stats.payload + stats.internal_fragmentation
	assert stats.reserved + stats.free == stats.capacity
	assert stats.largest_free_block <= stats.free
	mut reserved := u64(0)
	mut payload := u64(0)
	for index, allocation in active {
		assert allocator.contains(allocation)
		reserved += allocation.block_size
		payload += allocation.size
		for other in active[index + 1..] {
			assert allocation.block_end() <= other.offset || other.block_end() <= allocation.offset
		}
	}
	assert stats.reserved == reserved
	assert stats.payload == payload
}
