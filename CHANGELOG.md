# Changelog

All notable changes to this project will be documented in this file.

## 0.2.0 - Unreleased

- Convert the actor demonstration into the importable `generic_pool`
  module.
- Add the fixed-capacity, generation-checked `SlotPool[T]`.
- Add a bounded `ObjectPool[T]` with lazy creation, prewarming, reset callbacks,
  and bulk release.
- Move the actor demonstration to `examples/object_pool`.
- Add automated formatting, vetting, tests, and example execution.
