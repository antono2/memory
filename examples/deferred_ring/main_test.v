// A full queue or failed range request must not strand a live allocation.
module main

fn test_stream_backpressure_failure_wraparound_and_shutdown() {
	mut stream := new_stream(64, 2) or { panic(err) }
	_ := stream.submit(24) or { panic(err) }
	_ := stream.submit(24) or { panic(err) }
	before := stream.ring.stats()
	if _ := stream.submit(8) {
		assert false
	}
	assert stream.ring.stats() == before
	assert stream.next == 3
	assert stream.drain() == 0
	stream.pending.advance_completed(1) or { panic(err) }
	assert stream.drain() == 1
	before_failure := stream.ring.stats()
	if _ := stream.submit(65) {
		assert false
	}
	assert stream.ring.stats() == before_failure
	assert stream.pending.len() == 1
	assert stream.next == 3
	assert (stream.submit(24) or { panic(err) }) == 3
	stream.pending.advance_completed(2) or { panic(err) }
	assert stream.drain() == 1
	assert stream.ring.allocation_count() == 1
	stream.pending.advance_completed(3) or { panic(err) }
	assert stream.drain() == 1
	assert stream.pending.is_empty()
	assert stream.ring.used_bytes() == 0
}
