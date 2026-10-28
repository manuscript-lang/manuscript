# A reference-counted value that several owners hold at once.
#
# Copying a `Shared[T]` shares the payload instead of duplicating it; the payload is freed when
# the last holder is dropped. `get` reads the payload. To change it, `lock` it from
# `@std/sync.ms` into a `var` binding: the guard holds the payload for its scope and returns it when the
# scope ends, however it ends. `take`, `put`, `locked` and `id` are the primitives `lock` is built on;
# calling them elsewhere is rejected.
export type Shared[T]: ...

# Moves `value` into a new `Shared` with one holder; copy the result to add holders.
export def share[T](value: T) -> Shared[T]: ...

impl Shared[T]:
    # Reads the shared payload in place; the result borrows from this `Shared`.
    # Faults while the payload is taken.
    def get() -> ref T: ...

    # The identity of this box, the same for every copy of the handle. Only `lock` in
    # `@std/sync.ms` may call this; it keys the queue of tasks waiting for the box.
    def id() -> Int: ...

    # Whether the payload is out. Only `lock` in `@std/sync.ms` may call this.
    def locked() -> Bool: ...

    # Moves the payload out and marks this `Shared` in use. Faults if it is already out. Only
    # `lock` in `@std/sync.ms` may call this.
    def take() -> T: ...

    # Moves a payload back after `take`. Faults if nothing was taken. Only `SharedGuard.close`
    # in `@std/sync.ms` may call this.
    def put(value: T) -> Unit: ...
