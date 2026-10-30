import Closeable from "@std/core.ms"

extern fn msrt_channel_token() Int

extern fn msrt_channel_park(token: Int) Unit

extern fn msrt_waitq_push(key: Int, token: Int) Unit

extern fn msrt_waitq_wake(key: Int) Int

extern fn msrt_waitq_remove(key: Int, token: Int) Int

# A value several holders share. Copying a `Lock` shares the value instead of duplicating it; the
# value is freed with the last holder. Any number of holders read it with `get`. To change it, one
# holder at a time takes it with `lock()` into a `var` binding: `var held = box.lock()`, then change
# `held.value`; it is handed back when the binding's scope ends, however it ends. `take`, `put`,
# `locked` and `id` are the primitives `lock` is built on; calling them elsewhere is rejected.
export type Lock[T]: ...

# Moves `value` into a new `Lock` with one holder; copy the result to add holders.
export fn new_lock[T](value: T) Lock[T]: ...

impl Lock[T]:
    # Reads the value in place; the result borrows from this `Lock`. Faults while it is locked.
    fn get() ref T: ...

    # The identity of this lock, the same for every copy of the handle. Internal to `lock`.
    fn id() Int: ...

    # Whether the value is out. Internal to `lock`.
    fn locked() Bool: ...

    # Moves the value out and marks this `Lock` in use. Faults if it is already out. Internal to
    # `lock`.
    fn take() T: ...

    # Moves a value back after `take`. Faults if nothing was taken. Internal to `Locked.close`.
    fn put(value: T) Unit: ...

# The value of a `Lock` while one holder changes it, held until the scope of the binding that
# opened it ends, or its `close()` is called. Change the value through `value`.
export type Locked[T]:
    # Internal state: the lock the value returns to.
    box: Lock[T]
    # The value while locked.
    value: T
    # Internal state: false once the value was returned.
    held: Bool

impl Closeable for Locked[T]:
    # Returns the value to the lock, also when the task is cancelled or faults inside the block.
    # Closing again does nothing.
    var fn close() Unit:
        if self.held:
            self.held = false
            self.box.put(self.value)
            msrt_waitq_wake(self.box.id())

# A waiting task's place in the queue of a lock. Closing it matters only when the wait was cut short.
type Ticket:
    # The lock the task waits for.
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

impl Lock[T]:
    # Takes the value for changing and returns the guard that holds it. Waits while another holder
    # has it, and stops waiting if the task is cancelled. Bind it with `var`; the scope end hands it
    # back: `var held = box.lock()`, then change `held.value`.
    fn lock() Locked[T]:
        return acquire(self)

# Waits until `box` is free, then takes its value into a guard.
fn acquire[T](box: Lock[T]) Locked[T]:
    while box.locked():
        let key = box.id()
        let token = msrt_channel_token()
        msrt_waitq_push(key, token)

        var ticket = Ticket(key: key, token: token, parked: true)
        msrt_channel_park(token)
        ticket.parked = false

    return Locked[T](box: box, value: box.take(), held: true)
