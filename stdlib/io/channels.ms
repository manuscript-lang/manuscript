# How one end of a channel moves values. Each kind of group provides its own; use `Channel`.
export interface Transport[In, Out]:
    # Sends `value`, waiting while the other end has too many unread values.
    fn send(value: In) Unit!
    # Waits for the next value. `ok(none)` means the other end closed and every value was read.
    fn receive() Out?!
    # Closes this end. Safe to call again.
    var fn close() Unit

# One end of a two-way channel: sends `In`, receives `Out`. `spawn` makes both ends.
# A send waits while the other end has many unread values; a receive waits for the next one.
# After either end closes, the other end still receives what was sent before, then `ok(none)`,
# and its sends give an `Error` of kind `Closed`. Using an end after closing it gives `Closed`.
# An end is a handle on shared state, so `send` and `receive` work on a `let` binding or a plain parameter; only `close` needs `var`.
export type Channel[In, Out]:
    # Internal state: how this end moves values.
    transport: Transport[In, Out]

impl Channel[In, Out]:
    # Sends `value` to the other end, waiting while it has many unread values.
    # Gives `Closed` once either end is closed.
    fn send(value: In) Unit!:
        return self.transport.send(value)

    # Waits for the next value from the other end. Gives `ok(none)` once the other end closed and
    # every value it sent was read, and `Closed` once this end is closed.
    fn receive() Out?!:
        return self.transport.receive()

    # Closes this end: the other end reads what is left, then `ok(none)`. Safe to call again.
    var fn close() Unit:
        self.transport.close()
