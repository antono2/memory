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
