module memory

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

struct RingModelCandidate {
	offset         int
	reserved_start int
	reserved_size  int
}

struct RingModelRecord {
	allocation     RingAllocation
	reserved_start int
	reserved_size  int
}

struct RingReferenceModel {
	capacity int
mut:
	head      int
	tail      int
	used      int
	payload   int
	peak_used int
	occupied  []bool
	records   []RingModelRecord
}

fn new_ring_reference_model(capacity int) RingReferenceModel {
	return RingReferenceModel{
		capacity: capacity
		occupied: []bool{len: capacity}
	}
}

fn align_int_forward(value int, alignment int) int {
	return (value + alignment - 1) / alignment * alignment
}

fn (model &RingReferenceModel) allocation_candidate(size int, alignment int) ?RingModelCandidate {
	if size <= 0 || alignment <= 0 || model.capacity == 0 || size > model.capacity {
		return none
	}
	if model.records.len == 0 {
		return RingModelCandidate{
			offset:         0
			reserved_start: 0
			reserved_size:  size
		}
	}
	available := model.capacity - model.used
	if size > available {
		return none
	}
	if model.head < model.tail {
		aligned_offset := align_int_forward(model.head, alignment)
		if aligned_offset <= model.tail && size <= model.tail - aligned_offset {
			return RingModelCandidate{
				offset:         aligned_offset
				reserved_start: model.head
				reserved_size:  aligned_offset - model.head + size
			}
		}
		return none
	}

	aligned_offset := align_int_forward(model.head, alignment)
	if aligned_offset <= model.capacity && size <= model.capacity - aligned_offset {
		reserved_size := aligned_offset - model.head + size
		if reserved_size <= available {
			return RingModelCandidate{
				offset:         aligned_offset
				reserved_start: model.head
				reserved_size:  reserved_size
			}
		}
	}
	wrap_padding := model.capacity - model.head
	if wrap_padding + size <= available && size <= model.tail {
		return RingModelCandidate{
			offset:         0
			reserved_start: model.head
			reserved_size:  wrap_padding + size
		}
	}
	return none
}

fn (mut model RingReferenceModel) commit(allocation RingAllocation, candidate RingModelCandidate) {
	for distance in 0 .. candidate.reserved_size {
		index := (candidate.reserved_start + distance) % model.capacity
		assert !model.occupied[index]
		model.occupied[index] = true
	}
	model.records << RingModelRecord{
		allocation:     allocation
		reserved_start: candidate.reserved_start
		reserved_size:  candidate.reserved_size
	}
	model.head = (candidate.reserved_start + candidate.reserved_size) % model.capacity
	model.used += candidate.reserved_size
	model.payload += int(allocation.size)
	if model.used > model.peak_used {
		model.peak_used = model.used
	}
}

fn (mut model RingReferenceModel) release_oldest() RingAllocation {
	record := model.records[0]
	for distance in 0 .. record.reserved_size {
		index := (record.reserved_start + distance) % model.capacity
		assert model.occupied[index]
		model.occupied[index] = false
	}
	model.used -= record.reserved_size
	model.payload -= int(record.allocation.size)
	model.tail = (record.reserved_start + record.reserved_size) % model.capacity
	model.records.delete(0)
	if model.records.len == 0 {
		model.head = 0
		model.tail = 0
		model.used = 0
		model.payload = 0
	}
	return record.allocation
}

fn (model &RingReferenceModel) largest_contiguous_free() int {
	if model.records.len == 0 {
		return model.capacity
	}
	if model.used == model.capacity {
		return 0
	}
	if model.head < model.tail {
		return model.tail - model.head
	}
	end_space := model.capacity - model.head
	return if end_space > model.tail { end_space } else { model.tail }
}

fn assert_ring_matches_reference_model(allocator &RingAllocator, model &RingReferenceModel) {
	stats := allocator.stats()
	assert stats.capacity == u64(model.capacity)
	assert stats.used == u64(model.used)
	assert stats.payload == u64(model.payload)
	assert stats.padding == u64(model.used - model.payload)
	assert stats.free == u64(model.capacity - model.used)
	assert stats.peak_used == u64(model.peak_used)
	assert stats.allocation_count == model.records.len
	assert stats.largest_contiguous_free == u64(model.largest_contiguous_free())
	mut occupied_count := 0
	for is_occupied in model.occupied {
		if is_occupied {
			occupied_count++
		}
	}
	assert occupied_count == model.used
}

fn test_ring_allocator_matches_independent_fifo_model() {
	capacity := 127
	alignments := [1, 2, 3, 5, 7, 8, 16, 31]
	mut allocator := new_ring_allocator(u64(capacity))
	mut model := new_ring_reference_model(capacity)
	mut state := u32(0xf1f0cafe)

	for step in 0 .. 20_000 {
		state = state * 1_664_525 + 1_013_904_223
		if model.records.len > 0 && state % 4 == 0 {
			allocation := model.release_oldest()
			assert allocator.release(allocation)
		} else {
			size := 1 + int((state >> 12) % 29)
			alignment := alignments[int((state >> 24) % u32(alignments.len))]
			before := allocator.stats()
			if candidate := model.allocation_candidate(size, alignment) {
				allocation := allocator.allocate(u64(size), u64(alignment)) or {
					panic('model found offset ${candidate.offset}, allocator failed: ${err}')
				}
				assert allocation.offset == u64(candidate.offset)
				model.commit(allocation, candidate)
			} else {
				if allocation := allocator.allocate(u64(size), u64(alignment)) {
					assert false, 'allocator returned unexpected range at ${allocation.offset}'
				}
				assert allocator.stats() == before
			}
		}
		if step % 50 == 0 {
			assert_ring_matches_reference_model(allocator, &model)
		}
	}

	for model.records.len > 0 {
		allocation := model.release_oldest()
		assert allocator.release(allocation)
	}
	assert_ring_matches_reference_model(allocator, &model)
}

fn test_ring_allocator_allocation_ids_skip_zero_and_live_ids() {
	mut allocator := new_ring_allocator(4)
	first := allocator.allocate(1, 1) or { panic(err) }
	allocator.next_id = max_u64
	wrapped := allocator.allocate(1, 1) or { panic(err) }
	after_wrap := allocator.allocate(1, 1) or { panic(err) }

	assert first.id == 1
	assert wrapped.id == max_u64
	assert after_wrap.id == 2
	assert first.id != wrapped.id
	assert wrapped.id != after_wrap.id
}
