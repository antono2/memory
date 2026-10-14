// Replays identical synthetic byte workloads through fresh, retained and pooled storage.
module main

import antono2.memory
import time

const scratch_limit = 256

struct BenchmarkScratch {
mut:
	storage &ScratchStorage = &ScratchStorage{}
}

struct ScratchStorage {
mut:
	bytes []u8
}

fn make_scratch() BenchmarkScratch {
	return BenchmarkScratch{
		storage: &ScratchStorage{
			bytes: []u8{cap: scratch_limit}
		}
	}
}

fn reset_scratch(value BenchmarkScratch) BenchmarkScratch {
	mut scratch := value
	unsafe { scratch.storage.bytes.clear() }
	return scratch
}

fn fill_scratch(mut scratch BenchmarkScratch, count int, seed u32) !u64 {
	if count < 0 || count > scratch_limit {
		return error('scratch limit exceeded')
	}
	scratch.storage.bytes.clear()
	mut checksum := u64(0)
	for index in 0 .. count {
		value := u8(seed + u32(index) * 17)
		scratch.storage.bytes << value
		checksum += u64(value)
	}
	return checksum
}

fn benchmark_workspaces(operations int, mode string) BenchmarkResult {
	mut retained := make_scratch()
	mut pool := memory.new_object_pool[BenchmarkScratch](1, 1, make_scratch, reset_scratch) or {
		panic(err)
	}
	// Warm up the full admitted size outside the timed section.
	_ := fill_scratch(mut retained, scratch_limit, 0) or { panic(err) }
	warm := pool.acquire() or { panic(err) }
	mut warm_value := pool.get_mut(warm) or { panic('missing warm lease') }
	_ := fill_scratch(mut warm_value, scratch_limit, 0) or { panic(err) }
	if !pool.release(warm) { panic('warm lease release failed') }
	mut checksum := u64(0)
	mut hash := u64(0xcbf29ce484222325)
	mut rejected := 0
	mut replacements := 0
	mut growths := 0
	mut peak := 0
	mut created := if mode == 'fresh' { 0 } else { 1 }
	mut retained_capacity := 0
	mut fresh := make_scratch()
	start := time.sys_mono_now()
	for operation in 0 .. operations {
		count := if operation % 97 == 0 {
			scratch_limit + 1
		} else if operation % 31 == 0 {
			scratch_limit
		} else {
			operation % 65
		}
		seed := u32(operation) * 13
		hash = (hash ^ (u64(count) << 32) ^ u64(seed)) * 0x100000001b3
		mut handle := memory.Handle{}
		mut scratch := &retained
		if mode == 'fresh' {
			fresh = make_scratch()
			scratch = &fresh
			created++
		} else if mode == 'pooled' {
			handle = pool.acquire() or { panic(err) }
			scratch = pool.get_mut(handle) or { panic('missing lease') }
		}
		before := scratch.storage.bytes.data
		before_capacity := scratch.storage.bytes.cap
		checksum += fill_scratch(mut scratch, count, seed) or {
			rejected++
			u64(0)
		}
		if scratch.storage.bytes.data != before { replacements++ }
		if scratch.storage.bytes.cap != before_capacity { growths++ }
		peak = if scratch.storage.bytes.len > peak { scratch.storage.bytes.len } else { peak }
		retained_capacity = scratch.storage.bytes.cap
		if mode == 'pooled' {
			if !pool.release(handle) { panic('lease release failed') }
		}
	}
	elapsed := time.sys_mono_now() - start
	if replacements != 0 || growths != 0 { panic('pre-sized workspace storage changed') }
	return BenchmarkResult{
		name:       'workspace ${mode}'
		operations: operations
		elapsed_ns: elapsed
		checksum:   checksum
		trace_hash: hash
		detail:     'trace=workspace-v1 rejected=${rejected} factory_calls=${created} buffer_replacements=${replacements} capacity_changes=${growths} peak_bytes=${peak} payload_capacity=${retained_capacity}'
	}
}

fn benchmark_handle_snapshots(operations int, reuse bool) BenchmarkResult {
	mut pool := memory.new_slot_pool[u64](128) or { panic(err) }
	for i in 0 .. 128 {
		handle := pool.insert(u64(i)) or { panic(err) }
		if i % 3 == 0 {
			if !pool.release(handle) { panic('slot release failed') }
		}
	}
	mut destination := []memory.Handle{cap: 128}
	mut checksum := u64(0)
	start := time.sys_mono_now()
	for _ in 0 .. operations {
		if reuse {
			pool.handles_into(mut destination)
		} else {
			destination = pool.handles()
		}
		for handle in destination {
			checksum += *(pool.get(handle) or { panic('invalid snapshot') })
		}
	}
	return BenchmarkResult{
		name:       if reuse { 'handles caller buffer' } else { 'handles fresh snapshot' }
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum
		trace_hash: 0x68616e646c657301
		detail:     'trace=handles-v1 live=${pool.len()} destination_capacity=${destination.cap}'
	}
}

fn benchmark_retirement(operations int) BenchmarkResult {
	mut queue := memory.new_retirement_queue[u64](32) or { panic(err) }
	mut checksum := u64(0)
	mut saturated := 0
	start := time.sys_mono_now()
	for operation in 0 .. operations {
		token := u64(operation) + 1
		if queue.is_full() {
			if _ := queue.enqueue(token, token) { panic('expected backpressure') }
			saturated++
			queue.advance_completed(token - 16) or { panic(err) }
			for {
				checksum += queue.try_take_ready() or { break }
			}
		}
		queue.enqueue(token, token) or { panic(err) }
	}
	queue.advance_completed(u64(operations)) or { panic(err) }
	for {
		checksum += queue.try_take_ready() or { break }
	}
	if checksum != u64(operations) * (u64(operations) + 1) / 2 {
		panic('retirement checksum mismatch')
	}
	return BenchmarkResult{
		name:       'retirement delayed completion'
		operations: operations
		elapsed_ns: time.sys_mono_now() - start
		checksum:   checksum
		trace_hash: 0x7265746972650001
		detail:     'trace=retirement-v1 capacity=32 backpressure=${saturated} final_pending=${queue.len()}'
	}
}
