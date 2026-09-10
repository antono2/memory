module mem

const buddy_node_free = u8(0)
const buddy_node_split = u8(1)
const buddy_node_full = u8(2)

struct BuddyRecord {
	node_index int
	offset     u64
	size       u64
	block_size u64
}

struct BuddyCandidate {
	node_index int
	offset     u64
}

// BuddyAllocation identifies one live allocation and the power-of-two block
// reserved for it. size is the requested payload; block_size includes internal
// fragmentation and determines the allocation's reserved range.
pub struct BuddyAllocation {
	owner voidptr
	id    u64
pub:
	offset     u64
	size       u64
	block_size u64
}

// end returns the exclusive end of the requested payload.
pub fn (allocation BuddyAllocation) end() u64 {
	return allocation.offset + allocation.size
}

// block_end returns the exclusive end of the reserved buddy block.
pub fn (allocation BuddyAllocation) block_end() u64 {
	return allocation.offset + allocation.block_size
}

// BuddyStats describes payload, reserved space, internal fragmentation, and
// the largest block that can currently be allocated without releasing memory.
pub struct BuddyStats {
pub:
	capacity               u64
	reserved               u64
	payload                u64
	internal_fragmentation u64
	free                   u64
	peak_reserved          u64
	allocation_count       int
	largest_free_block     u64
}

// BuddyAllocator manages a power-of-two arena as a binary tree of blocks.
//
// Requests are rounded up to the smallest block that satisfies size,
// alignment, and minimum_block_size. Both capacity and minimum_block_size must
// be powers of two, and requested alignments must also be powers of two.
// Allocation searches deterministically from lower to higher offsets. Release
// coalesces free buddies while walking back to the root. The allocator owns no
// backing memory and is not internally synchronized.
pub struct BuddyAllocator {
	capacity_          u64
	minimum_block_size u64
mut:
	nodes         []u8
	allocations   map[u64]BuddyRecord
	next_id       u64 = 1
	reserved      u64
	payload       u64
	peak_reserved u64
}

// new_buddy_allocator creates a buddy allocator over [0, capacity).
pub fn new_buddy_allocator(capacity u64, minimum_block_size u64) !&BuddyAllocator {
	if capacity == 0 || !is_power_of_two(capacity) {
		return error('buddy allocator capacity must be a non-zero power of two')
	}
	if minimum_block_size == 0 || !is_power_of_two(minimum_block_size) {
		return error('buddy allocator minimum block size must be a non-zero power of two')
	}
	if minimum_block_size > capacity {
		return error('buddy allocator minimum block size exceeds capacity')
	}
	leaf_count := capacity / minimum_block_size
	if leaf_count > u64(max_int) / 2 {
		return error('buddy allocator capacity requires too many bookkeeping nodes')
	}
	node_count := int(leaf_count * 2 - 1)
	return &BuddyAllocator{
		capacity_:          capacity
		minimum_block_size: minimum_block_size
		nodes:              []u8{len: node_count}
		allocations:        map[u64]BuddyRecord{}
	}
}

// capacity returns the fixed size of the managed arena.
pub fn (allocator &BuddyAllocator) capacity() u64 {
	return allocator.capacity_
}

// min_block_size returns the smallest block this allocator can reserve.
pub fn (allocator &BuddyAllocator) min_block_size() u64 {
	return allocator.minimum_block_size
}

// used_bytes returns bytes reserved by live buddy blocks.
pub fn (allocator &BuddyAllocator) used_bytes() u64 {
	return allocator.reserved
}

// payload_bytes returns the sum of requested live allocation sizes.
pub fn (allocator &BuddyAllocator) payload_bytes() u64 {
	return allocator.payload
}

// free_bytes returns capacity not reserved by live buddy blocks.
pub fn (allocator &BuddyAllocator) free_bytes() u64 {
	return allocator.capacity_ - allocator.reserved
}

// allocation_count returns the number of live allocations.
pub fn (allocator &BuddyAllocator) allocation_count() int {
	return allocator.allocations.len
}

// allocate reserves a power-of-two block for size bytes. Alignment must be a
// power of two. Failed requests leave the allocator unchanged.
pub fn (mut allocator BuddyAllocator) allocate(size u64, alignment u64) !BuddyAllocation {
	if size == 0 {
		return error('buddy allocation size must be greater than zero')
	}
	if alignment == 0 || !is_power_of_two(alignment) {
		return error('buddy allocation alignment must be a non-zero power of two')
	}
	mut block_size := allocator.minimum_block_size
	required := if size > alignment { size } else { alignment }
	for block_size < required {
		if block_size > allocator.capacity_ / 2 {
			return error('buddy allocator is exhausted')
		}
		block_size *= 2
	}
	if block_size > allocator.capacity_ {
		return error('buddy allocator is exhausted')
	}

	candidate := allocator.allocate_node(0, 0, allocator.capacity_, block_size) or {
		return error('buddy allocator is exhausted or fragmented')
	}
	id := allocator.next_allocation_id()
	allocator.allocations[id] = BuddyRecord{
		node_index: candidate.node_index
		offset:     candidate.offset
		size:       size
		block_size: block_size
	}
	allocator.reserved += block_size
	allocator.payload += size
	if allocator.reserved > allocator.peak_reserved {
		allocator.peak_reserved = allocator.reserved
	}
	return BuddyAllocation{
		owner:      allocator
		id:         id
		offset:     candidate.offset
		size:       size
		block_size: block_size
	}
}

