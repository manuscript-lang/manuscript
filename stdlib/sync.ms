import Closeable from "@std/core.ms"
import Shared from "@std/shared.ms"

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
    var fn close() Unit:
        if self.held:
            self.held = false
            self.box.put(self.value)
            msrt_waitq_wake(self.box.id())

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
    var fn close() Unit:
        if self.parked:
            if msrt_waitq_remove(self.key, self.token) == 0:
                msrt_waitq_wake(self.key)

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
