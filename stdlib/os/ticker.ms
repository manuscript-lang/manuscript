import panic from "@std/core.ms"
import Duration, Instant, monotonic, nanoseconds, sleep from "@std/os/time.ms"
import ReadStream, Source, stream from "@std/io/stream.ms"

/*
A source of evenly spaced instants, for loops that run work on a schedule.
Each read suspends the task until the next tick; stop by dropping the stream. Ticks do not drift
with the loop body: a body slower than the period gets the next tick at once, and the ticks it missed are dropped.
*/
type TickSource:
    // The time between ticks.
    period: Duration
    // The instant of the next tick.
    due: Instant

impl Source[Instant] for TickSource:
    // Waits for the next tick and returns the instant it was due; never ends.
    var fn next() Instant?!:
        let tick = self.due.clone()
        sleep(tick.difference(monotonic()).max(nanoseconds(0)))
        self.due = tick.shift(self.period.clone()).max(monotonic())
        return ok(tick)

    var fn close() Unit!:
        return ok(unit)

// Returns a ticker whose first tick comes one `period` from now. A period of zero or less is a programming fault.
export fn ticker(period: Duration) ReadStream[Instant]:
    if period.compare(nanoseconds(0)) <= 0:
        panic("ticker: period must be positive")

    let due = monotonic().shift(period.clone())
    return stream[Instant](TickSource(period: period, due: due))
