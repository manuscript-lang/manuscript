import {expect_equal, expect_false, expect_true} from "@std/testing.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import from_int from "@std/bigint.ms"
import {parse_int, NumberError} from "@std/numbers.ms"

fn compare(left: Int, right: Int) -> Int: left - right

test "byte updates retain relative bounds and immutable storage":
    let bytes = Bytes(values: [0, 255])
    bytes.with_value(index: -2, value: 255) | try expect_equal(
        expected: Bytes(values: [255, 255])
    )
    bytes.with_value(index: 1, value: 0) | try expect_equal(
        expected: Bytes(values: [0, 0])
    )
    bytes | try expect_equal(expected: Bytes(values: [0, 255]))
    (not bytes.at(-3).is_none() or not bytes.at(2).is_none()) | try expect_false
    (
        bytes.slice(start: 2, end: 2).unwrap() | try expect_equal(
            expected: Bytes(values: [])
        )
    )
    let builder = BytesBuilder()
    builder.append(0)
    builder.append(255)
    builder.freeze() | try expect_equal(expected: bytes)

test "list boundaries retain mutation truncation and empty ranges":
    let list = [1, 2]
    list.set(index: -2, value: 0) | try expect_equal(expected: [0, 2])
    (list.remove(-1) != [0] or list != [0]) | try expect_false
    list.splice(start: 1, delete_count: 0, replacement: [1, 2])
    list.fill(value: 9, start: 3, end: 3)
    list.copy_within(target: 3, start: 0, end: 3)
    list | try expect_equal(expected: [0, 1, 2])
    list.copy_within(target: 2, start: 0, end: 3)
    list | try expect_equal(expected: [0, 1, 0])
    list.splice(start: 0, delete_count: 3, replacement: [])
    list.fill(value: 1, start: 0, end: 0)
    list.copy_within(target: 0, start: 0, end: 0)
    list.splice(start: 0, delete_count: 0, replacement: [])
    (list.length() != 0 or not list.at(0).is_none()) | try expect_false

test "radix formatting retains inclusive boundaries and parse errors":
    try expect_false(
        (
            (35).to_string(radix: 2) != "100011"
            or (35).to_string(radix: 36) != "z"
        )
    )
    let big = from_int(35)
    (big.to_string(radix: 2) != "100011" or big.to_string(radix: 36) != "z") | try expect_false
    let invalid: Result[Int, NumberError] = error(NumberError.InvalidInput)
    parse_int(text: "1", radix: 1) | try expect_equal(expected: invalid)
    ("invalid".parse_int().is_none()) | try expect_true
    let precision: Result[String, NumberError] = error(NumberError.InvalidInput)
    (1.0).to_precision(precision: 0) | try expect_equal(expected: precision)

test "queue capacities retain omission none minimum maximum and full results":
    let queue = Queue[Int](capacity: 1)
    (not queue.enqueue(1) or queue.enqueue(2)) | try expect_false
    (queue.dequeue() != some(1) or not queue.dequeue().is_none()) | try expect_false
    let unbounded = Queue[Int](capacity: none)
    let large = Queue[Int](capacity: 9223372036854775807)
    (not unbounded.enqueue(1) or not large.enqueue(1)) | try expect_false
    let priority = PriorityQueue[Int](compare: compare, capacity: 1)
    (not priority.enqueue(1) or priority.enqueue(2)) | try expect_false
    let unlimited = PriorityQueue[Int](compare: compare, capacity: none)
    let large_priority = PriorityQueue[Int](
        compare: compare,
        capacity: 9223372036854775807
    )
    (not unlimited.enqueue(1) or not large_priority.enqueue(1)) | try expect_false
