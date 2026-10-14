// Reuses bounded scratch arrays; outputs that outlive a lease need an explicit copy.
module main

import antono2.memory

const max_items = 256

struct Workspace {
mut:
	storage &WorkspaceStorage = &WorkspaceStorage{}
}

struct WorkspaceStorage {
mut:
	bytes   []u8
	indices []int
	visible []bool
}

fn make_workspace() Workspace {
	return Workspace{
		storage: &WorkspaceStorage{
			bytes:   []u8{cap: max_items * 4}
			indices: []int{cap: max_items}
			visible: []bool{cap: max_items}
		}
	}
}

fn reset_workspace(value Workspace) Workspace {
	// Copying this wrapper retains its private storage reference, not its arrays.
	mut workspace := value
	// Release ends the exclusive lease before this immutable-value callback.
	unsafe {
		workspace.storage.bytes.clear()
		workspace.storage.indices.clear()
		workspace.storage.visible.clear()
	}
	return workspace
}

// Reject before mutation. The caller chooses an application-specific limit;
// ObjectPool bounds lease count, not the size of arrays inside each workspace.
fn prepare(mut workspace Workspace, count int, seed u32) !u64 {
	if count < 0 || count > max_items {
		return error('workspace item limit exceeded')
	}
	workspace.storage.bytes.clear()
	workspace.storage.indices.clear()
	workspace.storage.visible.clear()
	mut checksum := u64(0)
	for i in 0 .. count {
		value := seed + u32(i) * 17
		visible := value & 1 == 0
		workspace.storage.bytes << [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)]
		workspace.storage.visible << visible
		if visible {
			workspace.storage.indices << i
		}
		checksum += u64(value)
	}
	return checksum
}

fn pooled_prepare(mut pool memory.ObjectPool[Workspace], count int, seed u32) !u64 {
	handle := pool.acquire()!
	defer {
		pool.release(handle)
	}
	mut workspace := pool.get_mut(handle) or { return error('missing workspace') }
	return prepare(mut workspace, count, seed)
}

fn main() {
	// Sequential work only needs one retained workspace.
	mut retained := make_workspace()
	for count in [0, 8, 64, max_items] {
		checksum := prepare(mut retained, count, 42) or { panic(err) }
		println('retained: items=${count} checksum=${checksum}')
	}
	// Use a pool when workspaces have overlapping lifetimes. Prewarm every lease
	// that must be available without invoking the factory on the processing path.
	mut pool := memory.new_object_pool[Workspace](2, 2, make_workspace, reset_workspace) or {
		panic(err)
	}
	first := pool.acquire() or { panic(err) }
	second := pool.acquire() or { panic(err) }
	mut first_workspace := pool.get_mut(first) or { panic('missing first lease') }
	_ := prepare(mut first_workspace, 32, 7) or { panic(err) }
	mut second_workspace := pool.get_mut(second) or { panic('missing second lease') }
	_ := prepare(mut second_workspace, 12, 99) or { panic(err) }
	// This result must survive release. A slice alone would still borrow storage.
	owned_result := first_workspace.storage.bytes.clone()
	if _ := pool.acquire() {
		panic('expected bounded pool exhaustion')
	}
	if !pool.release(first) || !pool.release(second) { panic('release failed') }
	checksum := pooled_prepare(mut pool, max_items, 19) or { panic(err) }
	if _ := pooled_prepare(mut pool, max_items + 1, 19) {
		panic('expected oversized request rejection')
	}
	assert pool.is_empty() // The failed request also released its lease.
	assert owned_result.len == 32 * 4
	println('pooled: checksum=${checksum} created=${pool.created_count()} owned_bytes=${owned_result.len}')
}
