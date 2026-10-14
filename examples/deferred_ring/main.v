// Simulates ordered submission completion without a GPU or platform dependency.
module main

import antono2.memory

struct Stream {
mut:
	ring    &memory.RingAllocator @[required]
	pending &memory.RetirementQueue[memory.RingAllocation] @[required]
	next    u64 = 1
}

fn new_stream(bytes u64, submissions int) !Stream {
	return Stream{
		ring:    memory.new_ring_allocator(bytes)
		pending: memory.new_retirement_queue[memory.RingAllocation](submissions)!
	}
}

fn (mut stream Stream) drain() int {
	mut count := 0
	for {
		allocation := stream.pending.try_take_ready() or { break }
		if !stream.ring.release(allocation) { panic('FIFO lifetime invariant violated') }
		count++
	}
	return count
}

// One serial producer generates its own tokens and reserves queue capacity
// before allocating. Shared producers require one external lock around both.
fn (mut stream Stream) submit(size u64) !u64 {
	if stream.pending.is_full() || stream.next == 0 {
		return error('apply backpressure or start a new drained completion domain')
	}
	token := stream.next
	allocation := stream.ring.allocate(size, 4)!
	// All enqueue preconditions are established before allocation. Do not try to
	// undo a new FIFO allocation while older allocations remain live.
	stream.pending.enqueue(allocation, token) or { panic('broken producer invariant: ${err}') }
	stream.next = if token == ~u64(0) { u64(0) } else { token + 1 }
	return token
}

fn main() {
	mut stream := new_stream(64, 2) or { panic(err) }
	first := stream.submit(24) or { panic(err) }
	second := stream.submit(24) or { panic(err) }
	initial := stream.drain()
	assert initial == 0
	if _ := stream.submit(8) {
		panic('expected queue backpressure')
	}
	stream.pending.advance_completed(first) or { panic(err) }
	first_retired := stream.drain()
	assert first_retired == 1
	third := stream.submit(24) or { panic(err) } // Wraps to offset zero.
	stream.pending.advance_completed(second) or { panic(err) }
	second_retired := stream.drain()
	assert second_retired == 1
	assert stream.ring.allocation_count() == 1
	// Shutdown: observe completion of the last submission before releasing its
	// metadata, and only then destroy the caller-owned backing resource.
	stream.pending.advance_completed(third) or { panic(err) }
	last_retired := stream.drain()
	assert last_retired == 1
	assert stream.pending.is_empty() && stream.ring.used_bytes() == 0
	println('retired three submissions after observed completion, including wraparound')
}
