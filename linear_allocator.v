module memory

// LinearAllocation identifies one aligned range from a LinearAllocator. It is
// valid until the allocator is reset.
pub struct LinearAllocation {
	owner      voidptr
	generation u64
pub:
	offset u64
	size   u64
}

// end returns the exclusive end offset of the allocation.
pub fn (allocation LinearAllocation) end() u64 {
	return allocation.offset + allocation.size
}

// LinearStats is a snapshot of cursor, payload, padding, and peak usage.
pub struct LinearStats {
pub:
	capacity         u64
	used             u64
	payload          u64
	padding          u64
	remaining        u64
	peak_used        u64
	allocation_count int
}

// LinearAllocator performs O(1) aligned bump allocation in a fixed-size range.
//
// It owns no backing memory and does not support individual release. reset()
// frees every range at once, making it suitable for frame, request, parser, and
// other phase-scoped temporary data. The allocator is not synchronized.
pub struct LinearAllocator {
	capacity_ u64
mut:
	cursor      u64
	payload     u64
	peak_used   u64
	allocations int
	generation  u64 = 1
}

// new_linear_allocator creates an allocator covering offsets [0, capacity).
pub fn new_linear_allocator(capacity u64) &LinearAllocator {
	return &LinearAllocator{
		capacity_: capacity
	}
}

// capacity returns the fixed size of the managed range.
pub fn (allocator &LinearAllocator) capacity() u64 {
	return allocator.capacity_
}

// used_bytes returns payload plus alignment padding consumed before the cursor.
pub fn (allocator &LinearAllocator) used_bytes() u64 {
	return allocator.cursor
}

// remaining_bytes returns the unconsumed range after the cursor.
pub fn (allocator &LinearAllocator) remaining_bytes() u64 {
	return allocator.capacity_ - allocator.cursor
}

// allocation_count returns the number of ranges allocated since the last reset.
pub fn (allocator &LinearAllocator) allocation_count() int {
	return allocator.allocations
}

// allocate advances the cursor and returns an aligned range. Alignment may be
// any positive integer. A failed request leaves the allocator unchanged.
pub fn (mut allocator LinearAllocator) allocate(size u64, alignment u64) !LinearAllocation {
	if size == 0 {
		return error('linear allocation size must be greater than zero')
	}
	if alignment == 0 {
		return error('linear allocation alignment must be greater than zero')
	}
	aligned_offset := align_forward(allocator.cursor, alignment) or {
		return error('linear allocator is exhausted')
	}
	if aligned_offset > allocator.capacity_ || size > allocator.capacity_ - aligned_offset {
		return error('linear allocator is exhausted')
	}
	allocator.cursor = aligned_offset + size
	allocator.payload += size
	allocator.allocations++
	if allocator.cursor > allocator.peak_used {
		allocator.peak_used = allocator.cursor
	}
	return LinearAllocation{
		owner:      allocator
		generation: allocator.generation
		offset:     aligned_offset
		size:       size
	}
}

// contains reports whether allocation belongs to the current generation and
// lies within the range consumed since the last reset.
pub fn (allocator &LinearAllocator) contains(allocation LinearAllocation) bool {
	if allocation.owner != voidptr(allocator) || allocation.generation != allocator.generation
		|| allocation.size == 0 || allocation.offset > allocator.cursor {
		return false
	}
	return allocation.size <= allocator.cursor - allocation.offset
}

// reset invalidates all allocations and returns the cursor to zero. The peak
// usage statistic is retained across resets.
pub fn (mut allocator LinearAllocator) reset() {
	allocator.cursor = 0
	allocator.payload = 0
	allocator.allocations = 0
	allocator.generation++
	if allocator.generation == 0 {
		allocator.generation = 1
	}
}

// stats returns current and peak allocator usage.
pub fn (allocator &LinearAllocator) stats() LinearStats {
	return LinearStats{
		capacity:         allocator.capacity_
		used:             allocator.cursor
		payload:          allocator.payload
		padding:          allocator.cursor - allocator.payload
		remaining:        allocator.capacity_ - allocator.cursor
		peak_used:        allocator.peak_used
		allocation_count: allocator.allocations
	}
}
