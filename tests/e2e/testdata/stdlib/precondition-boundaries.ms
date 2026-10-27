from "@std/test.ms" import expect_equal, expect_false
from "@std/bytes.ms" import Bytes, BytesBuilder
from "@std/queue.ms" import PriorityQueue, Queue
from "@std/math.ms" import from_int
from "@std/math.ms" import parse_int, NumberError

def compare(left: Int, right: Int) -> Int: left - right

test "byte updates retain relative bounds and immutable storage":
    let bytes = Bytes([0, 255])
    try expect_equal(bytes.with_value(-2, 255), Bytes([255, 255]))
    try expect_equal(bytes.with_value(1, 0), Bytes([0, 0]))
    try expect_equal(bytes, Bytes([0, 255]))
    try expect_equal(bytes.get(-3, default: -1), -1)
    try expect_equal(bytes.get(2, default: -1), -1)
    try expect_equal(bytes.slice(2, 2).get(), Bytes([]))

    var builder = BytesBuilder()
    builder.append(0)
    builder.append(255)
    try expect_equal(builder.build(), bytes)

test "list boundaries retain mutation truncation and empty ranges":
    var list = [1, 2]
    list.set(-2, 0)
    try expect_equal(list, [0, 2])
    list.remove(-1)
    try expect_false(list != [0] or list != [0])
    list.splice(1, 0, [1, 2])
    list.fill(9, 3, 3)
    list.copy_within(3, 0, 3)
    try expect_equal(list, [0, 1, 2])
    list.copy_within(2, 0, 3)
    try expect_equal(list, [0, 1, 0])
    list.splice(0, 3, [])
    list.fill(1, 0, 0)
    list.copy_within(0, 0, 0)
    list.splice(0, 0, [])
    try expect_equal(list.length(), 0)
    try expect_equal(list.get(0, default: -1), -1)

test "radix formatting retains inclusive boundaries and parse errors":
    try expect_false(
        ((35).to_string_radix(2) != "100011" or (35).to_string_radix(36) != "z")
    )

    let big = from_int(35)
    try expect_false(
        (big.to_string_radix(2) != "100011" or big.to_string_radix(36) != "z")
    )

    let invalid: Result[Int, NumberError] = error(NumberError.InvalidInput)
    try expect_equal(parse_int("1", 1), invalid)
    try expect_false(not "invalid".parse_int().is_none())

test "queue capacities retain omission none minimum maximum and full results":
    var queue = Queue[Int](1)
    try expect_false(not queue.enqueue(1) or queue.enqueue(2))
    try expect_false(queue.dequeue() != some(1) or not queue.dequeue().is_none())

    var unbounded = Queue[Int](none)
    var large = Queue[Int](9223372036854775807)
    try expect_false(not unbounded.enqueue(1) or not large.enqueue(1))

    var priority = PriorityQueue[Int](compare, 1)
    try expect_false(not priority.enqueue(1) or priority.enqueue(2))

    var unlimited = PriorityQueue[Int](compare, none)
    var large_priority = PriorityQueue[Int](compare, 9223372036854775807)
    try expect_false(not unlimited.enqueue(1) or not large_priority.enqueue(1))
