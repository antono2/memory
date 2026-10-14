// Converts out-of-order job completion to a contiguous retirement frontier.
module main

import antono2.memory

struct JobBuffer {
mut:
	bytes []u8
}

fn make_buffer() JobBuffer {
	return JobBuffer{
		bytes: []u8{cap: 128}
	}
}

fn reset_buffer(value JobBuffer) JobBuffer {
	mut buffer := value
	buffer.bytes.clear()
	return buffer
}

fn main() {
	mut pool := memory.new_object_pool[JobBuffer](3, 3, make_buffer, reset_buffer) or { panic(err) }
	mut pending := memory.new_retirement_queue[memory.Handle](3) or { panic(err) }
	for token in u64(1) .. u64(4) {
		handle := pool.acquire() or { panic(err) }
		// Register before starting asynchronous work. A rejected registration can
		// safely return an unsubmitted lease immediately.
		pending.enqueue(handle, token) or {
			pool.release(handle)
			panic(err)
		}
	}
	mut done := [false, false, false, false]
	mut frontier := 0
	mut released := 0
	for finished in [2, 1, 3] {
		done[finished] = true
		for frontier + 1 < done.len && done[frontier + 1] {
			frontier++
		}
		pending.advance_completed(u64(frontier)) or { panic(err) }
		for {
			handle := pending.try_take_ready() or { break }
			if !pool.release(handle) { panic('lease was released before completion') }
			released++
		}
		if finished == 2 {
			assert released == 0 // Job 1 still owns its buffer.
			assert pool.is_full()
		}
	}
	assert released == 3
	assert pending.is_empty() && pool.is_empty()
	println('recycled three buffers after completion order 2, 1, 3')
}
