import antono2.memory

const workers = 4
const allocations_per_worker = 1_000

fn allocate_ranges(mut allocator memory.SynchronizedRangeAllocator, worker int, done chan bool) {
	for step in 0 .. allocations_per_worker {
		size := u64(8 + (worker + step) % 25)
		allocation := allocator.allocate(size, 16) or { continue }
		assert allocator.release(allocation)
	}
	done <- true
}

fn main() {
	mut allocator := memory.new_synchronized_range_allocator(64 * 1024)
	done := chan bool{cap: workers}
	mut threads := []thread{}
	for worker in 0 .. workers {
		threads << spawn allocate_ranges(mut allocator, worker, done)
	}
	for _ in 0 .. workers {
		assert <-done
	}
	threads.wait()
	stats := allocator.stats()
	assert stats.used == 0
	assert stats.largest_free_range == stats.capacity

	mut pages := memory.new_synchronized_buddy_allocator(1024, 16) or { panic(err) }
	page := pages.allocate(48, 64) or { panic(err) }
	assert page.block_size == 64
	assert pages.release(page)

	println('${workers} workers completed ${workers * allocations_per_worker} synchronized range allocations')
	println('synchronized buddy allocation coalesced back to ${pages.stats().largest_free_block} bytes')
}
