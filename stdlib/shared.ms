# A reference-counted, immutable value that several owners hold at once.
#
# Copying a `Shared[T]` shares the payload instead of duplicating it; the payload is freed when
# the last holder is dropped. The payload cannot be changed through a `Shared`, so state that
# several holders update lives in the payload's own handles (streams, gates, builders).
export type Shared[T]:

# Moves `value` into a new `Shared` with one holder; copy the result to add holders.
export fn share[T](value: T) Shared[T]:

impl Shared[T]:
    # Reads the shared payload in place; the result borrows from this `Shared`.
    fn get() ref T:
