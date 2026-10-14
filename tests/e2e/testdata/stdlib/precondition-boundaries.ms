import panic from "@std/faults.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import from_int from "@std/bigint.ms"
import {parse_int, NumberError} from "@std/numbers.ms"

fn compare(left: Int, right: Int) -> Int: left - right

test "byte updates retain relative bounds and immutable storage":
    let bytes = Bytes(values: [0, 255])
    if bytes.with_value(index: -2, value: 255) != Bytes(values: [255, 255]): return panic(
        "first relative byte"
    )
    if bytes.with_value(index: 1, value: 0) != Bytes(values: [0, 0]): return panic(
        "last byte"
    )
    if bytes != Bytes(values: [0, 255]): return panic("byte mutation")
    if not bytes.at(-3).is_none() or not bytes.at(2).is_none(): return panic(
        "absent byte"
    )
    if bytes.slice(start: 2, end: 2).unwrap() != Bytes(values: []): return panic(
        "empty byte slice"
    )

    let builder = BytesBuilder()
    builder.append(0)
    builder.append(255)
    if builder.freeze() != bytes: return panic("builder byte boundaries")

test "list boundaries retain mutation truncation and empty ranges":
    let list = [1, 2]
    if list.set(index: -2, value: 0) != [0, 2]: return panic("relative list update")
    if list.remove(-1) != [0] or list != [0]: return panic("relative removal")

    list.splice(start: 1, delete_count: 0, replacement: [1, 2])
    list.fill(value: 9, start: 3, end: 3)
    list.copy_within(target: 3, start: 0, end: 3)
    if list != [0, 1, 2]: return panic("end boundaries")

    list.copy_within(target: 2, start: 0, end: 3)
    if list != [0, 1, 0]: return panic("copy truncation")

    list.splice(start: 0, delete_count: 3, replacement: [])
    list.fill(value: 1, start: 0, end: 0)
    list.copy_within(target: 0, start: 0, end: 0)
    list.splice(start: 0, delete_count: 0, replacement: [])
    if list.length() != 0 or not list.at(0).is_none(): return panic("empty list")

test "radix formatting retains inclusive boundaries and parse errors":
    if (35).to_string(radix: 2) != "100011" or (35).to_string(radix: 36) != "z": return panic(
        "int radix"
    )

    let big = from_int(35)
    if big.to_string(radix: 2) != "100011" or big.to_string(radix: 36) != "z": return panic(
        "big radix"
    )

    let invalid: Result[Int, NumberError] = error(NumberError.InvalidInput)
    if parse_int(text: "1", radix: 1) != invalid: return panic("parse failure category")
    if not "invalid".parse_int().is_none(): return panic("optional parsing")

    let precision: Result[String, NumberError] = error(NumberError.InvalidInput)
    if (1.0).to_precision(precision: 0) != precision: return panic(
        "precision failure category"
    )

test "queue capacities retain omission none minimum maximum and full results":
    let queue = Queue[Int](capacity: 1)
    if not queue.enqueue(1) or queue.enqueue(2): return panic("bounded queue")
    if queue.dequeue() != some(1) or not queue.dequeue().is_none(): return panic(
        "queue absence"
    )

    let unbounded = Queue[Int](capacity: none)
    let large = Queue[Int](capacity: 9223372036854775807)
    if not unbounded.enqueue(1) or not large.enqueue(1): return panic(
        "queue capacity boundaries"
    )

    let priority = PriorityQueue[Int](compare: compare, capacity: 1)
    if not priority.enqueue(1) or priority.enqueue(2): return panic("bounded priority")

    let unlimited = PriorityQueue[Int](compare: compare, capacity: none)
    let large_priority = PriorityQueue[Int](
        compare: compare,
        capacity: 9223372036854775807
    )
    if not unlimited.enqueue(1) or not large_priority.enqueue(1): return panic(
        "priority capacity boundaries"
    )
