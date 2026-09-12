module concurrent

import antono2.memory

const worker_count = 8
const worker_iterations = 2_000

fn range_hold_worker(mut allocator RangeAllocator, ready chan memory.RangeAllocation, release chan bool, done chan bool) {
	allocation := allocator.allocate(8, 8) or { panic(err) }
	ready <- allocation
	_ := <-release
	done <- allocator.release(allocation)
}

fn buddy_hold_worker(mut allocator BuddyAllocator, ready chan memory.BuddyAllocation, release chan bool, done chan bool) {
	allocation := allocator.allocate(9, 16) or { panic(err) }
	ready <- allocation
	_ := <-release
	done <- allocator.release(allocation)
}

fn range_churn_worker(mut allocator RangeAllocator, worker int, done chan bool) {
	for step in 0 .. worker_iterations {
		size := u64(1 + (worker * 17 + step * 13) % 31)
		alignment := u64(1) << u32((worker + step) % 5)
		allocation := allocator.allocate(size, alignment) or { continue }
		if !allocator.contains(allocation) || !allocator.release(allocation) {
			done <- false
			return
		}
	}
	done <- true
}

fn buddy_churn_worker(mut allocator BuddyAllocator, worker int, done chan bool) {
	for step in 0 .. worker_iterations {
		size := u64(1 + (worker * 19 + step * 11) % 63)
		alignment := u64(1) << u32((worker + step) % 6)
		allocation := allocator.allocate(size, alignment) or { continue }
		if !allocator.contains(allocation) || !allocator.release(allocation) {
			done <- false
			return
		}
	}
	done <- true
}

fn test_concurrent_range_allocator_holds_distinct_live_ranges() {
	mut allocator := new_range_allocator(worker_count * 8)
	assert allocator.capacity() == worker_count * 8
	assert allocator.used_bytes() == 0
	assert allocator.free_bytes() == worker_count * 8
	assert allocator.allocation_count() == 0
	ready := chan memory.RangeAllocation{cap: worker_count}
	release := chan bool{cap: worker_count}
	done := chan bool{cap: worker_count}

	mut threads := []thread{}
	for _ in 0 .. worker_count {
		threads << spawn range_hold_worker(mut allocator, ready, release, done)
	}
	mut allocations := []memory.RangeAllocation{cap: worker_count}
	for _ in 0 .. worker_count {
		allocations << <-ready
	}
	for index, allocation in allocations {
		assert allocator.contains(allocation)
		for other in allocations[index + 1..] {
			assert allocation.end() <= other.offset || other.end() <= allocation.offset
		}
	}
	assert allocator.stats().used == worker_count * 8
	assert allocator.used_bytes() == worker_count * 8
	assert allocator.allocation_count() == worker_count

	for _ in 0 .. worker_count {
		release <- true
	}
	for _ in 0 .. worker_count {
		assert <-done
	}
	threads.wait()
	assert allocator.stats().used == 0
	assert allocator.stats().largest_free_range == worker_count * 8
}

fn test_concurrent_buddy_allocator_holds_distinct_live_blocks() {
	mut allocator := new_buddy_allocator(128, 8) or { panic(err) }
	assert allocator.capacity() == 128
	assert allocator.min_block_size() == 8
	assert allocator.used_bytes() == 0
	assert allocator.payload_bytes() == 0
	assert allocator.free_bytes() == 128
	assert allocator.allocation_count() == 0
	ready := chan memory.BuddyAllocation{cap: worker_count}
	release := chan bool{cap: worker_count}
	done := chan bool{cap: worker_count}

	mut threads := []thread{}
	for _ in 0 .. worker_count {
		threads << spawn buddy_hold_worker(mut allocator, ready, release, done)
	}
	mut allocations := []memory.BuddyAllocation{cap: worker_count}
	for _ in 0 .. worker_count {
		allocations << <-ready
	}
	for index, allocation in allocations {
		assert allocation.block_size == 16
		assert allocator.contains(allocation)
		for other in allocations[index + 1..] {
			assert allocation.block_end() <= other.offset || other.block_end() <= allocation.offset
		}
	}
	assert allocator.stats().reserved == 128
	assert allocator.used_bytes() == 128
	assert allocator.payload_bytes() == worker_count * 9
	assert allocator.allocation_count() == worker_count

	for _ in 0 .. worker_count {
		release <- true
	}
	for _ in 0 .. worker_count {
		assert <-done
	}
	threads.wait()
	assert allocator.stats().reserved == 0
	assert allocator.stats().largest_free_block == 128
}

fn test_concurrent_allocators_remain_consistent_under_churn() {
	mut ranges := new_range_allocator(4096)
	mut buddies := new_buddy_allocator(4096, 8) or { panic(err) }
	range_done := chan bool{cap: worker_count}
	buddy_done := chan bool{cap: worker_count}

	mut range_threads := []thread{}
	mut buddy_threads := []thread{}
	for worker in 0 .. worker_count {
		range_threads << spawn range_churn_worker(mut ranges, worker, range_done)
		buddy_threads << spawn buddy_churn_worker(mut buddies, worker, buddy_done)
	}
	for _ in 0 .. worker_count {
		assert <-range_done
		assert <-buddy_done
	}
	range_threads.wait()
	buddy_threads.wait()

	range_stats := ranges.stats()
	assert range_stats.used == 0
	assert range_stats.allocation_count == 0
	assert range_stats.free_range_count == 1
	assert range_stats.largest_free_range == range_stats.capacity

	buddy_stats := buddies.stats()
	assert buddy_stats.reserved == 0
	assert buddy_stats.payload == 0
	assert buddy_stats.allocation_count == 0
	assert buddy_stats.largest_free_block == buddy_stats.capacity
}

fn test_concurrent_buddy_allocator_validates_configuration() {
	if _ := new_buddy_allocator(48, 8) {
		assert false, 'non-power-of-two capacity must fail'
	} else {
		assert err.msg().contains('power of two')
	}
}
