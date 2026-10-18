import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import {ReadStream, IoError, read_line} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import {Scheduler, WorkStatus} from "@std/tasks.ms"
import {sleep} from "@std/time.ms"
import {parse, JsonValue} from "@std/json.ms"

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() -> Int: self.id

fn compare(left: Key, right: Key) -> Int:
    return left.id - right.id

test "domain equality and hashing select interfaces":
    let a = Key(id: 1, label: "first")
    let b = Key(id: 1, label: "second")
    a | try expect_equal(expected: b)
    a.hash() | try expect_equal(expected: b.hash())
    let values = (Map[Key, String]().add(key: a, value: "a").add(key: b, value: "b"))
    values.length() | try expect_equal(expected: 1)
    values.get(a) | try expect_equal(expected: some("b"))
    ([a].contains(b)) | try expect_true
    let view = Equal(Equal(a))
    (view.equals(Equal(b))) | try expect_true

test "stable priority queue and optional capacity":
    let queue = PriorityQueue(compare: compare)
    queue.enqueue(Key(id: 2, label: "later"))
    queue.enqueue(Key(id: 1, label: "first"))
    queue.enqueue(Key(id: 1, label: "second"))

    match queue.dequeue():
        some(value):
            try expect_equal(value.label, "first")
        none: return fail("missing item")

    match queue.dequeue():
        some(value):
            try expect_equal(value.label, "second")
        none: return fail("missing item")

    let bounded = PriorityQueue(compare: compare, capacity: 1)
    (bounded.enqueue(Key(id: 1, label: "only"))) | try expect_true
    bounded.enqueue(Key(id: 0, label: "full")) | try expect_false

test "limits can be omitted or supplied":
    match "ab".repeat(count: 3):
        ok(value):
            try expect_equal(value, "ababab")
        error(_): return fail("omitted limit rejected")

    match "ab".repeat(count: 3, max_bytes: 5):
        ok(_): return fail("supplied limit ignored")
        error(_): return

fn operation() -> Result[Unit, Error]: ok(unit)

test "one scheduler admits and schedules work":
    with scheduler = Scheduler():
        let immediate = scheduler.start(operation)
        let delayed = scheduler.after(duration: 0.milliseconds, operation: operation)
        let repeated = scheduler.every(interval: 1.milliseconds, operation: operation)

        match repeated:
            ok(id): scheduler.cancel(id)
            error(_): return fail("unbounded admission failed")

type EmptyReader:
    requested: Int

impl ReadStream for EmptyReader:
    fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        match max_bytes:
            none: self.requested = 0
            some(value): self.requested = value

        return ok(none)

    fn close() -> Unit: unit

test "native compositions preserve Optional arguments for source implementations":
    let reader = EmptyReader(-1)
    let stream = ReadStream(reader)
    let omitted = stream.read()
    reader.requested | try expect_equal(expected: 0)
    let supplied = stream.read(8)
    reader.requested | try expect_equal(expected: 8)
    let line = read_line(input: stream)
    reader.requested | try expect_equal(expected: 1)
