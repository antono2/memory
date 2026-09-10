module mem

fn test_ring_allocator_aligns_and_accounts_for_padding() {
	mut allocator := new_ring_allocator(32)
	first := allocator.allocate(3, 1) or { panic(err) }
	second := allocator.allocate(4, 8) or { panic(err) }

	assert first.offset == 0
	assert second.offset == 8
	assert allocator.contains(first)
	assert allocator.contains(second)
	stats := allocator.stats()
	assert stats.used == 12
	assert stats.payload == 7
	assert stats.padding == 5
	assert stats.free == 20
	assert stats.allocation_count == 2

	first_release := allocator.release(first)
	assert first_release
	second_release := allocator.release(second)
	assert second_release
	assert allocator.stats().largest_contiguous_free == 32
}

fn test_ring_allocator_wraps_and_releases_in_fifo_order() {
	mut allocator := new_ring_allocator(32)
	first := allocator.allocate(12, 1) or { panic(err) }
	second := allocator.allocate(12, 1) or { panic(err) }
	first_release := allocator.release(first)
	assert first_release

	wrapped := allocator.allocate(10, 8) or { panic(err) }
	assert wrapped.offset == 0
	assert wrapped.end() == 10
	stats := allocator.stats()
	assert stats.used == 30
	assert stats.payload == 22
	assert stats.padding == 8
	assert stats.free == 2
	assert stats.largest_contiguous_free == 2

	out_of_order := allocator.release(wrapped)
	assert !out_of_order
	assert allocator.contains(wrapped)
	second_release := allocator.release(second)
	assert second_release
	assert allocator.stats().largest_contiguous_free == 14
	wrapped_release := allocator.release(wrapped)
	assert wrapped_release
	assert allocator.used_bytes() == 0
	assert allocator.free_bytes() == 32
}

fn test_ring_allocator_reports_fragmentation_without_mutation() {
	mut allocator := new_ring_allocator(16)
	first := allocator.allocate(6, 1) or { panic(err) }
	_ = allocator.allocate(6, 1) or { panic(err) }
	first_release := allocator.release(first)
	assert first_release
	before := allocator.stats()

	if _ := allocator.allocate(7, 1) {
		assert false, 'fragmented request must fail'
	} else {
		assert err.msg().contains('fragmented')
	}
	assert allocator.stats() == before
	assert before.free == 10
	assert before.largest_contiguous_free == 6
}

fn test_ring_allocator_validates_requests() {
	mut allocator := new_ring_allocator(0)
	if _ := allocator.allocate(1, 1) {
		assert false, 'zero-capacity allocation must fail'
	} else {
		assert err.msg().contains('exhausted')
	}
	mut usable := new_ring_allocator(8)
	if _ := usable.allocate(0, 1) {
		assert false, 'zero size must fail'
	} else {
		assert err.msg().contains('size')
	}
	if _ := usable.allocate(1, 0) {
		assert false, 'zero alignment must fail'
	} else {
		assert err.msg().contains('alignment')
	}
}

fn test_ring_allocator_rejects_foreign_forged_and_stale_allocations() {
	mut first_allocator := new_ring_allocator(16)
	mut second_allocator := new_ring_allocator(16)
	allocation := first_allocator.allocate(4, 1) or { panic(err) }
	foreign := second_allocator.allocate(4, 1) or { panic(err) }

	assert !first_allocator.contains(foreign)
	foreign_release := first_allocator.release(foreign)
	assert !foreign_release
	forged_release := first_allocator.release(RingAllocation{
		owner:  allocation.owner
		id:     allocation.id
		offset: allocation.offset + 1
		size:   allocation.size
	})
	assert !forged_release

	first_allocator.reset()
	assert !first_allocator.contains(allocation)
	stale_release := first_allocator.release(allocation)
	assert !stale_release
}

fn test_ring_allocator_handles_alignment_overflow() {
	mut allocator := new_ring_allocator(max_u64)
	large := allocator.allocate(max_u64 - 3, 1) or { panic(err) }
	assert allocator.contains(large)
	if _ := allocator.allocate(2, 8) {
		assert false, 'alignment overflow must fail'
	} else {
		assert err.msg().contains('fragmented')
	}
}

fn test_ring_allocator_compacts_retired_metadata() {
	mut allocator := new_ring_allocator(2)
	mut oldest := allocator.allocate(1, 1) or { panic(err) }
	for _ in 0 .. 1_500 {
		newest := allocator.allocate(1, 1) or { panic(err) }
		released := allocator.release(oldest)
		assert released
		oldest = newest
	}
	assert allocator.allocation_count() == 1
	assert allocator.records.len < 1024
	final_release := allocator.release(oldest)
	assert final_release
}

fn test_ring_allocator_deterministic_stress() {
	capacity := u64(1024)
	mut allocator := new_ring_allocator(capacity)
	mut active := []RingAllocation{}
	mut state := u32(0x71f01234)

	for step in 0 .. 5_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len > 0 && state % 4 == 0 {
			released := allocator.release(active[0])
			assert released
			active.delete(0)
		} else {
			size := u64(1 + state % 48)
			alignment := u64(1) << u32((state >> 8) % 6)
			if allocation := allocator.allocate(size, alignment) {
				assert allocation.offset % alignment == 0
				assert allocation.end() <= capacity
				active << allocation
			} else if active.len > 0 {
				released := allocator.release(active[0])
				assert released
				active.delete(0)
			}
		}

		if step % 25 == 0 {
			assert_ring_allocator_invariants(allocator, active)
		}
	}

	for allocation in active {
		released := allocator.release(allocation)
		assert released
	}
	assert allocator.allocation_count() == 0
	assert allocator.free_bytes() == capacity
}

fn assert_ring_allocator_invariants(allocator &RingAllocator, active []RingAllocation) {
	stats := allocator.stats()
	assert stats.allocation_count == active.len
	assert stats.used == stats.payload + stats.padding
	assert stats.used + stats.free == stats.capacity
	assert stats.largest_contiguous_free <= stats.free
	for i, allocation in active {
		assert allocator.contains(allocation)
		assert allocation.end() <= allocator.capacity()
		for other in active[i + 1..] {
			assert allocation.end() <= other.offset || other.end() <= allocation.offset
		}
	}
}
