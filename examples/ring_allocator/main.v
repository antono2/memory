module main

import memory

fn main() {
	mut staging_buffer := []u8{len: 64}
	mut uploads := memory.new_ring_allocator(u64(staging_buffer.len))

	frame_0 := uploads.allocate(24, 16) or { panic(err) }
	frame_1 := uploads.allocate(24, 16) or { panic(err) }
	staging_buffer[int(frame_0.offset)] = 10
	staging_buffer[int(frame_1.offset)] = 11

	// A completed submission retires the oldest region first.
	frame_0_released := uploads.release(frame_0)
	assert frame_0_released

	// The next upload wraps to the start instead of crossing the buffer end.
	frame_2 := uploads.allocate(16, 16) or { panic(err) }
	assert frame_2.offset == 0
	staging_buffer[int(frame_2.offset)] = 12

	stats := uploads.stats()
	println('frame 1: offset=${frame_1.offset}, size=${frame_1.size}')
	println('frame 2: offset=${frame_2.offset}, size=${frame_2.size}')
	println('used=${stats.used}, payload=${stats.payload}, padding=${stats.padding}')

	// Releasing a newer submission early is rejected.
	assert !uploads.release(frame_2)
	frame_1_released := uploads.release(frame_1)
	assert frame_1_released
	frame_2_released := uploads.release(frame_2)
	assert frame_2_released
	assert uploads.free_bytes() == u64(staging_buffer.len)
}
