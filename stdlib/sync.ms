from "@std/core.ms" import Closeable
from "@std/shared.ms" import Shared
from "@std/time.ms" import duration, sleep

# The locked payload of a `Shared`, held until the `with` block that opened it ends. Change the
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
    var def close() -> Unit:
        if self.held:
            self.held = False
            self.box.put(self.value)

# Locks `box` and returns the guard that holds its payload. Waits while another guard holds it,
# and stops waiting if the task is cancelled. Use it with `with var`, which closes the guard:
#
# ```
# with var guard = lock(box):
#     guard.value.append(1)
# ```
export def lock[T](box: Shared[T]) -> SharedGuard[T]:
    while box.locked():
        sleep(duration(50000))
    return SharedGuard[T](box: box, value: box.take(), held: True)
