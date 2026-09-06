module main

// ActorConfig shows how different actor types can accept configuration through
// one shared initialization API.
type ActorConfig = LightConfig | MovementConfig

struct MovementConfig {
	velocity f32
}

struct LightConfig {
	intensity int
}

// DrawContext works the same way for values supplied while drawing.
type DrawContext = Screen | TextLayer

struct Screen {
	width  int = 1280
	height int = 720
}

struct TextLayer {
	name string = 'foreground'
}

// Actor documents the behavior expected by the example's pooled types.
// ActorPool itself is generic, so V checks these methods for each concrete T.
interface Actor {
mut:
	active bool
	configure([]ActorConfig)
	draw([]DrawContext)
}

struct MovingActor {
mut:
	active   bool
	name     string = 'MovingActor'
	velocity f32
}

fn (mut actor MovingActor) configure(config []ActorConfig) {
	for value in config {
		if value is MovementConfig {
			actor.velocity = value.velocity
		}
	}
}

fn (actor MovingActor) draw(context []DrawContext) {
	for value in context {
		if value is Screen {
			println('${actor.name}: velocity=${actor.velocity}, screen=${value.width}x${value.height}')
		}
	}
}

struct TextActor {
mut:
	active bool
	name   string = 'TextActor'
}

fn (mut actor TextActor) configure(_ []ActorConfig) {}

fn (actor TextActor) draw(context []DrawContext) {
	for value in context {
		if value is TextLayer {
			println('${actor.name}: layer=${value.name}')
		}
	}
}

struct LuminousActor {
mut:
	active    bool
	name      string = 'LuminousActor'
	intensity int
}

fn (mut actor LuminousActor) configure(config []ActorConfig) {
	for value in config {
		if value is LightConfig {
			actor.intensity = value.intensity
		}
	}
}

fn (actor LuminousActor) draw(context []DrawContext) {
	for value in context {
		if value is Screen {
			println('${actor.name}: intensity=${actor.intensity}, screen=${value.width}x${value.height}')
		}
	}
}

fn (actor LuminousActor) glow() {
	println('${actor.name}: glow intensity=${actor.intensity}')
}

// ActorPool owns a fixed number of reusable values. acquire returns the next
// inactive value, or none when every value is active.
struct ActorPool[T] {
mut:
	next_index int
pub mut:
	items []T
}

fn new_actor_pool[T](size int, config []ActorConfig) ActorPool[T] {
	mut items := []T{len: size}
	for mut item in items {
		item.configure(config)
	}
	return ActorPool[T]{
		items: items
	}
}

fn (mut pool ActorPool[T]) acquire() ?&T {
	if pool.items.len == 0 {
		return none
	}
	for _ in 0 .. pool.items.len {
		index := pool.next_index
		pool.next_index = (pool.next_index + 1) % pool.items.len
		if !pool.items[index].active {
			pool.items[index].active = true
			return &pool.items[index]
		}
	}
	return none
}

fn (pool ActorPool[T]) draw_active(context []DrawContext) {
	for item in pool.items {
		if item.active {
			item.draw(context)
		}
	}
}

fn (mut pool ActorPool[T]) reset() {
	for mut item in pool.items {
		item.active = false
	}
	pool.next_index = 0
}

fn main() {
	mut moving_actors := new_actor_pool[MovingActor](2, [
		ActorConfig(MovementConfig{ velocity: 3.5 }),
	])
	mut text_actors := new_actor_pool[TextActor](1, [])
	mut lights := new_actor_pool[LuminousActor](1, [
		ActorConfig(LightConfig{ intensity: 9001 }),
	])

	_ = moving_actors.acquire() or { panic('moving actor pool is unexpectedly empty') }
	_ = text_actors.acquire() or { panic('text actor pool is unexpectedly empty') }
	mut light := lights.acquire() or { panic('light pool is unexpectedly empty') }

	screen := DrawContext(Screen{})
	moving_actors.draw_active([screen])
	text_actors.draw_active([DrawContext(TextLayer{})])
	lights.draw_active([screen])
	light.glow()

	lights.reset()
	println('active lights after reset: ${lights.items.count(it.active)}')
}
