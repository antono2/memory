module mem

struct FreeRange {
mut:
	offset u64
	size   u64
}

struct AllocatedRange {
	offset u64
	size   u64
}

// RangeAllocation identifies one aligned subrange owned by a RangeAllocator.
// offset and size can be used directly when binding or indexing the backing
// resource; the ownership token remains private.
pub struct RangeAllocation {
	owner voidptr
	id    u64
pub:
	offset u64
	size   u64
}

// end returns the exclusive end offset of the allocation.
pub fn (allocation RangeAllocation) end() u64 {
	return allocation.offset + allocation.size
}

// RangeStats is a snapshot of allocator occupancy and fragmentation.
pub struct RangeStats {
pub:
	capacity           u64
	used               u64
	free               u64
	allocation_count   int
	free_range_count   int
	largest_free_range u64
}

// RangeAllocator manages aligned offsets inside one fixed-size resource.
//
// It owns no memory itself. The offsets can refer to bytes in a host buffer,
// mapped file, shared-memory object, GPU buffer, or Vulkan device-memory block.
// Allocation uses deterministic first fit; release reinserts and coalesces the
// returned range. The allocator is not internally synchronized.
pub struct RangeAllocator {
	capacity_ u64
mut:
	free_ranges []FreeRange
	allocations map[u64]AllocatedRange
	next_id     u64 = 1
	used        u64
}

// new_range_allocator creates an allocator covering offsets [0, capacity).
pub fn new_range_allocator(capacity u64) &RangeAllocator {
	mut free_ranges := []FreeRange{}
	if capacity > 0 {
		free_ranges << FreeRange{
			size: capacity
		}
	}
	return &RangeAllocator{
		capacity_:   capacity
		free_ranges: free_ranges
		allocations: map[u64]AllocatedRange{}
	}
}

// capacity returns the fixed size of the managed resource.
pub fn (allocator &RangeAllocator) capacity() u64 {
	return allocator.capacity_
}

// used_bytes returns the sum of all live allocation sizes.
pub fn (allocator &RangeAllocator) used_bytes() u64 {
	return allocator.used
}

// free_bytes returns the number of bytes not currently allocated.
pub fn (allocator &RangeAllocator) free_bytes() u64 {
	return allocator.capacity_ - allocator.used
}

// allocation_count returns the number of live allocations.
pub fn (allocator &RangeAllocator) allocation_count() int {
	return allocator.allocations.len
}

// allocate reserves size bytes at an offset divisible by alignment.
// Alignment may be any positive integer. It returns an error for zero values or
// when no individual free range can satisfy the request.
pub fn (mut allocator RangeAllocator) allocate(size u64, alignment u64) !RangeAllocation {
	if size == 0 {
		return error('range allocation size must be greater than zero')
	}
	if alignment == 0 {
		return error('range allocation alignment must be greater than zero')
	}
	for index, free_range in allocator.free_ranges {
		aligned_offset := align_forward(free_range.offset, alignment) or { continue }
		padding := aligned_offset - free_range.offset
		if padding > free_range.size || size > free_range.size - padding {
			continue
		}
		suffix_size := free_range.size - padding - size
		allocator.consume_free_range(index, aligned_offset, size, padding, suffix_size)

		id := allocator.next_allocation_id()
		allocator.allocations[id] = AllocatedRange{
			offset: aligned_offset
			size:   size
		}
		allocator.used += size
		return RangeAllocation{
			owner:  allocator
			id:     id
			offset: aligned_offset
			size:   size
		}
	}
	return error('range allocator is exhausted or fragmented')
}

// contains reports whether allocation is currently live and belongs to this
// allocator.
pub fn (allocator &RangeAllocator) contains(allocation RangeAllocation) bool {
	if allocation.owner != voidptr(allocator) || allocation.id == 0
		|| allocation.id !in allocator.allocations {
		return false
	}
	record := allocator.allocations[allocation.id]
	return record.offset == allocation.offset && record.size == allocation.size
}

