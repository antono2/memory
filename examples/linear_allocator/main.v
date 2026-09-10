module main

import generic_pool

fn main() {
	mut frame_memory := []u8{len: 1024}
	mut arena := generic_pool.new_linear_allocator(u64(frame_memory.len))

	for frame in 0 .. 3 {
		vertices := arena.allocate(300, 16) or { panic(err) }
		uniforms := arena.allocate(64, 256) or { panic(err) }

		frame_memory[int(vertices.offset)] = u8(frame)
		frame_memory[int(uniforms.offset)] = u8(frame + 10)
		stats := arena.stats()
		println('frame=${frame}, used=${stats.used}, payload=${stats.payload}, padding=${stats.padding}')

		arena.reset()
		assert !arena.contains(vertices)
		assert !arena.contains(uniforms)
	}
	println('peak frame usage: ${arena.stats().peak_used}')
}
