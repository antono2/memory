module main

import antono2.mem
import os
import time

const default_operations = 1_000_000

struct BenchmarkResult {
	name       string
	operations int
	elapsed_ns u64
	checksum   u64
	detail     string
}

struct BenchmarkRandom {
mut:
	state u32
}

fn (mut random BenchmarkRandom) next() u32 {
	random.state = random.state * 1_664_525 + 1_013_904_223
	return random.state
}

fn benchmark_slot_pool(operations int) BenchmarkResult {
	mut pool := mem.new_slot_pool[u64](1024) or { panic(err) }
	mut handles := []mem.Handle{cap: 1024}
	mut random_source := BenchmarkRandom{
		state: 0x5107cafe
	}
	mut checksum := u64(0)
	start := time.sys_mono_now()
	for operation in 0 .. operations {
		random := random_source.next()
		if handles.len == pool.capacity() || (handles.len > 0 && random & 3 == 0) {
			handle := handles[handles.len - 1]
			checksum += pool.take(handle) or { panic('live slot handle was rejected') }
			handles.trim(handles.len - 1)
		} else {
			handles << pool.insert(u64(operation)) or { panic(err) }
		}
	}
	return BenchmarkResult{
		name:       'slot pool churn'
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum + u64(pool.len())
		detail:     'capacity=1024 live=${pool.len()}'
	}
}

fn make_benchmark_object() u64 {
	return 1
}

fn reset_benchmark_object(_ u64) u64 {
	return 0
}

fn benchmark_object_pool(operations int) BenchmarkResult {
	mut pool := mem.new_object_pool[u64](1024, 1024, make_benchmark_object, reset_benchmark_object) or {
		panic(err)
	}
	mut handles := []mem.Handle{cap: 1024}
	mut random_source := BenchmarkRandom{
		state: 0x0b1ec700
	}
	mut checksum := u64(0)
	start := time.sys_mono_now()
	for operation in 0 .. operations {
		random := random_source.next()
		if handles.len == pool.capacity() || (handles.len > 0 && random & 3 == 0) {
			handle := handles[handles.len - 1]
			if !pool.release(handle) {
				panic('live object handle was rejected')
			}
			checksum += u64(operation)
			handles.trim(handles.len - 1)
		} else {
			handle := pool.acquire() or {
				panic('object acquire failed at operation ${operation}: tracked=${handles.len} leases=${pool.len()} available=${pool.available_count()} created=${pool.created_count()}: ${err}')
			}
			handles << handle
		}
	}
	return BenchmarkResult{
		name:       'object pool churn'
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum + u64(pool.len())
		detail:     'capacity=1024 live=${pool.len()} created=${pool.created_count()}'
	}
}

fn benchmark_range_allocator(operations int) BenchmarkResult {
	mut allocator := mem.new_range_allocator(1024 * 1024)
	mut active := []mem.RangeAllocation{cap: 1024}
	mut random_source := BenchmarkRandom{
		state: 0xa110ca7e
	}
	mut checksum := u64(0)
	start := time.sys_mono_now()
	for _ in 0 .. operations {
		random := random_source.next()
		if active.len > 0 && random % 3 == 0 {
			index := int((random >> 8) % u32(active.len))
			allocation := active[index]
			checksum += allocation.offset
			if !allocator.release(allocation) {
				panic('live range allocation was rejected')
			}
			active[index] = active[active.len - 1]
			active.trim(active.len - 1)
		} else {
			size := u64(16 + (random >> 12) % 2033)
			alignment := u64(1) << u32((random >> 28) % 9)
			if allocation := allocator.allocate(size, alignment) {
				active << allocation
			} else if active.len > 0 {
				index := int((random >> 8) % u32(active.len))
				if !allocator.release(active[index]) {
					panic('live range allocation was rejected after exhaustion')
				}
				active[index] = active[active.len - 1]
				active.trim(active.len - 1)
			}
		}
	}
	stats := allocator.stats()
	return BenchmarkResult{
		name:       'range first-fit'
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum + stats.used
		detail:     'capacity=1MiB live=${stats.allocation_count} free_ranges=${stats.free_range_count} largest_free=${stats.largest_free_range}'
	}
}

fn benchmark_linear_allocator(operations int) BenchmarkResult {
	mut allocator := mem.new_linear_allocator(1024 * 1024)
	mut random_source := BenchmarkRandom{
		state: 0x1a2b3c4d
	}
	mut checksum := u64(0)
	start := time.sys_mono_now()
	for _ in 0 .. operations {
		random := random_source.next()
		size := u64(16 + (random >> 12) % 2033)
		alignment := u64(1) << u32((random >> 28) % 9)
		if allocation := allocator.allocate(size, alignment) {
			checksum += allocation.offset
		} else {
			allocator.reset()
			allocation := allocator.allocate(size, alignment) or { panic(err) }
			checksum += allocation.offset
		}
	}
	stats := allocator.stats()
	return BenchmarkResult{
		name:       'linear allocate/reset'
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum + stats.used
		detail:     'capacity=1MiB peak=${stats.peak_used}'
	}
}

fn benchmark_ring_allocator(operations int) BenchmarkResult {
	mut allocator := mem.new_ring_allocator(1024 * 1024)
	mut active := []mem.RingAllocation{cap: 2048}
	mut first_active := 0
	mut random_source := BenchmarkRandom{
		state: 0x71f01234
	}
	mut checksum := u64(0)
	start := time.sys_mono_now()
	for _ in 0 .. operations {
		random := random_source.next()
		if first_active < active.len && random & 3 == 0 {
			allocation := active[first_active]
			checksum += allocation.offset
			if !allocator.release(allocation) {
				panic('oldest ring allocation was rejected')
			}
			first_active++
		} else {
			size := u64(16 + (random >> 12) % 2033)
			alignment := u64(1) << u32((random >> 28) % 9)
			if allocation := allocator.allocate(size, alignment) {
				active << allocation
			} else if first_active < active.len {
				if !allocator.release(active[first_active]) {
					panic('oldest ring allocation was rejected after exhaustion')
				}
				first_active++
			}
		}
		if first_active >= 4096 && first_active * 2 >= active.len {
			active = active[first_active..].clone()
			first_active = 0
		}
	}
	stats := allocator.stats()
	return BenchmarkResult{
		name:       'ring streaming'
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum + stats.used
		detail:     'capacity=1MiB live=${stats.allocation_count} padding=${stats.padding} largest_free=${stats.largest_contiguous_free}'
	}
}

fn print_result(result BenchmarkResult) {
	ns_per_operation := f64(result.elapsed_ns) / f64(result.operations)
	operations_per_second := 1_000_000_000.0 / ns_per_operation
	println('${result.name}: ${ns_per_operation:.1f} ns/op, ${operations_per_second:.0f} ops/s')
	println('  ${result.detail} checksum=${result.checksum}')
}

fn main() {
	mut operations := default_operations
	if os.args.len > 1 {
		operations = os.args[1].int()
	}
	if operations <= 0 {
		eprintln('operation count must be greater than zero')
		exit(2)
	}
	println('deterministic allocator benchmark: operations=${operations}, seed set=v1')
	print_result(benchmark_slot_pool(operations))
	print_result(benchmark_object_pool(operations))
	print_result(benchmark_range_allocator(operations))
	print_result(benchmark_linear_allocator(operations))
	print_result(benchmark_ring_allocator(operations))
}
