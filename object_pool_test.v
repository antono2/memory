module memory

struct ReusableItem {
mut:
	value int
	label string
}

fn make_reusable_item() ReusableItem {
	return ReusableItem{
		value: 7
		label: 'factory'
	}
}

fn reset_reusable_item(_ ReusableItem) ReusableItem {
	return ReusableItem{}
}

fn test_object_pool_validates_configuration() {
	if _ := new_object_pool[ReusableItem](-1, 0, make_reusable_item, reset_reusable_item) {
		assert false, 'negative capacity must fail'
	} else {
		assert err.msg().contains('capacity')
	}
	if _ := new_object_pool[ReusableItem](2, -1, make_reusable_item, reset_reusable_item) {
		assert false, 'negative preallocation must fail'
	} else {
		assert err.msg().contains('negative')
	}
	if _ := new_object_pool[ReusableItem](2, 3, make_reusable_item, reset_reusable_item) {
		assert false, 'preallocation beyond capacity must fail'
	} else {
		assert err.msg().contains('capacity')
	}
}

fn test_object_pool_prewarms_lazily_creates_resets_and_reuses() {
	mut pool := new_object_pool[ReusableItem](3, 2, make_reusable_item, reset_reusable_item) or {
		panic(err)
	}
	assert pool.capacity() == 3
	assert pool.created_count() == 2
	assert pool.available_count() == 2
	assert pool.is_empty()

	first := pool.acquire() or { panic(err) }
	second := pool.acquire() or { panic(err) }
	assert pool.created_count() == 2
	assert pool.available_count() == 0
	assert (pool.get(first) or { panic('missing first value') }).value == 7

	third := pool.acquire() or { panic(err) }
	assert pool.created_count() == 3
	assert pool.is_full()
	if _ := pool.acquire() {
		assert false, 'acquisition beyond capacity must fail'
	} else {
		assert err.msg().contains('exhausted')
	}

	mut value := pool.get_mut(second) or { panic('missing mutable value') }
	value.value = 99
	value.label = 'used'
	second_release := pool.release(second)
	assert second_release
	double_release := pool.release(second)
	assert !double_release
	assert pool.available_count() == 1

	reused := pool.acquire() or { panic(err) }
	reused_value := pool.get(reused) or { panic('missing reused value') }
	assert reused_value.value == 0
	assert reused_value.label == ''
	assert pool.created_count() == 3

	assert pool.contains(first)
	assert pool.contains(third)
	assert pool.contains(reused)
}

fn test_object_pool_prewarm_and_release_all() {
	mut pool := new_object_pool[ReusableItem](4, 0, make_reusable_item, reset_reusable_item) or {
		panic(err)
	}
	pool.prewarm(3) or { panic(err) }
	assert pool.created_count() == 3
	assert pool.available_count() == 3
	pool.prewarm(2) or { panic(err) }
	assert pool.created_count() == 3

	if _ := pool.prewarm(5) {
		assert false, 'prewarm beyond capacity must fail'
	} else {
		assert err.msg().contains('capacity')
	}

	first := pool.acquire() or { panic(err) }
	second := pool.acquire() or { panic(err) }
	released := pool.release_all()
	assert released == 2
	assert pool.is_empty()
	assert pool.available_count() == 3
	assert !pool.contains(first)
	assert !pool.contains(second)
	released_again := pool.release_all()
	assert released_again == 0
}

fn test_object_pool_rejects_foreign_handles() {
	mut first_pool := new_object_pool[int](1, 0, fn () int {
		return 1
	}, fn (value int) int {
		return value
	}) or { panic(err) }
	mut second_pool := new_object_pool[int](1, 0, fn () int {
		return 2
	}, fn (value int) int {
		return value
	}) or { panic(err) }
	first := first_pool.acquire() or { panic(err) }
	second := second_pool.acquire() or { panic(err) }

	foreign_first := first_pool.release(second)
	assert !foreign_first
	foreign_second := second_pool.release(first)
	assert !foreign_second
	assert first_pool.contains(first)
	assert second_pool.contains(second)
}

fn test_object_pool_deterministic_lifecycle_stress() {
	capacity := 17
	mut pool := new_object_pool[ReusableItem](capacity, 3, make_reusable_item, reset_reusable_item) or {
		panic(err)
	}
	mut active := []Handle{cap: capacity}
	mut stale := []Handle{}
	mut state := u32(0x0b1ec700)

	for step in 0 .. 10_000 {
		state = state * 1_664_525 + 1_013_904_223
		if step > 0 && step % 211 == 0 {
			stale << active
			assert pool.release_all() == active.len
			active.clear()
		} else if active.len == capacity || (active.len > 0 && state % 3 == 0) {
			index := int((state >> 8) % u32(active.len))
			handle := active[index]
			assert pool.release(handle)
			assert !pool.release(handle)
			assert !pool.contains(handle)
			stale << handle
			active.delete(index)
		} else {
			handle := pool.acquire() or { panic(err) }
			mut item := pool.get_mut(handle) or { panic('new lease was rejected') }
			item.value = step
			item.label = 'active-${step}'
			active << handle
		}

		assert pool.len() == active.len
		assert pool.created_count() <= capacity
		assert pool.available_count() + pool.len() == pool.created_count()
		for handle in active {
			assert pool.contains(handle)
		}
		if stale.len > 0 {
			assert !pool.contains(stale[stale.len - 1])
		}
	}
}
