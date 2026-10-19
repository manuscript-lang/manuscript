import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {ReadStream, IoError, read_line} from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import {PriorityQueue} from "@std/queues.ms"

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
    try expect_equal(a, b)
    try expect_equal(a.hash(), b.hash())
    let values = (Map[Key, String]().add(a, "a").add(b, "b"))
    try expect_equal(values.length(), 1)
    try expect_equal(values.get(a), some("b"))
    try expect_false(not ([a].contains(b)))
    let view = Equal(Equal(a))
    try expect_false(not (view.equals(Equal(b))))

test "stable priority queue and optional capacity":
    let queue = PriorityQueue(compare)
    queue.enqueue(Key(2, "later"))
    queue.enqueue(Key(1, "first"))
    queue.enqueue(Key(1, "second"))

    if let value = queue.dequeue():
        try expect_equal(value.label, "first")
    else:
        return fail("missing item")

    if let value = queue.dequeue():
        try expect_equal(value.label, "second")
    else:
        return fail("missing item")

    let bounded = PriorityQueue(compare, 1)
    try expect_false(not (bounded.enqueue(Key(1, "only"))))
    try expect_false(bounded.enqueue(Key(0, "full")))

test "limits can be omitted or supplied":
    let repeated = try "ab".repeat(3)
    try expect_equal(repeated, "ababab")
    try expect_false("ab".repeat(3, 5).is_ok())

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
    try expect_equal(reader.requested, 0)
    let _supplied = stream.read(8)
    try expect_equal(reader.requested, 8)
    let _line = read_line(stream)
    try expect_equal(reader.requested, 1)
