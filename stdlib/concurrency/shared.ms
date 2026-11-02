import Proxy from "@std/core.ms"

# One value that several owners hold at once, for state shared by the tasks of one program. Make one
# with `Shared(value)` and use it like the value itself: its fields, `[i]` and methods are reached
# through the handle, and where the value's type is expected the handle gives the value.
#
# ```
# var stats = Shared(Stats(hits: 0, names: []))
# let view = stats            # another holder of the same value
# stats.hits += 1             # a var handle changes the one value
# stats.record("ada")         # a var fn runs alone on the value
# view.hits                   # 1: every holder reads the current value
# ```
#
# A `var` handle can change the value and a `let` handle only reads it; a type's own methods can
# change the values kept in its `Shared` fields. Calls that read the value run together, and a call
# that changes it runs alone: while a call that waits is in progress, a change from another task
# waits for every read to end, and a read waits for the change. A read from the same task inside a
# call on the value (a callback, or a second handle) sees the value as it is. A callback that
# changes the value a call is using is a compile error; the callback takes it as a `var`
# parameter instead. A change the checker cannot see, through a callback stored in a value,
# faults. Keep
# changes that must not interleave in one method of the value's type. A cancelled call keeps the
# changes it made so far. A reference a call returns into the value is copied out, so it stays valid
# after the value changes.
#
# Copying a handle adds a holder; the last holder to go drops the value and closes it when it is a
# resource. Assigning a value replaces the shared value (`names = ["a"]`); assigning a handle points
# the binding at another value (`names = other`).
export extern type Shared[T]

impl Proxy for Shared[T]:
