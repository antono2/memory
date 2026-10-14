// Checks completion ordering, bounded storage and an independent FIFO model.
module memory

fn test_retirement_queue_configuration_and_failure_atomicity() {
	if _ := new_retirement_queue[int](-1) {
		assert false
	}
	mut empty := new_retirement_queue[int](0) or { panic(err) }
	assert empty.is_empty() && empty.is_full()
	if _ := empty.try_take_ready() {
		assert false
	}
	if _ := empty.enqueue(1, 1) {
		assert false
	}
	assert empty.len() == 0
	mut queue := new_retirement_queue[int](2) or { panic(err) }
	if _ := queue.enqueue(0, 0) {
		assert false
	}
	queue.enqueue(10, 2) or { panic(err) }
	if _ := queue.enqueue(20, 1) {
		assert false
	}
	queue.enqueue(30, 2) or { panic(err) }
	assert queue.is_full()
	if _ := queue.enqueue(40, 100) {
		assert false
	}
	assert queue.last == 2
	assert queue.len() == 2
	queue.advance_completed(1) or { panic(err) }
	if _ := queue.try_take_ready() {
		assert false
	}
	if _ := queue.advance_completed(0) {
		assert false
	}
	assert queue.completed_token() == 1
	queue.advance_completed(2) or { panic(err) }
	queue.advance_completed(2) or { panic(err) }
	assert (queue.try_take_ready() or { panic('missing value') }) == 10
	assert (queue.try_take_ready() or { panic('missing grouped value') }) == 30
	assert queue.is_empty()
	if _ := queue.enqueue(50, 2) {
		assert false
	}
	queue.enqueue(60, 3) or { panic(err) }
	queue.advance_completed(100) or { panic(err) }
	assert (queue.try_take_ready() or { panic('missing value') }) == 60
	queue.enqueue(70, 101) or { panic(err) }
}

fn test_retirement_queue_wraparound_and_token_limit() {
	mut queue := new_retirement_queue[u64](3) or { panic(err) }
	storage := queue.entries.data
	for token in u64(1) .. u64(1001) {
		queue.enqueue(token, token) or { panic(err) }
		queue.advance_completed(token) or { panic(err) }
		assert (queue.try_take_ready() or { panic('missing value') }) == token
		assert queue.entries.data == storage
		assert queue.capacity() == 3
	}
	maximum := ~u64(0)
	queue.enqueue(maximum - 1, maximum - 1) or { panic(err) }
	queue.enqueue(maximum, maximum) or { panic(err) }
	queue.advance_completed(maximum - 1) or { panic(err) }
	assert (queue.try_take_ready() or { panic('missing penultimate') }) == maximum - 1
	if _ := queue.try_take_ready() {
		assert false
	}
	queue.advance_completed(maximum) or { panic(err) }
	assert (queue.try_take_ready() or { panic('missing last') }) == maximum
	if _ := queue.enqueue(0, 0) {
		assert false
	}
	if _ := queue.advance_completed(0) {
		assert false
	}
}

struct RetiredPayload {
	bytes []u8
}

fn test_retirement_queue_clears_removed_payload_reference() {
	mut queue := new_retirement_queue[RetiredPayload](1) or { panic(err) }
	queue.enqueue(RetiredPayload{ bytes: [u8(3), 4] }, 1) or { panic(err) }
	queue.advance_completed(1) or { panic(err) }
	value := queue.try_take_ready() or { panic('missing payload') }
	assert value.bytes == [u8(3), 4]
	assert queue.entries[0].value.bytes.len == 0
	assert queue.entries[0].after == 0
}

fn test_retirement_queue_deterministic_reference_model() {
	mut queue := new_retirement_queue[int](7) or { panic(err) }
	mut tokens := []u64{}
	mut values := []int{}
	mut completed := u64(0)
	mut last := u64(0)
	mut state := u32(0xdecafbad)
	for step in 0 .. 20_000 {
		state = state * 1_664_525 + 1_013_904_223
		match state % 4 {
			0, 1 {
				token := if state & 16 == 0 { last } else { last + 1 }
				valid := token > completed && token >= last && tokens.len < 7
				if _ := queue.enqueue(step, token) {
					assert valid
					tokens << token
					values << step
					last = token
				} else {
					assert !valid
				}
			}
			2 {
				candidate := if state & 32 == 0 && completed > 0 {
					completed - 1
				} else {
					completed + u64((state >> 8) % 3)
				}
				if _ := queue.advance_completed(candidate) {
					assert candidate >= completed
					completed = candidate
				} else {
					assert candidate < completed
				}
				if last < completed {
					last = completed
				}
			}
			else {
				ready := tokens.len > 0 && tokens[0] <= completed
				if value := queue.try_take_ready() {
					assert ready
					assert value == values[0]
					tokens.delete(0)
					values.delete(0)
				} else {
					assert !ready
				}
			}
		}

		assert queue.len() == tokens.len
		assert queue.completed_token() == completed
	}
	queue.advance_completed(~u64(0)) or { panic(err) }
	for expected in values {
		assert (queue.try_take_ready() or { panic('missing drain value') }) == expected
	}
	assert queue.is_empty()
}
