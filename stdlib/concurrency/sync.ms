import Closeable from "@std/core.ms"
import Shared, share from "@std/concurrency/shared.ms"
import (
    msrt_channel_token,
    msrt_channel_park,
    msrt_waitq_push,
    msrt_waitq_wake,
    msrt_waitq_remove
) from "@std/internal/sync.ms"

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
            self.box.put(self.value)
            msrt_waitq_wake(self.box.id())

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
    while box.locked():
        let key = box.id()
        let token = msrt_channel_token()
        msrt_waitq_push(key, token)

        var ticket = Ticket(key: key, token: token, parked: true)
        msrt_channel_park(token)
        ticket.parked = false

    return SharedGuard[T](box: box, value: box.take(), held: true)

# Runs an action at most once, however many tasks ask. Tasks that arrive while the action runs wait for it
# to finish, then return without running it again. Copies of a `Once` share one outcome.
export type Once:
    # Internal state: true once the action has completed.
    done: Shared[Bool]

# Returns a `Once` that has not run yet.
export fn once() Once:
    return Once(done: share(false))

impl Once:
    # Runs `action` the first time any copy of this `Once` calls it; later calls return at once. If the first
    # caller is cancelled or faults inside `action`, the action counts as not run and the next caller runs it.
    fn run(action: fn() Unit) Unit:
        var guard = lock(self.done)
        if guard.value:
            return unit

        action()
        guard.value = true
        return unit

    # Whether the action has completed.
    fn is_done() Bool:
        return self.done.get()
