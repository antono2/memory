module generic_pool

struct TestItem {
mut:
	value int
	name  string
}

fn test_new_pool_validates_capacity() {
	pool := new_slot_pool[TestItem](3) or { panic(err) }
	assert pool.capacity() == 3
	assert pool.len() == 0
	assert pool.is_empty()
	assert !pool.is_full()

	empty := new_slot_pool[TestItem](0) or { panic(err) }
	assert empty.capacity() == 0
	assert empty.is_empty()
	assert empty.is_full()

	if _ := new_slot_pool[TestItem](-1) {
		assert false, 'negative capacity must fail'
	} else {
		assert err.msg().contains('negative')
	}
}

fn test_insert_get_mut_release_and_reuse() {
	mut pool := new_slot_pool[TestItem](2) or { panic(err) }
	first := pool.insert(TestItem{ value: 10, name: 'first' }) or { panic(err) }
	second := pool.insert(TestItem{ value: 20, name: 'second' }) or { panic(err) }

	assert pool.len() == 2
	assert pool.is_full()
	assert pool.contains(first)
	assert (pool.get(first) or { panic('missing first item') }).name == 'first'

	mut first_item := pool.get_mut(first) or { panic('missing mutable first item') }
	first_item.value = 11
	assert (pool.get(first) or { panic('missing modified first item') }).value == 11

	if _ := pool.insert(TestItem{}) {
		assert false, 'inserting into a full pool must fail'
	} else {
		assert err.msg().contains('full')
	}

	assert pool.release(first)
	assert !pool.release(first)
	assert !pool.contains(first)
	assert pool.get(first) == none
	assert pool.len() == 1

	replacement := pool.insert(TestItem{ value: 30, name: 'replacement' }) or { panic(err) }
	assert replacement.index == first.index
	assert replacement.generation != first.generation
	assert (pool.get(replacement) or { panic('missing replacement') }).value == 30
	assert pool.contains(second)
}

fn test_clear_invalidates_active_handles_without_changing_capacity() {
	mut pool := new_slot_pool[TestItem](3) or { panic(err) }
	first := pool.insert(TestItem{ value: 1 }) or { panic(err) }
	second := pool.insert(TestItem{ value: 2 }) or { panic(err) }

	pool.clear()

	assert pool.capacity() == 3
	assert pool.len() == 0
	assert pool.is_empty()
	assert !pool.contains(first)
	assert !pool.contains(second)
	assert pool.get(first) == none

	for i in 0 .. pool.capacity() {
		_ = pool.insert(TestItem{ value: i }) or { panic(err) }
	}
	assert pool.is_full()
}

fn test_forged_handles_are_rejected() {
	mut pool := new_slot_pool[TestItem](1) or { panic(err) }
	valid := pool.insert(TestItem{ value: 1 }) or { panic(err) }

	assert !pool.contains(Handle{
		index: -1
		generation: valid.generation
		owner: valid.owner
	})
	assert !pool.contains(Handle{
		index: 4
		generation: valid.generation
		owner: valid.owner
	})
	assert !pool.contains(Handle{
		index: valid.index
		generation: valid.generation + 1
		owner: valid.owner
	})
	assert !pool.release(Handle{
		index: valid.index
		generation: valid.generation + 1
		owner: valid.owner
	})
	assert pool.contains(valid)
}

fn test_handles_are_rejected_by_other_pools() {
	mut first_pool := new_slot_pool[int](1) or { panic(err) }
	mut second_pool := new_slot_pool[int](1) or { panic(err) }
	first := first_pool.insert(42) or { panic(err) }
	second := second_pool.insert(42) or { panic(err) }

	assert !first_pool.contains(second)
	assert !second_pool.contains(first)
	assert !first_pool.release(second)
	assert first_pool.release(first)
}

fn test_generation_skips_reserved_zero_after_wrap() {
	assert next_generation(max_u32) == 1
}

fn test_deterministic_insert_release_stress() {
	capacity := 32
	mut pool := new_slot_pool[int](capacity) or { panic(err) }
	mut active := []Handle{cap: capacity}
	mut state := u32(0x5eed1234)

	for step in 0 .. 5_000 {
		state = state * 1_664_525 + 1_013_904_223
		if active.len == 0 || (active.len < capacity && state & 1 == 0) {
			handle := pool.insert(step) or { panic(err) }
			active << handle
		} else {
			index := int(state % u32(active.len))
			handle := active[index]
			assert pool.release(handle)
			active.delete(index)
			assert !pool.contains(handle)
		}

		assert pool.len() == active.len
		mut seen := []bool{len: capacity}
		for handle in active {
			assert pool.contains(handle)
			assert !seen[handle.index]
			seen[handle.index] = true
		}
	}

	pool.clear()
	assert pool.is_empty()
	for value in 0 .. capacity {
		_ = pool.insert(value) or { panic(err) }
	}
	assert pool.is_full()
}
