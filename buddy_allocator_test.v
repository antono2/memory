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

struct BuddyModelAllocation {
	allocation  BuddyAllocation
	first_block int
	block_count int
}

fn model_buddy_block_count(size int, alignment int, minimum_block_size int) int {
	mut required := size
	if alignment > required {
		required = alignment
	}
	mut block_size := minimum_block_size
	for block_size < required {
		block_size *= 2
	}
	return block_size / minimum_block_size
}

fn model_buddy_first_free_block(occupied []bool, block_count int) ?int {
	if block_count <= 0 || block_count > occupied.len {
		return none
	}
	mut first := 0
	for first + block_count <= occupied.len {
		mut available := true
		for index in first .. first + block_count {
			if occupied[index] {
				available = false
				break
			}
		}
		if available {
			return first
		}
		first += block_count
	}
	return none
}

fn model_buddy_largest_free_block(occupied []bool, minimum_block_size int) u64 {
	mut block_count := occupied.len
	for block_count > 0 {
		mut first := 0
		for first < occupied.len {
			mut available := true
			for index in first .. first + block_count {
				if occupied[index] {
					available = false
					break
				}
			}
			if available {
				return u64(block_count * minimum_block_size)
			}
			first += block_count
		}
		block_count /= 2
	}
	return 0
}

fn test_buddy_allocator_matches_independent_block_model() {
	capacity := 512
	minimum_block_size := 8
	mut allocator := new_buddy_allocator(u64(capacity), u64(minimum_block_size)) or { panic(err) }
	mut occupied := []bool{len: capacity / minimum_block_size}
	mut active := []BuddyModelAllocation{}
	mut state := u32(0xb10c5eed)
	mut model_reserved := u64(0)
	mut model_peak_reserved := u64(0)

	for step in 0 .. 20_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len > 0 && state % 3 == 0 {
			index := int((state >> 8) % u32(active.len))
			record := active[index]
			assert allocator.release(record.allocation)
			for block in record.first_block .. record.first_block + record.block_count {
				assert occupied[block]
				occupied[block] = false
			}
			model_reserved -= u64(record.block_count * minimum_block_size)
			active.delete(index)
		} else {
			size := 1 + int((state >> 12) % 127)
			alignment := 1 << int((state >> 28) % 9)
			block_count := model_buddy_block_count(size, alignment, minimum_block_size)
			before := allocator.stats()
			if first_block := model_buddy_first_free_block(occupied, block_count) {
				allocation := allocator.allocate(u64(size), u64(alignment)) or {
					panic('model found block ${first_block}, allocator failed: ${err}')
				}
				assert allocation.offset == u64(first_block * minimum_block_size)
				assert allocation.block_size == u64(block_count * minimum_block_size)
				for block in first_block .. first_block + block_count {
					assert !occupied[block]
					occupied[block] = true
				}
				active << BuddyModelAllocation{
					allocation:  allocation
					first_block: first_block
					block_count: block_count
				}
				model_reserved += u64(block_count * minimum_block_size)
				if model_reserved > model_peak_reserved {
					model_peak_reserved = model_reserved
				}
			} else {
				if allocation := allocator.allocate(u64(size), u64(alignment)) {
					assert false, 'allocator returned unexpected block at ${allocation.offset}'
				}
				assert allocator.stats() == before
			}
		}

		if step % 100 == 0 {
			mut occupied_reserved := u64(0)
			for is_occupied in occupied {
				if is_occupied {
					occupied_reserved += u64(minimum_block_size)
				}
			}
			assert occupied_reserved == model_reserved
			mut model_payload := u64(0)
			for record in active {
				model_payload += record.allocation.size
			}
			stats := allocator.stats()
			assert stats.reserved == model_reserved
			assert stats.payload == model_payload
			assert stats.internal_fragmentation == model_reserved - model_payload
			assert stats.free == u64(capacity) - model_reserved
			assert stats.peak_reserved == model_peak_reserved
			assert stats.allocation_count == active.len
			assert stats.largest_free_block == model_buddy_largest_free_block(occupied,
				minimum_block_size)
		}
	}

	for record in active {
		assert allocator.release(record.allocation)
		for block in record.first_block .. record.first_block + record.block_count {
			assert occupied[block]
			occupied[block] = false
		}
	}
	final_stats := allocator.stats()
	assert final_stats.reserved == 0
	assert final_stats.payload == 0
	assert final_stats.peak_reserved == model_peak_reserved
	assert final_stats.largest_free_block == u64(capacity)
	assert model_buddy_largest_free_block(occupied, minimum_block_size) == u64(capacity)
}

fn test_buddy_allocator_allocation_ids_skip_zero_and_live_ids() {
	mut allocator := new_buddy_allocator(16, 4) or { panic(err) }
	first := allocator.allocate(4, 1) or { panic(err) }
	allocator.next_id = max_u64
	wrapped := allocator.allocate(4, 1) or { panic(err) }
	after_wrap := allocator.allocate(4, 1) or { panic(err) }

	assert first.id == 1
	assert wrapped.id == max_u64
	assert after_wrap.id == 2
	assert first.id != wrapped.id
	assert wrapped.id != after_wrap.id
}
