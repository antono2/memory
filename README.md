# Generic object pool in V

[Project portfolio](https://oreskin.de/projects_en.php)

A compact example of a fixed-size, generic object pool written in
[V](https://vlang.io). It models game actors, but the pool can be adapted for
particles, projectiles, temporary buffers, or other frequently reused values.

The example demonstrates:

- a generic `ActorPool[T]`
- acquiring inactive values without allocating new ones
- resetting a pool for reuse
- V sum types for actor configuration and drawing context
- type-specific behavior on a pooled actor

## Run it

Install V, clone the repository, and run:

```sh
v run generic_pool.v
```

Example output:

```text
MovingActor: velocity=3.5, screen=1280x720
TextActor: layer=foreground
LuminousActor: intensity=9001, screen=1280x720
LuminousActor: glow intensity=9001
active lights after reset: 0
```

## How the pool works

`new_actor_pool[T]` creates and configures a fixed number of values. Calling
`acquire()` scans from the last position and activates the first available
value. It returns `none` when the pool is exhausted.

```v
mut pool := new_actor_pool[MovingActor](2, [
	ActorConfig(MovementConfig{velocity: 3.5}),
])

mut actor := pool.acquire() or { panic('pool exhausted') }
// Use actor...

pool.reset()
```

The pool intentionally stays small and direct. A production implementation may
also need individual release, automatic growth, synchronization, or generation
IDs for detecting stale references.

## Verify it

```sh
v fmt -verify generic_pool.v generic_pool_test.v
v test .
```

## License

This project is available under the [MIT License](LICENSE).
