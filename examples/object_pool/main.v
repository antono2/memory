module main

import generic_pool

struct MovingActor {
	name string = 'MovingActor'
mut:
	x        f32
	velocity f32
}

struct Light {
	name string = 'Light'
mut:
	intensity int
}

fn main() {
	mut actors := generic_pool.new_slot_pool[MovingActor](2) or { panic(err) }
	mut lights := generic_pool.new_slot_pool[Light](1) or { panic(err) }

	actor_handle := actors.insert(MovingActor{ velocity: 3.5 }) or { panic(err) }
	light_handle := lights.insert(Light{ intensity: 9001 }) or { panic(err) }

	mut actor := actors.get_mut(actor_handle) or { panic('actor handle became stale') }
	actor.x += actor.velocity
	light := lights.get(light_handle) or { panic('light handle became stale') }

	println('${actor.name}: x=${actor.x}, velocity=${actor.velocity}')
	println('${light.name}: intensity=${light.intensity}')

	assert actors.release(actor_handle)
	assert actors.get(actor_handle) == none
	println('active actors after release: ${actors.len()}')

	lights.clear()
	assert lights.get(light_handle) == none
	println('active lights after clear: ${lights.len()}')
}
