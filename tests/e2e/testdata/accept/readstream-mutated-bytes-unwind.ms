import Closeable, panic from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import ReadStream, IoError from "@std/io/io.ms"
import Channel from "@std/io/channels.ms"
import TaskGroup, TaskError, cancelled from "@std/concurrency/tasks.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import expect_equal, expect_true from "@std/test/test.ms"

type Source:
    closes: Shared[Int]
    cancelled_close: Shared[Bool]
    gate: Channel[Bool, Unit]
    action: Int

impl ReadStream for Source:
    var fn read(max_bytes: Int?) Bytes?!IoError:
        if self.action == 1:
            self.gate.send(true).get()
            self.gate.receive().get()
            panic("source read resumed instead of being cancelled")

        if self.action == 2: panic("source read fault")
        return ok(none)

    var fn close() Unit:
        var count = lock(self.closes)
        count.value += 1
        count.close().get()

        if self.action == 1:
            var state = lock(self.cancelled_close)
            state.value = cancelled()
            state.close().get()

        if self.action == 3: panic("source close fault")
        return unit

type Wrapper:
    input: ReadStream
    pending: Bytes

impl Closeable for Wrapper:
    var fn close() Unit!:
        self.input.close()
        return ok(unit)

impl Wrapper:
    var fn read() Bytes?!IoError:
        self.pending = Bytes([7, 8, 9])
        return self.input.read(8192)

fn run(
    closes: Shared[Int],
    cancelled_close: Shared[Bool],
    gate: Channel[Bool, Unit],
    action: Int
) Int:
    var rows = Wrapper(Source(closes, cancelled_close, gate, action), Bytes([]))
    let result = rows.read()
    return if result.is_ok(): 0 else: 1

fn check(action: Int) Unit!:
    let closes = share(0)
    let cancelled_close = share(false)
    let captured = closes
    let observed = cancelled_close
    var group = TaskGroup[Int, Unit, Bool](contain_faults: true)
    let task = group.spawn(fn channel: run(captured, observed, channel, action))

    if action == 1:
        let entered = try task.channel.receive()
        try expect_true(entered.get(false))
        try group.close()
        try expect_true(cancelled_close.get())

    let result = task.result()

    if action == 0:
        try expect_equal(result, ok(0))
    else if action == 1:
        try expect_equal(result.err(), TaskError.Closed)
    else:
        let expected = if action == 2: "source read fault" else: "source close fault"
        try expect_true(result.err().message().contains(expected))

    try group.close()
    try expect_equal(closes.get(), 1)
    return ok(unit)

test "normal":
    try check(0)

test "cancellation":
    try check(1)

test "read fault":
    try check(2)

test "close fault":
    try check(3)