// contains reports whether allocation is live and belongs to this allocator.
pub fn (allocator &BuddyAllocator) contains(allocation BuddyAllocation) bool {
	if allocation.owner != voidptr(allocator) || allocation.id == 0
		|| allocation.id !in allocator.allocations {
		return false
	}
	record := allocator.allocations[allocation.id]
	return record.offset == allocation.offset && record.size == allocation.size
		&& record.block_size == allocation.block_size
}

// release returns a live allocation and coalesces every completely free pair
// of buddy blocks. Invalid, foreign, forged, and stale allocations are rejected.
pub fn (mut allocator BuddyAllocator) release(allocation BuddyAllocation) bool {
	if !allocator.contains(allocation) {
		return false
	}
	record := allocator.allocations[allocation.id]
	allocator.allocations.delete(allocation.id)
	allocator.reserved -= record.block_size
	allocator.payload -= record.size
	allocator.nodes[record.node_index] = buddy_node_free
	mut node_index := record.node_index
	for node_index > 0 {
		node_index = (node_index - 1) / 2
		allocator.refresh_node(node_index)
	}
	return true
}

// reset releases every allocation and restores one free root block. Peak
// reserved bytes are retained.
pub fn (mut allocator BuddyAllocator) reset() {
	for index in 0 .. allocator.nodes.len {
		allocator.nodes[index] = buddy_node_free
	}
	allocator.allocations.clear()
	allocator.reserved = 0
	allocator.payload = 0
}

// stats returns current and peak buddy-allocation occupancy.
pub fn (allocator &BuddyAllocator) stats() BuddyStats {
	return BuddyStats{
		capacity:               allocator.capacity_
		reserved:               allocator.reserved
		payload:                allocator.payload
		internal_fragmentation: allocator.reserved - allocator.payload
		free:                   allocator.capacity_ - allocator.reserved
		peak_reserved:          allocator.peak_reserved
		allocation_count:       allocator.allocations.len
		largest_free_block:     allocator.largest_free_block_at(0, allocator.capacity_)
	}
}

fn (mut allocator BuddyAllocator) allocate_node(node_index int, offset u64, node_size u64, target_size u64) ?BuddyCandidate {
	state := allocator.nodes[node_index]
	if state == buddy_node_full || node_size < target_size {
		return none
	}
	if node_size == target_size {
		if state != buddy_node_free {
			return none
		}
		allocator.nodes[node_index] = buddy_node_full
		return BuddyCandidate{
			node_index: node_index
			offset:     offset
		}
	}
	if state == buddy_node_free {
		allocator.nodes[node_index] = buddy_node_split
	}
	half_size := node_size / 2
	left_index := node_index * 2 + 1
	if candidate := allocator.allocate_node(left_index, offset, half_size, target_size) {
		allocator.refresh_node(node_index)
		return candidate
	}
	right_index := left_index + 1
	if candidate := allocator.allocate_node(right_index, offset + half_size, half_size, target_size) {
		allocator.refresh_node(node_index)
		return candidate
	}
	allocator.refresh_node(node_index)
	return none
}

fn (mut allocator BuddyAllocator) refresh_node(node_index int) {
	left_index := node_index * 2 + 1
	right_index := left_index + 1
	left := allocator.nodes[left_index]
	right := allocator.nodes[right_index]
	allocator.nodes[node_index] = if left == buddy_node_free && right == buddy_node_free {
		buddy_node_free
	} else if left == buddy_node_full && right == buddy_node_full {
		buddy_node_full
	} else {
		buddy_node_split
	}
}

fn (allocator &BuddyAllocator) largest_free_block_at(node_index int, node_size u64) u64 {
	state := allocator.nodes[node_index]
	if state == buddy_node_free {
		return node_size
	}
	if state == buddy_node_full || node_size == allocator.minimum_block_size {
		return 0
	}
	half_size := node_size / 2
	left := allocator.largest_free_block_at(node_index * 2 + 1, half_size)
	right := allocator.largest_free_block_at(node_index * 2 + 2, half_size)
	return if left > right { left } else { right }
}

fn (mut allocator BuddyAllocator) next_allocation_id() u64 {
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

fn is_power_of_two(value u64) bool {
	return value != 0 && value & (value - 1) == 0
}
