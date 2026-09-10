module generic_pool

fn test_range_allocator_aligns_tracks_and_coalesces() {
	mut allocator := new_range_allocator(128)
	first := allocator.allocate(13, 1) or { panic(err) }
	second := allocator.allocate(16, 16) or { panic(err) }

	assert first.offset == 0
	assert first.size == 13
	assert first.end() == 13
	assert second.offset == 16
	assert second.end() == 32
	assert allocator.contains(first)
	assert allocator.contains(second)

	stats := allocator.stats()
	assert stats.capacity == 128
	assert stats.used == 29
	assert stats.free == 99
	assert stats.allocation_count == 2
	assert stats.free_range_count == 2
	assert stats.largest_free_range == 96

	first_release := allocator.release(first)
	assert first_release
	double_release := allocator.release(first)
	assert !double_release
	second_release := allocator.release(second)
	assert second_release
	final_stats := allocator.stats()
	assert final_stats.used == 0
	assert final_stats.free == 128
	assert final_stats.allocation_count == 0
	assert final_stats.free_range_count == 1
	assert final_stats.largest_free_range == 128
}

fn test_range_allocator_supports_non_power_of_two_alignment() {
	mut allocator := new_range_allocator(8)
	first := allocator.allocate(2, 1) or { panic(err) }
	second := allocator.allocate(1, 3) or { panic(err) }

	assert first.offset == 0
	assert second.offset == 3
	assert second.offset % 3 == 0
}

fn test_range_allocator_validates_requests_and_reports_fragmentation() {
	mut allocator := new_range_allocator(64)
	if _ := allocator.allocate(0, 1) {
		assert false, 'zero size must fail'
	} else {
		assert err.msg().contains('size')
	}
	if _ := allocator.allocate(1, 0) {
		assert false, 'zero alignment must fail'
	} else {
		assert err.msg().contains('alignment')
	}

	mut allocations := []RangeAllocation{cap: 4}
	for _ in 0 .. 4 {
		allocations << allocator.allocate(16, 1) or { panic(err) }
	}
	first_release := allocator.release(allocations[0])
	assert first_release
	third_release := allocator.release(allocations[2])
	assert third_release
	stats := allocator.stats()
	assert stats.free == 32
	assert stats.free_range_count == 2
	assert stats.largest_free_range == 16
	if _ := allocator.allocate(24, 1) {
		assert false, 'fragmented request must fail'
	} else {
		assert err.msg().contains('fragmented')
	}

	second_release := allocator.release(allocations[1])
	assert second_release
	large := allocator.allocate(24, 1) or { panic(err) }
	assert large.offset == 0
}

fn test_range_allocator_rejects_foreign_and_forged_allocations() {
	mut first_allocator := new_range_allocator(32)
	mut second_allocator := new_range_allocator(32)
	allocation := first_allocator.allocate(8, 1) or { panic(err) }
	foreign := second_allocator.allocate(8, 1) or { panic(err) }

	assert !first_allocator.contains(foreign)
	foreign_release := first_allocator.release(foreign)
	assert !foreign_release
	forged_release := first_allocator.release(RangeAllocation{
		owner:  allocation.owner
		id:     allocation.id
		offset: allocation.offset + 1
		size:   allocation.size
	})
	assert !forged_release
	assert first_allocator.contains(allocation)
}

fn test_range_allocator_reset_invalidates_allocations() {
	mut allocator := new_range_allocator(100)
	old := allocator.allocate(25, 8) or { panic(err) }
	allocator.reset()

	assert !allocator.contains(old)
	old_release := allocator.release(old)
	assert !old_release
	assert allocator.used_bytes() == 0
	assert allocator.free_bytes() == 100
	assert allocator.allocation_count() == 0

	fresh := allocator.allocate(100, 1) or { panic(err) }
	assert fresh.offset == 0
	assert fresh.id != old.id
}

fn test_range_allocator_handles_alignment_overflow() {
	mut allocator := new_range_allocator(max_u64)
	large := allocator.allocate(max_u64 - 3, 1) or { panic(err) }
	if _ := allocator.allocate(2, 8) {
		assert false, 'alignment overflow must fail'
	} else {
		assert err.msg().contains('exhausted')
	}
	large_release := allocator.release(large)
	assert large_release
	assert allocator.stats().largest_free_range == max_u64
}

fn test_range_allocator_deterministic_stress() {
	capacity := u64(4096)
	mut allocator := new_range_allocator(capacity)
	mut active := []RangeAllocation{}
	mut state := u32(0xa110ca7e)

	for step in 0 .. 5_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len > 0 && state % 3 == 0 {
			index := int(state % u32(active.len))
			allocation := active[index]
			released := allocator.release(allocation)
			assert released
			active.delete(index)
		} else {
			size := u64(1 + state % 96)
			alignment := u64(1) << u32((state >> 8) % 7)
			if allocation := allocator.allocate(size, alignment) {
				assert allocation.offset % alignment == 0
				active << allocation
			} else if active.len > 0 {
				index := int((state >> 16) % u32(active.len))
				released := allocator.release(active[index])
				assert released
				active.delete(index)
			}
		}

		if step % 25 == 0 {
			assert_range_allocator_invariants(allocator, active)
		}
	}

	for allocation in active {
		released := allocator.release(allocation)
		assert released
	}
	assert_range_allocator_invariants(allocator, [])
	stats := allocator.stats()
	assert stats.free_range_count == 1
	assert stats.largest_free_range == capacity
}

fn assert_range_allocator_invariants(allocator &RangeAllocator, active []RangeAllocation) {
	assert allocator.allocation_count() == active.len
	assert allocator.used_bytes() + allocator.free_bytes() == allocator.capacity()
	for i, allocation in active {
		assert allocator.contains(allocation)
		assert allocation.end() <= allocator.capacity()
		for other in active[i + 1..] {
			assert allocation.end() <= other.offset || other.end() <= allocation.offset
		}
	}
	mut free_total := u64(0)
	for i, free_range in allocator.free_ranges {
		assert free_range.size > 0
		assert free_range.offset <= allocator.capacity() - free_range.size
		free_total += free_range.size
		if i > 0 {
			previous := allocator.free_ranges[i - 1]
			assert previous.offset + previous.size < free_range.offset
		}
	}
	assert free_total == allocator.free_bytes()
}
