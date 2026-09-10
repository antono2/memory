module generic_pool

struct RingRecord {
	id             u64
	offset         u64
	size           u64
	reserved_start u64
	reserved_size  u64
}

// RingAllocation identifies one contiguous payload inside a RingAllocator.
// Allocations must be released in acquisition order.
pub struct RingAllocation {
	owner voidptr
	id    u64
pub:
	offset u64
	size   u64
}

// end returns the exclusive end offset of the contiguous payload.
pub fn (allocation RingAllocation) end() u64 {
	return allocation.offset + allocation.size
}

// RingStats describes active payload, alignment/wrap padding, and peak use.
pub struct RingStats {
pub:
	capacity                u64
	used                    u64
	payload                 u64
	padding                 u64
	free                    u64
	peak_used               u64
	allocation_count        int
	largest_contiguous_free u64
}

// RingAllocator manages FIFO allocations in a fixed-size circular range.
//
// Payloads never cross the end of the backing range. When allocation wraps,
// the unused suffix is tracked as padding and reclaimed with the allocation.
// This is suitable for staging buffers, streaming data, and resources retired
// in submission order. The allocator is not internally synchronized.
pub struct RingAllocator {
	capacity_ u64
mut:
	head         u64
	tail         u64
	used         u64
	payload      u64
	peak_used    u64
	records      []RingRecord
	first_record int
	next_id      u64 = 1
}

// new_ring_allocator creates a FIFO allocator over offsets [0, capacity).
pub fn new_ring_allocator(capacity u64) &RingAllocator {
	return &RingAllocator{
		capacity_: capacity
	}
}

// capacity returns the fixed size of the managed circular range.
pub fn (allocator &RingAllocator) capacity() u64 {
	return allocator.capacity_
}

// used_bytes returns live payload plus alignment and wrap padding.
pub fn (allocator &RingAllocator) used_bytes() u64 {
	return allocator.used
}

// free_bytes returns capacity not reserved by live allocations.
pub fn (allocator &RingAllocator) free_bytes() u64 {
	return allocator.capacity_ - allocator.used
}

// allocation_count returns the number of live FIFO allocations.
pub fn (allocator &RingAllocator) allocation_count() int {
	return allocator.records.len - allocator.first_record
}

// allocate reserves one aligned, contiguous payload. A failed request leaves
// the allocator unchanged.
pub fn (mut allocator RingAllocator) allocate(size u64, alignment u64) !RingAllocation {
	if size == 0 {
		return error('ring allocation size must be greater than zero')
	}
	if alignment == 0 {
		return error('ring allocation alignment must be greater than zero')
	}
	if size > allocator.capacity_ || allocator.capacity_ == 0 {
		return error('ring allocator is exhausted or fragmented')
	}
	if allocator.allocation_count() == 0 {
		allocator.head = 0
		allocator.tail = 0
		return allocator.commit_allocation(0, size, 0, size)
	}

	available := allocator.capacity_ - allocator.used
	if size > available {
		return error('ring allocator is exhausted or fragmented')
	}
	if allocator.head < allocator.tail {
		aligned_offset := align_forward(allocator.head, alignment) or {
			return error('ring allocator is exhausted or fragmented')
		}
		if aligned_offset <= allocator.tail && size <= allocator.tail - aligned_offset {
			padding := aligned_offset - allocator.head
			return allocator.commit_allocation(aligned_offset, size, allocator.head, padding + size)
		}
		return error('ring allocator is exhausted or fragmented')
	}

	aligned_offset := align_forward(allocator.head, alignment) or { allocator.capacity_ }
	if aligned_offset <= allocator.capacity_ && size <= allocator.capacity_ - aligned_offset {
		padding := aligned_offset - allocator.head
		if padding <= available && size <= available - padding {
			return allocator.commit_allocation(aligned_offset, size, allocator.head, padding + size)
		}
	}

	wrap_padding := allocator.capacity_ - allocator.head
	if wrap_padding <= available && size <= available - wrap_padding && size <= allocator.tail {
		return allocator.commit_allocation(0, size, allocator.head, wrap_padding + size)
	}
	return error('ring allocator is exhausted or fragmented')
}

