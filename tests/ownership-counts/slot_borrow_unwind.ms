# A scalar result cannot borrow a container's storage. Cancelling a call through a mutable
# container slot must drop the container, even when that scalar was put in a record or returned.
# A scalar field update preserves owned resources; an owned field replacement must finish
# before a later normal close can register a fresh cleanup snapshot.
import Closeable, panic from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import ReadStream, IoError from "@std/io/io.ms"
import Channel from "@std/io/channels.ms"
import TaskGroup, TaskError from "@std/concurrency/tasks.ms"

type Summary:
    length: Int

fn summarize_and_wait(var values: List[String], gate: Channel[Bool, Unit]) Int:
    let summary = Summary(values.length())
    gate.send(true).get()
    gate.receive().get()
    return summary.length

fn blocked(gate: Channel[Bool, Unit]) Int:
    var values = ["retained payload ".repeat(8).get()]
    return summarize_and_wait(var values, gate)

type ScalarResource:
    payload: String
    closed: Bool = false

impl Closeable for ScalarResource:
    var fn close() Unit!:
        self.closed = true
        panic("scalar close fault")

fn scalar_work() Int:
    var resource = ScalarResource("retained payload ".repeat(8).get())
    return resource.payload.byte_length()

type Source:
    payload: String

impl ReadStream for Source:
    var fn read(max_bytes: Int?) Bytes?!IoError:
        return ok(none)

    var fn close() Unit:
        panic("wrapper close fault")

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

fn wrapper_work() Int:
    var rows = Wrapper(Source("retained payload ".repeat(8).get()), Bytes([]))
    let result = rows.read()
    return if result.is_ok(): 0 else: 1

fn faulting_work(action: Int) Int:
    if action == 0: return scalar_work()

    return wrapper_work()

fn check_cancellation() Int:
    var group = TaskGroup[Int, Unit, Bool](contain_faults: true)
    let task = group.spawn(fn channel: blocked(channel))
    if not task.channel.receive().get().get(false): return 1

    group.close().get()
    if task.result().err() != TaskError.Closed: return 2

    return 0

export fn main() Int:
    if check_cancellation() != 0: return 1

    for action in [0, 1]:
        var group = TaskGroup[Int](contain_faults: true)
        let task = group.spawn(fn channel: faulting_work(action))
        let result = task.result()
        if result.is_ok(): return 2

        let expected = if action == 0: "scalar close fault" else: "wrapper close fault"
        if not result.err().message().contains(expected): return 3

        group.close().get()

    return 0
