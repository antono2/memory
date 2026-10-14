// Checks caller-owned handle snapshots across holes, reuse and invalidation.
module memory

fn test_slot_handles_into_replaces_and_reuses_destination() {
	mut pool := new_slot_pool[int](4) or { panic(err) }
	first := pool.insert(10) or { panic(err) }
	second := pool.insert(20) or { panic(err) }
	third := pool.insert(30) or { panic(err) }
	mut destination := []Handle{cap: 4}
	storage := destination.data
	capacity := destination.cap
	pool.handles_into(mut destination)
	assert destination == pool.handles()
	assert destination.len == 3
	assert pool.release(second)
	pool.handles_into(mut destination)
	assert destination == pool.handles()
	assert destination.len == 2
	assert second !in destination
	assert !pool.contains(second)
	reused := pool.insert(40) or { panic(err) }
	pool.handles_into(mut destination)
	assert reused in destination
	assert first in destination && third in destination
	assert destination.data == storage
	assert destination.cap == capacity
	snapshot := destination.clone()
	pool.clear()
	assert snapshot.len == 3
	for handle in snapshot {
		assert !pool.contains(handle)
	}
	pool.handles_into(mut destination)
	assert destination.len == 0
	assert destination.data == storage
}

fn test_handles_into_grows_and_handles_zero_capacity() {
	mut pool := new_slot_pool[int](2) or { panic(err) }
	_ := pool.insert(1) or { panic(err) }
	_ := pool.insert(2) or { panic(err) }
	mut destination := []Handle{}
	pool.handles_into(mut destination)
	assert destination == pool.handles()
	mut empty := new_slot_pool[int](0) or { panic(err) }
	empty.handles_into(mut destination)
	assert destination.len == 0
}

fn test_object_handles_into_contains_only_current_own_leases() {
	mut pool := new_object_pool[int](3, 2, fn () int {
		return 0
	}, fn (_ int) int {
		return 0
	}) or { panic(err) }
	mut foreign_pool := new_slot_pool[int](1) or { panic(err) }
	foreign := foreign_pool.insert(9) or { panic(err) }
	first := pool.acquire() or { panic(err) }
	second := pool.acquire() or { panic(err) }
	mut destination := []Handle{cap: 3}
	destination << foreign
	storage := destination.data
	pool.handles_into(mut destination)
	assert destination == pool.handles()
	assert foreign !in destination
	assert !pool.contains(foreign)
	assert pool.release(first)
	assert !pool.release(first)
	reused := pool.acquire() or { panic(err) }
	pool.handles_into(mut destination)
	assert first !in destination
	assert reused in destination && second in destination
	assert destination.data == storage
	assert pool.release_all() == 2
	pool.handles_into(mut destination)
	assert destination.len == 0
	assert destination.data == storage
}
