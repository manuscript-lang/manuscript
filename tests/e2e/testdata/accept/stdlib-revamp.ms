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
    let a = Key(1, "first")
    let b = Key(1, "second")
    if not (a == b): return panic("custom equality ignored")
    if not (a.hash() == b.hash()): return panic("custom hash ignored")

    let values = (Map[Key, String]().add(a, "a").add(b, "b"))
    if values.length() != 1: return panic("custom key lookup ignored")
    if values.get(a) != some("b"): return panic("custom key update ignored")
    if not ([a].contains(b)): return panic("custom search ignored")

    let view = Equal(Equal(a))
    if not (view.equals(Equal(b))): return panic("interface view ignored")

test "stable priority queue and optional capacity":
    let queue = PriorityQueue(compare)
    queue.enqueue(Key(2, "later"))
    queue.enqueue(Key(1, "first"))
    queue.enqueue(Key(1, "second"))

    if let value = queue.dequeue():
        if value.label != "first": return panic("priority order")
    else:
        return panic("missing item")

    if let value = queue.dequeue():
        if value.label != "second": return panic("unstable priority order")
    else:
        return panic("missing item")

    let bounded = PriorityQueue(compare, 1)
    if not (bounded.enqueue(Key(1, "only"))): return panic("enqueue failed")
    if bounded.enqueue(Key(0, "full")): return panic("capacity ignored")

test "limits can be omitted or supplied":
    let repeated = try "ab".repeat(3)
    if repeated != "ababab": return panic("omitted limit failed")
    if "ab".repeat(3, 5).is_ok(): return panic("supplied limit ignored")

fn operation() Result[Unit, Error]: ok(unit)

test "one scheduler admits and schedules work":
    with scheduler = Scheduler():
        let _immediate = scheduler.start(operation)
        let _delayed = scheduler.after(0.milliseconds, operation)
        let repeated = try scheduler.every(1.milliseconds, operation)
        scheduler.cancel(repeated)

type EmptyReader:
    requested: Int

impl ReadStream for EmptyReader:
    fn read(max_bytes: Optional[Int]) Result[Optional[Bytes], IoError]:
        self.requested = max_bytes.get(0)
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

    let _line = read_line(stream)
    if reader.requested != 1: return panic(
        "native helper bypassed the interface contract"
    )
