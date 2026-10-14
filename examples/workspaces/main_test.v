// Verifies actual backing-array reuse and independent live workspace leases.
module main

import antono2.memory

fn test_workspace_reuse_isolation_and_owned_results() {
	mut pool := memory.new_object_pool[Workspace](2, 2, make_workspace, reset_workspace) or {
		panic(err)
	}
	first := pool.acquire() or { panic(err) }
	second := pool.acquire() or { panic(err) }
	mut a := pool.get_mut(first) or { panic('missing a') }
	mut b := pool.get_mut(second) or { panic('missing b') }
	a_storage := a.storage.bytes.data
	b_storage := b.storage.bytes.data
	index_storage := a.storage.indices.data
	visible_storage := a.storage.visible.data
	assert a_storage != b_storage
	_ := prepare(mut a, 16, 42) or { panic(err) }
	owned := a.storage.bytes.clone()
	_ := prepare(mut b, 32, 70) or { panic(err) }
	assert a.storage.bytes == owned
	assert a.storage.bytes.data == a_storage
	if _ := prepare(mut a, max_items + 1, 0) {
		assert false
	}
	assert a.storage.bytes == owned
	assert pool.release(first)
	assert !pool.release(first)
	assert !pool.contains(first)
	for iteration in 0 .. 1000 {
		handle := pool.acquire() or { panic(err) }
		mut reused := pool.get_mut(handle) or { panic('missing reused workspace') }
		assert reused.storage.bytes.len == 0
		assert reused.storage.indices.len == 0
		assert reused.storage.visible.len == 0
		assert reused.storage.bytes.data == a_storage
		assert reused.storage.indices.data == index_storage
		assert reused.storage.visible.data == visible_storage
		_ := prepare(mut reused, iteration % (max_items + 1), u32(iteration)) or { panic(err) }
		assert pool.release(handle)
	}
	assert pool.created_count() == 2
	assert owned.len == 64
	assert owned[0] == 42
	assert b.storage.bytes.data == b_storage
	assert b.storage.bytes.len == 128
	assert pool.release(second)
}

fn test_workspace_error_path_returns_lease_and_results_match() {
	mut pool := memory.new_object_pool[Workspace](1, 1, make_workspace, reset_workspace) or {
		panic(err)
	}
	mut retained := make_workspace()
	for count in [0, 1, 32, max_items, 7] {
		expected := prepare(mut retained, count, 50) or { panic(err) }
		assert (pooled_prepare(mut pool, count, 50) or { panic(err) }) == expected
		assert pool.is_empty()
	}
	for count in [-1, max_items + 1] {
		if _ := pooled_prepare(mut pool, count, 50) {
			assert false
		}
		assert pool.is_empty()
	}
	assert pool.created_count() == 1
}
