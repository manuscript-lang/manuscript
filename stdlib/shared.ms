# A reference-counted value that several owners hold at once.
#
# Copying a `Shared[T]` shares the payload instead of duplicating it; the payload is freed when
# the last holder is dropped. `get` reads the payload. To change it, `take` the payload out,
# change the local, and `put` it back; one holder at a time can have it out, and a second `take`
# or a `get` meanwhile is a fault.
export type Shared[T]: ...

# Moves `value` into a new `Shared` with one holder; copy the result to add holders.
export def share[T](value: T) -> Shared[T]: ...

impl Shared[T]:
    # Reads the shared payload in place; the result borrows from this `Shared`.
    # Faults while the payload is taken.
    def get() -> ref T: ...

    # Moves the payload out to change it and marks this `Shared` in use. Faults if it is already
    # out. Return it with `put` before any other holder reads it.
    def take() -> T: ...

    # Moves a payload back after `take`. Faults if nothing was taken.
    def put(value: T) -> Unit: ...
