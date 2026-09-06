module main

fn test_pool_acquire_exhaustion_and_reset() {
	mut pool := new_actor_pool[MovingActor](2, [
		ActorConfig(MovementConfig{ velocity: 2.5 }),
	])

	first := pool.acquire() or { panic('expected first actor') }
	second := pool.acquire() or { panic('expected second actor') }

	assert first.active
	assert second.active
	assert first.velocity == 2.5
	assert pool.acquire() == none

	pool.reset()
	assert pool.items.all(!it.active)
	assert pool.acquire() != none
}

fn test_empty_pool_returns_none() {
	mut pool := new_actor_pool[MovingActor](0, [])
	assert pool.acquire() == none
}
