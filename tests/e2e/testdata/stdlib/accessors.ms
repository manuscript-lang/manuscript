import {Queue, PriorityQueue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {ClientResponse, HttpResponseMetadata, headers} from "@std/http.ms"
import {duration, timestamp} from "@std/time.ms"
import panic from "@std/faults.ms"

interface Counted:
    get observed -> Int

type Counter:
    calls: Int
    reads: Int
    items: List[Int]

impl Counted for Counter:
    get observed -> Int:
        self.reads = self.reads + 1
        return self.items.length

fn receiver(counter: Counter) -> Counter:
    counter.calls = counter.calls + 1
    return counter

fn compare(left: List[Int], right: List[Int]) -> Int:
    return left.length - right.length

test "receivers evaluate once and source reads remain live":
    let counter = Counter(0, 0, [])
    if receiver(counter).observed != 0 or counter.calls != 1 or counter.reads != 1:
        return panic("receiver or accessor executed the wrong number of times")

    counter.items.append(7)
    if counter.observed != 1 or counter.reads != 2:
        return panic("source accessor cached its result")
    if false and counter.observed == 1:
        return panic("unreachable branch")

    if true or counter.observed == 1:
        let skipped = true

    if counter.reads != 2:
        return panic("short circuit evaluated an accessor")

test "collection accessors preserve absence and mutable result aliases":
    let items: List[List[Int]] = []
    let absent: Optional[List[Int]] = none
    if items.first != absent or items.last != absent or not items.is_empty:
        return panic("empty list accessors")

    let original = [7]
    items.append(original)
    items.first.unwrap().append(8)
    if original != [7, 8] or items.last.unwrap() != original or items.length != 1:
        return panic("list accessor copied its mutable payload")

    let nested: List[Optional[Int]] = [none]
    let present_absent: Optional[Optional[Int]] = some(none)
    if nested.first != present_absent:
        return panic("accessor flattened Optional absence")

    let queue = Queue[List[Int]]()
    queue.enqueue(original)
    queue.peek.unwrap().append(9)
    if queue.length != 1 or queue.dequeue() != some(original) or original.length != 3:
        return panic("queue peek consumed or copied")

    let priority = PriorityQueue[List[Int]](compare)
    priority.enqueue(original)
    priority.peek.unwrap().append(10)
    if (
        priority.length != 1
        or priority.dequeue() != some(original)
        or original.length != 4
    ):
        return panic("priority peek consumed or copied")

test "metadata accessor aliases the current replaceable head":
    let first = HttpResponseMetadata(200, headers())
    let response = ClientResponse(first, "".to_bytes())
    let saved = response.metadata
    response.metadata.status = 201
    if saved.status != 201:
        return panic("metadata accessor copied its head")

    let replacement = HttpResponseMetadata(202, headers())
    response.head = replacement
    response.metadata.status = 203
    if (
        response.metadata.status != 203
        or replacement.status != 203
        or saved.status != 201
    ):
        return panic("metadata accessor used a stale head")

test "guard value aliases the protected payload on every read":
    let shared = Synchronized([1])

    with guard = shared.lock():
        let payload = guard.value
        guard.value.append(2)
        if payload != [1, 2]:
            return panic("guard accessor copied payload")

        guard.set([3])
        if guard.value != [3] or payload != [1, 2]:
            return panic("guard accessor cached payload")

test "duration unit projections preserve negative truncation and fractions":
    let negative = duration(-1500001)
    if (
        negative.nanoseconds != -1500001
        or negative.microseconds != -1500
        or negative.milliseconds != -1
    ):
        return panic("duration integer projection")
    if (
        duration(1500000000).seconds != 1.5
        or 90.seconds.minutes != 1.5
        or 90.minutes.hours != 1.5
    ):
        return panic("duration fractional projection")

    let instant = timestamp(-1, 500000000).unwrap()
    if instant.unix_seconds != -1 or instant.nanoseconds != 500000000:
        return panic("timestamp components")

import filesystem from "@std/fs.ms"

test "directory path accessors retain post-close availability":
    let fs = filesystem()
    let temporary = fs.temporary("accessor-path-").unwrap()
    let temporary_path = temporary.path
    let directory = fs.open_directory(temporary_path).unwrap()
    let directory_path = directory.path
    directory.close()
    if directory.path != directory_path:
        return panic("closed directory lost path")

    temporary.close()
    if temporary.path != temporary_path:
        return panic("closed temporary directory lost path")
