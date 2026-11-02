import Closeable, panic from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import ReadStream, IoError from "@std/io/io.ms"
import TaskGroup, TaskError from "@std/concurrency/tasks.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import Duration, nanoseconds, sleep from "@std/os/time.ms"
import expect_equal, expect_true from "@std/test/test.ms"

type Probe:
    events: Shared[List[Int]]
    action: Int
    label: Int

impl ReadStream for Probe:
    var fn read(max_bytes: Int?) Bytes?!IoError:
        if self.action == 1: sleep(nanoseconds(500000000))
        if self.action == 2: panic("source read failed")
        return ok(none)

    var fn close() Unit:
        var events = lock(self.events)
        events.value.append(self.label)
        events.close().get()
        if self.action == 3: panic("source close failed")
        return unit

type Wrapper:
    input: ReadStream

impl Closeable for Wrapper:
    var fn close() Unit!:
        self.input.close()
        return ok(unit)

impl Wrapper:
    var fn read() Bytes?!IoError:
        return self.input.read()

    var fn conditional_read(choice: Bool) Bytes?!IoError:
        if choice: return self.input.read(1)

        return self.input.read(2)

fn run_wrapped(events: Shared[List[Int]], action: Int, conditional: Bool) Int:
    let _first = Wrapper(Probe(events, 0, 1))
    var last = Wrapper(Probe(events, action, 2))
    let result = if conditional: last.conditional_read(events.get().length() == 0) else: last.read()
    return if result.is_ok(): 0 else: 1

fn check_wrapped(action: Int, conditional: Bool) Unit!:
    let events: Shared[List[Int]] = share([])
    let captured = events
    var timeout: Duration? = none
    if action == 1: timeout = nanoseconds(20000000)

    var group = TaskGroup[Int](timeout: timeout, contain_faults: true)
    let task = group.spawn(fn channel: run_wrapped(captured, action, conditional))
    let result = task.result()

    if action == 0:
        try expect_equal(result, ok(0))
    else if action == 1:
        try expect_equal(result.err(), TaskError.TimedOut)
    else:
        let expected = if action == 2: "source read failed" else: "source close failed"
        try expect_true(result.err().message().contains(expected))

    try group.close()
    try expect_equal(events.get(), [2, 1])
    return ok(unit)

test "cancelled reads keep scope-closed interface receivers alive":
    for conditional in [false, true]:
        try check_wrapped(1, conditional)

test "guarded read faults close interface wrappers in reverse order":
    for conditional in [false, true]:
        try check_wrapped(2, conditional)

test "normal reads close each interface wrapper exactly once":
    for conditional in [false, true]:
        try check_wrapped(0, conditional)

test "faults during normal close retain remaining scope cleanup":
    for conditional in [false, true]:
        try check_wrapped(3, conditional)