// release returns a live allocation to the free-range set. It returns false for
// stale, forged, foreign, or already released allocations.
pub fn (mut allocator RangeAllocator) release(allocation RangeAllocation) bool {
	if !allocator.contains(allocation) {
		return false
	}
	allocator.allocations.delete(allocation.id)
	allocator.used -= allocation.size
	allocator.insert_free_range(FreeRange{
		offset: allocation.offset
		size:   allocation.size
	})
	return true
}

// reset releases every allocation and restores one contiguous free range.
// Previously returned allocations become stale.
pub fn (mut allocator RangeAllocator) reset() {
	allocator.allocations.clear()
	allocator.free_ranges.clear()
	if allocator.capacity_ > 0 {
		allocator.free_ranges << FreeRange{
			size: allocator.capacity_
		}
	}
	allocator.used = 0
}

// stats returns current capacity, occupancy, and free-range information.
pub fn (allocator &RangeAllocator) stats() RangeStats {
	mut largest := u64(0)
	for free_range in allocator.free_ranges {
		if free_range.size > largest {
			largest = free_range.size
		}
	}
	return RangeStats{
		capacity:           allocator.capacity_
		used:               allocator.used
		free:               allocator.capacity_ - allocator.used
		allocation_count:   allocator.allocations.len
		free_range_count:   allocator.free_ranges.len
		largest_free_range: largest
	}
}

fn (mut allocator RangeAllocator) consume_free_range(index int, aligned_offset u64, allocation_size u64, prefix_size u64, suffix_size u64) {
	if prefix_size == 0 && suffix_size == 0 {
		allocator.remove_free_range(index)
	} else if prefix_size == 0 {
		allocator.free_ranges[index].offset = aligned_offset + allocation_size
		allocator.free_ranges[index].size = suffix_size
	} else if suffix_size == 0 {
		allocator.free_ranges[index].size = prefix_size
	} else {
		allocator.free_ranges[index].size = prefix_size
		allocator.free_ranges.insert(index + 1, FreeRange{
			offset: aligned_offset + allocation_size
			size:   suffix_size
		})
	}
}

fn (mut allocator RangeAllocator) insert_free_range(free_range FreeRange) {
	mut index := 0
	for index < allocator.free_ranges.len && allocator.free_ranges[index].offset < free_range.offset {
		index++
	}
	allocator.free_ranges.insert(index, free_range)
	allocator.coalesce_free_range_at(index)
}

fn (mut allocator RangeAllocator) coalesce_free_range_at(index int) {
	mut merged_index := index
	if merged_index > 0 {
		previous_index := merged_index - 1
		if allocator.free_ranges[previous_index].offset + allocator.free_ranges[previous_index].size == allocator.free_ranges[merged_index].offset {
			allocator.free_ranges[previous_index].size += allocator.free_ranges[merged_index].size
			allocator.remove_free_range(merged_index)
			merged_index = previous_index
		}
	}
	if merged_index + 1 < allocator.free_ranges.len {
		next_index := merged_index + 1
		if allocator.free_ranges[merged_index].offset + allocator.free_ranges[merged_index].size == allocator.free_ranges[next_index].offset {
			allocator.free_ranges[merged_index].size += allocator.free_ranges[next_index].size
			allocator.remove_free_range(next_index)
		}
	}
}

fn (mut allocator RangeAllocator) remove_free_range(index int) {
	for i in index .. allocator.free_ranges.len - 1 {
		allocator.free_ranges[i] = allocator.free_ranges[i + 1]
	}
	allocator.free_ranges.trim(allocator.free_ranges.len - 1)
}

fn (mut allocator RangeAllocator) next_allocation_id() u64 {
	for {
		id := allocator.next_id
		allocator.next_id++
		if allocator.next_id == 0 {
			allocator.next_id = 1
		}
		if id != 0 && id !in allocator.allocations {
			return id
		}
	}
	return 0
}
