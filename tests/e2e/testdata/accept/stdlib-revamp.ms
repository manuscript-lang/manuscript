import {ReadStream, IoError, read_line} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import panic from "@std/faults.ms"
import {List, Map} from "@std/collections.ms"
import {Equal, Hashable} from "@std/equality.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import Optional from "@std/optional.ms"
import {Scheduler, WorkStatus} from "@std/tasks.ms"
import {Result} from "@std/result.ms"
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
    if not (a == b): return panic("custom equality ignored")
    if not (a.hash() == b.hash()): return panic("custom hash ignored")

    let values = (
        Map[Key, String]()
        .with_entry(key: a, value: "a")
        .with_entry(key: b, value: "b")
    )
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

    match queue.dequeue():
        some(value):
            if value.label != "first": return panic("priority order")

        none: return panic("missing item")

    match queue.dequeue():
        some(value):
            if value.label != "second": return panic("unstable priority order")

        none: return panic("missing item")

    let bounded = PriorityQueue(
        compare: compare,
        capacity: 1
    )
    if not (bounded.enqueue(Key(id: 1, label: "only"))): return panic("enqueue failed")
    if bounded.enqueue(Key(id: 0, label: "full")): return panic("capacity ignored")

test "limits can be omitted or supplied":
    match "ab".repeat(count: 3):
        ok(value):
            if value != "ababab": return panic("omitted limit failed")

        error(_): return panic("omitted limit rejected")

    match "ab".repeat(
        count: 3,
        max_bytes: 5
    ):
        ok(_): return panic("supplied limit ignored")
        error(_): return

fn operation() -> Result[Unit, String]: ok(unit)

test "one scheduler admits and schedules work":
    with scheduler = Scheduler():
        let immediate = scheduler.start(operation)
        let delayed = scheduler.after(duration: 0.milliseconds, operation: operation)
        let repeated = scheduler.every(interval: 1.milliseconds, operation: operation)

        match repeated:
            ok(id): scheduler.cancel(id)
            error(_): return panic("unbounded admission failed")

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
    if reader.requested != 0: return panic(
        "omitted limit did not reach the source implementation"
    )

    let supplied = stream.read(8)
    if reader.requested != 8: return panic("supplied limit was not an Optional")

    let line = read_line(input: stream)
    if reader.requested != 1: return panic(
        "native helper bypassed the interface contract"
    )
