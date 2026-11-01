import Closeable from "@std/core.ms"

# A reference-counted value that several owners hold at once.
#
# Copying a `Shared[T]` shares the payload instead of duplicating it; the payload is freed when
# the last holder is dropped. `get` reads the payload. To change it, `lock` it into a `var`
# binding: the guard holds the payload for its scope and returns it when the scope ends, however
# it ends.
export extern type Shared[T]

# Moves `value` into a new `Shared` with one holder; copy the result to add holders.
export fn share[T](value: T) Shared[T]: ...

impl Shared[T]:
    # Reads the shared payload in place; the result borrows from this `Shared`.
    # Faults while the payload is locked.
    fn get() T: ...

# The identity of `box`, the same for every copy of the handle; it keys the queue of tasks waiting
# for the box.
fn id[T](box: Shared[T]) Int: ...

# Whether the payload of `box` is out.
fn locked[T](box: Shared[T]) Bool: ...

# Moves the payload out of `box` and marks it in use. Faults if it is already out.
fn take[T](box: Shared[T]) T: ...

# Moves `value` back into `box` after `take`, without a copy. Faults if nothing was taken.
fn put[T](box: Shared[T], value: T) Unit: ...

extern fn msrt_channel_token() Int

extern fn msrt_channel_park(token: Int) Unit

extern fn msrt_waitq_push(key: Int, token: Int) Unit

extern fn msrt_waitq_wake(key: Int) Int

extern fn msrt_waitq_remove(key: Int, token: Int) Int

# The locked payload of a `Shared`, held until the scope of the binding that opened it ends, or its `close()` is called. Change the
# payload through `value`.
export type SharedGuard[T]:
    # Internal state: the box the payload returns to.
    box: Shared[T]
    # The payload while locked.
    value: T
    # Internal state: false once the payload was returned.
    held: Bool

impl Closeable for SharedGuard[T]:
    # Returns the payload to the box, also when the task is cancelled or faults inside the block.
    # Closing again does nothing.
    var fn close() Unit!:
        if self.held:
            self.held = false
            put(self.box, self.value)
            msrt_waitq_wake(id(self.box))

        return ok(unit)

# A waiting task's place in the queue of a box. Closing it matters only when the wait was cut short.
type Ticket:
    # The box the task waits for.
    key: Int
    # The token the task parks on.
    token: Int
    # False once the park returned normally.
    parked: Bool

impl Closeable for Ticket:
    # A task cancelled while parked leaves the queue, or, when a release had already chosen it,
    # passes that wake on so it is not lost.
    var fn close() Unit!:
        if self.parked:
            if msrt_waitq_remove(self.key, self.token) == 0:
                msrt_waitq_wake(self.key)
        return ok(unit)

# Locks `box` and returns the guard that holds its payload. Waits while another guard holds it,
# and stops waiting if the task is cancelled. Bind it with `var`; the scope end closes the guard:
# `var guard = lock(box)`, then change `guard.value`.
export fn lock[T](box: Shared[T]) SharedGuard[T]:
    while locked(box):
        let key = id(box)
        let token = msrt_channel_token()
        msrt_waitq_push(key, token)

        var ticket = Ticket(key: key, token: token, parked: true)
        msrt_channel_park(token)
        ticket.parked = false

    return SharedGuard[T](box: box, value: take(box), held: true)
