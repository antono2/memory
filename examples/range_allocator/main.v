module main

import memory

fn main() {
	mut backing_buffer := []u8{len: 256}
	mut ranges := memory.new_range_allocator(u64(backing_buffer.len))

	vertices := ranges.allocate(36, 16) or { panic(err) }
	indices := ranges.allocate(12, 4) or { panic(err) }
	assert vertices.offset % 16 == 0
	assert indices.offset % 4 == 0

	vertex_data := [u8(1), 2, 3, 4]
	start := int(vertices.offset)
	copy(mut backing_buffer[start..start + vertex_data.len], vertex_data)

	stats := ranges.stats()
	println('vertices: offset=${vertices.offset}, size=${vertices.size}')
	println('indices: offset=${indices.offset}, size=${indices.size}')
	println('used=${stats.used}, free=${stats.free}, largest_free=${stats.largest_free_range}')

	vertices_released := ranges.release(vertices)
	assert vertices_released
	indices_released := ranges.release(indices)
	assert indices_released
	assert ranges.stats().largest_free_range == u64(backing_buffer.len)
}
