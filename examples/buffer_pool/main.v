module main

import memory

struct Buffer {
mut:
	data []u8
}

fn make_buffer() Buffer {
	return Buffer{
		data: []u8{cap: 4096}
	}
}

fn reset_buffer(buffer Buffer) Buffer {
	mut reset := buffer
	reset.data.clear()
	return reset
}

fn main() {
	mut buffers := memory.new_object_pool[Buffer](16, 4, make_buffer, reset_buffer) or {
		panic(err)
	}

	handle := buffers.acquire() or { panic(err) }
	mut buffer := buffers.get_mut(handle) or { panic('stale buffer handle') }
	buffer.data << [u8(1), 2, 3]
	released := buffers.release(handle)
	assert released

	reused := buffers.acquire() or { panic(err) }
	reused_buffer := buffers.get(reused) or { panic('stale buffer handle') }
	assert reused_buffer.data.len == 0
	println('reused buffer capacity: ${reused_buffer.data.cap}')
}
