module memory

const synchronized_worker_count = 8
const synchronized_worker_iterations = 2_000

fn synchronized_range_hold_worker(mut allocator SynchronizedRangeAllocator, ready chan RangeAllocation, release chan bool, done chan bool) {
	allocation := allocator.allocate(8, 8) or { panic(err) }
	ready <- allocation
	_ := <-release
	done <- allocator.release(allocation)
}

fn synchronized_buddy_hold_worker(mut allocator SynchronizedBuddyAllocator, ready chan BuddyAllocation, release chan bool, done chan bool) {
	allocation := allocator.allocate(9, 16) or { panic(err) }
	ready <- allocation
	_ := <-release
	done <- allocator.release(allocation)
}

fn synchronized_range_churn_worker(mut allocator SynchronizedRangeAllocator, worker int, done chan bool) {
	for step in 0 .. synchronized_worker_iterations {
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

fn synchronized_buddy_churn_worker(mut allocator SynchronizedBuddyAllocator, worker int, done chan bool) {
	for step in 0 .. synchronized_worker_iterations {
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

fn test_synchronized_range_allocator_holds_distinct_live_ranges() {
	mut allocator := new_synchronized_range_allocator(synchronized_worker_count * 8)
	assert allocator.capacity() == synchronized_worker_count * 8
	assert allocator.used_bytes() == 0
	assert allocator.free_bytes() == synchronized_worker_count * 8
	assert allocator.allocation_count() == 0
	ready := chan RangeAllocation{cap: synchronized_worker_count}
	release := chan bool{cap: synchronized_worker_count}
	done := chan bool{cap: synchronized_worker_count}

	mut threads := []thread{}
	for _ in 0 .. synchronized_worker_count {
		threads << spawn synchronized_range_hold_worker(mut allocator, ready, release, done)
	}
	mut allocations := []RangeAllocation{cap: synchronized_worker_count}
	for _ in 0 .. synchronized_worker_count {
		allocations << <-ready
	}
	for index, allocation in allocations {
		assert allocator.contains(allocation)
		for other in allocations[index + 1..] {
			assert allocation.end() <= other.offset || other.end() <= allocation.offset
		}
	}
	assert allocator.stats().used == synchronized_worker_count * 8
	assert allocator.used_bytes() == synchronized_worker_count * 8
	assert allocator.allocation_count() == synchronized_worker_count

	for _ in 0 .. synchronized_worker_count {
		release <- true
	}
	for _ in 0 .. synchronized_worker_count {
		assert <-done
	}
	threads.wait()
	assert allocator.stats().used == 0
	assert allocator.stats().largest_free_range == synchronized_worker_count * 8
}

fn test_synchronized_buddy_allocator_holds_distinct_live_blocks() {
	mut allocator := new_synchronized_buddy_allocator(128, 8) or { panic(err) }
	assert allocator.capacity() == 128
	assert allocator.min_block_size() == 8
	assert allocator.used_bytes() == 0
	assert allocator.payload_bytes() == 0
	assert allocator.free_bytes() == 128
	assert allocator.allocation_count() == 0
	ready := chan BuddyAllocation{cap: synchronized_worker_count}
	release := chan bool{cap: synchronized_worker_count}
	done := chan bool{cap: synchronized_worker_count}

	mut threads := []thread{}
	for _ in 0 .. synchronized_worker_count {
		threads << spawn synchronized_buddy_hold_worker(mut allocator, ready, release, done)
	}
	mut allocations := []BuddyAllocation{cap: synchronized_worker_count}
	for _ in 0 .. synchronized_worker_count {
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
	assert allocator.payload_bytes() == synchronized_worker_count * 9
	assert allocator.allocation_count() == synchronized_worker_count

	for _ in 0 .. synchronized_worker_count {
		release <- true
	}
	for _ in 0 .. synchronized_worker_count {
		assert <-done
	}
	threads.wait()
	assert allocator.stats().reserved == 0
	assert allocator.stats().largest_free_block == 128
}

fn test_synchronized_allocators_remain_consistent_under_churn() {
	mut ranges := new_synchronized_range_allocator(4096)
	mut buddies := new_synchronized_buddy_allocator(4096, 8) or { panic(err) }
	range_done := chan bool{cap: synchronized_worker_count}
	buddy_done := chan bool{cap: synchronized_worker_count}

	mut range_threads := []thread{}
	mut buddy_threads := []thread{}
	for worker in 0 .. synchronized_worker_count {
		range_threads << spawn synchronized_range_churn_worker(mut ranges, worker, range_done)
		buddy_threads << spawn synchronized_buddy_churn_worker(mut buddies, worker, buddy_done)
	}
	for _ in 0 .. synchronized_worker_count {
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

fn test_synchronized_buddy_allocator_validates_configuration() {
	if _ := new_synchronized_buddy_allocator(48, 8) {
		assert false, 'non-power-of-two capacity must fail'
	} else {
		assert err.msg().contains('power of two')
	}
}
