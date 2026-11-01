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
# change the values kept in its `Shared` fields. Every call on the value runs one at a time: while a
# call that waits is in progress, another task's access waits its turn, and an access from the same
# task (a callback, or a second handle) faults. Keep changes that must not interleave in one method
# of the value's type. A cancelled call keeps the changes it made so far.
#
# Copying a handle adds a holder; the last holder to go drops the value and closes it when it is a
# resource. Assigning a value replaces the shared value (`names = ["a"]`); assigning a handle points
# the binding at another value (`names = other`).
export extern type Shared[T]

impl Proxy for Shared[T]:
