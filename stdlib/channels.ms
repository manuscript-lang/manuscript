# Two-way channels between a group and the work it starts.
#
# A `Channel[In, Out]` sends `In` values and receives `Out` values. Channels are made by a group's
# `spawn`: the started work gets one end, a `Channel[Out, In]`, and the handle `spawn` returns holds
# the other in its `channel` field. Values move through it; `.clone()` gives another handle on the same end.
# `TaskGroup` (`@std/tasks.ms`) carries the channel types as `TaskGroup[T, In, Out]`, both `Unit`
# unless given.
# Why a channel could not send or receive.
export type ChannelError:
    # This end, or the other end, was closed: nothing more can be sent, or received here.
    case Closed
    # The channel cannot carry messages any more.
    case Broken(
        # Why, for example that the other end's process exited.
        reason: String
    )

impl Error for ChannelError:
    # Returns the fixed diagnostic `channel: closed` or `channel: broken: <reason>`.
    fn message() String:
        match self:
            Closed: return "channel: closed"
            Broken(reason): return "channel: broken: " + reason

# How one end of a channel moves values. Each kind of group provides its own; use `Channel`.
export interface Transport[In, Out]:
    # Sends `value`, waiting while the other end has too many unread values.
    fn send(value: In) Result[Unit, ChannelError]
    # Waits for the next value. `ok(none)` means the other end closed and every value was read.
    fn receive() Result[Optional[Out], ChannelError]
    # Closes this end. Safe to call again.
    var fn close() Unit

# One end of a two-way channel: sends `In`, receives `Out`. `spawn` makes both ends.
# A send waits while the other end has many unread values; a receive waits for the next one.
# After either end closes, the other end still receives what was sent before, then `ok(none)`,
# and its sends give `error(ChannelError.Closed)`. Using an end after closing it gives `Closed`.
# An end is a handle on shared state, so `send` and `receive` work on a `let` binding or a plain parameter; only `close` needs `var`.
export type Channel[In, Out]:
    # Internal state: how this end moves values.
    transport: Transport[In, Out]

impl Channel[In, Out]:
    # Sends `value` to the other end, waiting while it has many unread values.
    # Gives `Closed` once either end is closed.
    fn send(value: In) Result[Unit, ChannelError]:
        return self.transport.send(value)

    # Waits for the next value from the other end. Gives `ok(none)` once the other end closed and
    # every value it sent was read, and `Closed` once this end is closed.
    fn receive() Result[Optional[Out], ChannelError]:
        return self.transport.receive()

    # Closes this end: the other end reads what is left, then `ok(none)`. Safe to call again.
    var fn close() Unit:
        self.transport.close()
