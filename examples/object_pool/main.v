module main

import memory

struct MovingActor {
	name string = 'MovingActor'
mut:
	x        f32
	velocity f32 = 3.5
}

fn make_moving_actor() MovingActor {
	return MovingActor{}
}

fn reset_moving_actor(actor MovingActor) MovingActor {
	return MovingActor{
		velocity: actor.velocity
	}
}

fn main() {
	mut actors := memory.new_object_pool[MovingActor](2, 1, make_moving_actor, reset_moving_actor) or {
		panic(err)
	}

	actor_handle := actors.acquire() or { panic(err) }
	mut actor := actors.get_mut(actor_handle) or { panic('actor handle became stale') }
	actor.x += actor.velocity
	println('${actor.name}: x=${actor.x}, velocity=${actor.velocity}')

	released := actors.release(actor_handle)
	assert released
	reused_handle := actors.acquire() or { panic(err) }
	reused := actors.get(reused_handle) or { panic('reused actor handle became stale') }
	println('${reused.name}: x=${reused.x}, reused=${actors.created_count() == 1}')

	released_count := actors.release_all()
	assert released_count == 1
	println('active actors after release: ${actors.len()}')
}
