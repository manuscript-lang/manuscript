import {ReadStream, IoError, read_line} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import {PriorityQueue} from "@std/queues.ms"
import {Scheduler} from "@std/tasks.ms"

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() Int: self.id

fn compare(left: Key, right: Key) Int:
    return left.id - right.id

test "domain equality and hashing select interfaces":
    let a = Key(id: 1, label: "first")
    let b = Key(id: 1, label: "second")
    if not (a == b): return panic("custom equality ignored")
    if not (a.hash() == b.hash()): return panic("custom hash ignored")

    let values = (Map[Key, String]().add(key: a, value: "a").add(key: b, value: "b"))
    if values.length() != 1: return panic("custom key lookup ignored")
    if values.get(a) != some("b"): return panic("custom key update ignored")
    if not ([a].contains(b)): return panic("custom search ignored")

    let view = Equal(Equal(a))
    if not (view.equals(Equal(b))): return panic("interface view ignored")

test "stable priority queue and optional capacity":
    let queue = PriorityQueue(compare: compare)
    queue.enqueue(Key(id: 2, label: "later"))
    queue.enqueue(Key(id: 1, label: "first"))
    queue.enqueue(Key(id: 1, label: "second"))

    if let value = queue.dequeue():
        if value.label != "first": return panic("priority order")
    else:
        return panic("missing item")

    if let value = queue.dequeue():
        if value.label != "second": return panic("unstable priority order")
    else:
        return panic("missing item")

    let bounded = PriorityQueue(compare: compare, capacity: 1)
    if not (bounded.enqueue(Key(id: 1, label: "only"))): return panic("enqueue failed")
    if bounded.enqueue(Key(id: 0, label: "full")): return panic("capacity ignored")

test "limits can be omitted or supplied":
    let repeated = try "ab".repeat(count: 3)
    if repeated != "ababab": return panic("omitted limit failed")
    if not "ab".repeat(count: 3, max_bytes: 5).is_error():
        return panic("supplied limit ignored")

fn operation() Result[Unit, Error]: ok(unit)

test "one scheduler admits and schedules work":
    with scheduler = Scheduler():
        let _immediate = scheduler.start(operation)
        let _delayed = scheduler.after(duration: 0.milliseconds, operation: operation)
        let repeated = try scheduler.every(
            interval: 1.milliseconds,
            operation: operation
        )
        scheduler.cancel(repeated)

type EmptyReader:
    requested: Int

impl ReadStream for EmptyReader:
    fn read(max_bytes: Optional[Int]) Result[Optional[Bytes], IoError]:
        self.requested = max_bytes.unwrap_or(0)
        return ok(none)

    fn close() Unit: unit

test "native compositions preserve Optional arguments for source implementations":
    let reader = EmptyReader(-1)
    let stream = ReadStream(reader)
    let _omitted = stream.read()
    if reader.requested != 0: return panic(
        "omitted limit did not reach the source implementation"
    )

    let _supplied = stream.read(8)
    if reader.requested != 8: return panic("supplied limit was not an Optional")

    let _line = read_line(input: stream)
    if reader.requested != 1: return panic(
        "native helper bypassed the interface contract"
    )
