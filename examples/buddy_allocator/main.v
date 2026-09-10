module main

import antono2.mem

fn main() {
	mut pages := mem.new_buddy_allocator(64 * 1024, 256) or { panic(err) }
	uniforms := pages.allocate(700, 256) or { panic(err) }
	texture_staging := pages.allocate(5000, 4096) or { panic(err) }

	println('uniforms: offset=${uniforms.offset}, payload=${uniforms.size}, block=${uniforms.block_size}')
	println('texture staging: offset=${texture_staging.offset}, payload=${texture_staging.size}, block=${texture_staging.block_size}')
	stats := pages.stats()
	println('reserved=${stats.reserved}, payload=${stats.payload}, internal fragmentation=${stats.internal_fragmentation}')

	assert pages.release(uniforms)
	assert pages.release(texture_staging)
	assert pages.stats().largest_free_block == pages.capacity()
}