// contains reports whether allocation is currently live in this allocator.
pub fn (allocator &RingAllocator) contains(allocation RingAllocation) bool {
	if allocation.owner != voidptr(allocator) || allocation.id == 0 {
		return false
	}
	for index in allocator.first_record .. allocator.records.len {
		record := allocator.records[index]
		if record.id == allocation.id {
			return record.offset == allocation.offset && record.size == allocation.size
		}
	}
	return false
}

// release retires the oldest live allocation. It returns false for an invalid
// allocation or a valid allocation presented out of FIFO order.
pub fn (mut allocator RingAllocator) release(allocation RingAllocation) bool {
	if allocation.owner != voidptr(allocator) || allocator.allocation_count() == 0 {
		return false
	}
	record := allocator.records[allocator.first_record]
	if record.id != allocation.id || record.offset != allocation.offset
		|| record.size != allocation.size {
		return false
	}
	allocator.used -= record.reserved_size
	allocator.payload -= record.size
	allocator.tail = advance_ring(record.reserved_start, record.reserved_size, allocator.capacity_)
	allocator.first_record++
	if allocator.allocation_count() == 0 {
		allocator.records.clear()
		allocator.first_record = 0
		allocator.head = 0
		allocator.tail = 0
		allocator.used = 0
		allocator.payload = 0
	} else if allocator.first_record >= 1024 && allocator.first_record * 2 >= allocator.records.len {
		allocator.records = allocator.records[allocator.first_record..].clone()
		allocator.first_record = 0
	}
	return true
}

// reset invalidates and releases every live allocation. Peak usage is retained.
pub fn (mut allocator RingAllocator) reset() {
	allocator.head = 0
	allocator.tail = 0
	allocator.used = 0
	allocator.payload = 0
	allocator.records.clear()
	allocator.first_record = 0
}

// stats returns current FIFO occupancy, padding, and peak use.
pub fn (allocator &RingAllocator) stats() RingStats {
	return RingStats{
		capacity:                allocator.capacity_
		used:                    allocator.used
		payload:                 allocator.payload
		padding:                 allocator.used - allocator.payload
		free:                    allocator.capacity_ - allocator.used
		peak_used:               allocator.peak_used
		allocation_count:        allocator.allocation_count()
		largest_contiguous_free: allocator.largest_contiguous_free()
	}
}

fn (mut allocator RingAllocator) commit_allocation(offset u64, size u64, reserved_start u64, reserved_size u64) RingAllocation {
	id := allocator.next_allocation_id()
	allocator.records << RingRecord{
		id:             id
		offset:         offset
		size:           size
		reserved_start: reserved_start
		reserved_size:  reserved_size
	}
	allocator.head = advance_ring(reserved_start, reserved_size, allocator.capacity_)
	allocator.used += reserved_size
	allocator.payload += size
	if allocator.used > allocator.peak_used {
		allocator.peak_used = allocator.used
	}
	return RingAllocation{
		owner:  allocator
		id:     id
		offset: offset
		size:   size
	}
}

fn (allocator &RingAllocator) largest_contiguous_free() u64 {
	if allocator.allocation_count() == 0 {
		return allocator.capacity_
	}
	if allocator.used == allocator.capacity_ {
		return 0
	}
	if allocator.head < allocator.tail {
		return allocator.tail - allocator.head
	}
	end_space := allocator.capacity_ - allocator.head
	return if end_space > allocator.tail { end_space } else { allocator.tail }
}

fn (mut allocator RingAllocator) next_allocation_id() u64 {
	for {
		id := allocator.next_id
		allocator.next_id++
		if allocator.next_id == 0 {
			allocator.next_id = 1
		}
		mut in_use := false
		for index in allocator.first_record .. allocator.records.len {
			if allocator.records[index].id == id {
				in_use = true
				break
			}
		}
		if id != 0 && !in_use {
			return id
		}
	}
	return 0
}

fn advance_ring(start u64, distance u64, capacity u64) u64 {
	until_end := capacity - start
	if distance < until_end {
		return start + distance
	}
	if distance == until_end {
		return 0
	}
	return distance - until_end
}
