module mem

fn test_linear_allocator_aligns_and_accounts_for_padding() {
	mut allocator := new_linear_allocator(64)
	first := allocator.allocate(3, 1) or { panic(err) }
	second := allocator.allocate(4, 8) or { panic(err) }

	assert first.offset == 0
	assert first.end() == 3
	assert second.offset == 8
	assert second.end() == 12
	assert allocator.contains(first)
	assert allocator.contains(second)

	stats := allocator.stats()
	assert stats.capacity == 64
	assert stats.used == 12
	assert stats.payload == 7
	assert stats.padding == 5
	assert stats.remaining == 52
	assert stats.peak_used == 12
	assert stats.allocation_count == 2
}

fn test_linear_allocator_validates_and_does_not_advance_on_failure() {
	mut allocator := new_linear_allocator(16)
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

	full := allocator.allocate(16, 1) or { panic(err) }
	assert full.offset == 0
	before := allocator.stats()
	if _ := allocator.allocate(1, 1) {
		assert false, 'allocation beyond capacity must fail'
	} else {
		assert err.msg().contains('exhausted')
	}
	assert allocator.stats() == before
}

fn test_linear_allocator_reset_invalidates_and_retains_peak() {
	mut allocator := new_linear_allocator(32)
	old := allocator.allocate(20, 1) or { panic(err) }
	allocator.reset()

	assert !allocator.contains(old)
	assert allocator.used_bytes() == 0
	assert allocator.remaining_bytes() == 32
	assert allocator.allocation_count() == 0
	assert allocator.stats().peak_used == 20

	fresh := allocator.allocate(8, 8) or { panic(err) }
	assert allocator.contains(fresh)
	assert fresh.generation != old.generation
}

fn test_linear_allocator_rejects_foreign_and_forged_allocations() {
	mut first_allocator := new_linear_allocator(32)
	mut second_allocator := new_linear_allocator(32)
	allocation := first_allocator.allocate(8, 1) or { panic(err) }
	foreign := second_allocator.allocate(8, 1) or { panic(err) }

	assert !first_allocator.contains(foreign)
	assert !first_allocator.contains(LinearAllocation{
		owner:      allocation.owner
		generation: allocation.generation
		offset:     31
		size:       2
	})
}

fn test_linear_allocator_handles_alignment_overflow() {
	mut allocator := new_linear_allocator(max_u64)
	large := allocator.allocate(max_u64 - 3, 1) or { panic(err) }
	assert allocator.contains(large)
	if _ := allocator.allocate(2, 8) {
		assert false, 'alignment overflow must fail'
	} else {
		assert err.msg().contains('exhausted')
	}
}

fn test_linear_allocator_generation_skips_zero() {
	mut allocator := new_linear_allocator(1)
	allocator.generation = max_u64
	allocator.reset()
	assert allocator.generation == 1
}

fn test_linear_allocator_deterministic_stress() {
	capacity := u64(2048)
	mut allocator := new_linear_allocator(capacity)
	mut current := []LinearAllocation{}
	mut state := u32(0x1a2b3c4d)

	for _ in 0 .. 5_000 {
		state = state * 1_664_525 + 1_013_904_223
		size := u64(1 + state % 64)
		alignment := u64(1) << u32((state >> 8) % 7)
		if allocation := allocator.allocate(size, alignment) {
			assert allocation.offset % alignment == 0
			assert allocation.end() <= capacity
			assert allocator.contains(allocation)
			current << allocation
		} else {
			for allocation in current {
				assert allocator.contains(allocation)
			}
			allocator.reset()
			for allocation in current {
				assert !allocator.contains(allocation)
			}
			current.clear()
		}
		stats := allocator.stats()
		assert stats.used == stats.payload + stats.padding
		assert stats.used + stats.remaining == capacity
	}
}
