# conform: tags=control-flow,faults,interfaces,maps,match,modules,optional,records,stdlib-bytes,stdlib-io,stdlib-queues,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/stdlib-revamp.ms
import expect_equal, expect_false, fail from "@std/test.ms"
import ReadStream, IoError, read_line from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import PriorityQueue from "@std/queue.ms"

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

impl Hashable for Key:
    fn hash() Int: self.id

impl Comparable for Key:
    fn compare(other: Key) Int:
        return self.id - other.id

test "domain equality and hashing select interfaces":
    let a = Key(1, "first")
    let b = Key(1, "second")
    try expect_equal(a, b)
    try expect_equal(a.hash(), b.hash())

    var values = Map[Key, String]()
    values.add(a.clone(), "a")
    values.add(b.clone(), "b")
    try expect_equal(values.length(), 1)
    try expect_equal(values.get(a), "b")
    try expect_false(not ([a.clone()].contains(b)))

    let view: Equal = a
    try expect_false(not (view.equals(b)))

test "stable priority queue and optional capacity":
    var queue = PriorityQueue[Key]()
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

    var bounded = PriorityQueue[Key](1)
    try expect_false(not (bounded.enqueue(Key(1, "only"))))
    try expect_false(bounded.enqueue(Key(0, "full")))

test "limits can be omitted or supplied":
    let repeated = try "ab".repeat(3)
    try expect_equal(repeated, "ababab")
    try expect_false("ab".repeat(3, 5).is_ok())

type EchoReader:
    unused: Int

impl ReadStream for EchoReader:
    var fn read(max_bytes: Int?) Result[Bytes?, IoError]:
        let requested = max_bytes.get(0)
        if requested == 1: return error(IoError.InvalidInput)

        return ok(Bytes([requested.to_uint8().get(0)]))

    fn close() Unit: unit

test "native compositions preserve Optional arguments for source implementations":
    var stream: ReadStream = EchoReader(0)
    let omitted: Result[Bytes?, IoError] = stream.read()
    try expect_equal(omitted, ok(Bytes([0])))

    let supplied: Result[Bytes?, IoError] = stream.read(8)
    try expect_equal(supplied, ok(Bytes([8])))

    let line = read_line(stream)
    try expect_false(line.is_ok())
