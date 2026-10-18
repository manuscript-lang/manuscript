import panic from "@std/faults.ms"
import {Bytes, BytesBuilder} from "@std/bytes.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import from_int from "@std/bigint.ms"
import {parse_int, NumberError} from "@std/numbers.ms"

fn compare(left: Int, right: Int) Int: left - right

test "byte updates retain relative bounds and immutable storage":
    let bytes = Bytes([0, 255])
    if bytes.with_value(-2, 255) != Bytes([255, 255]): return panic(
        "first relative byte"
    )
    if bytes.with_value(1, 0) != Bytes([0, 0]): return panic("last byte")
    if bytes != Bytes([0, 255]): return panic("byte mutation")
    if not bytes.at(-3).is_none() or not bytes.at(2).is_none(): return panic(
        "absent byte"
    )
    if bytes.slice(2, 2).get() != Bytes([]): return panic("empty byte slice")

    let builder = BytesBuilder()
    builder.append(0)
    builder.append(255)
    if builder.freeze() != bytes: return panic("builder byte boundaries")

test "list boundaries retain mutation truncation and empty ranges":
    let list = [1, 2]
    if list.set(-2, 0) != [0, 2]: return panic("relative list update")
    if list.remove(-1) != [0] or list != [0]: return panic("relative removal")

    list.splice(1, 0, [1, 2])
    list.fill(9, 3, 3)
    list.copy_within(3, 0, 3)
    if list != [0, 1, 2]: return panic("end boundaries")

    list.copy_within(2, 0, 3)
    if list != [0, 1, 0]: return panic("copy truncation")

    list.splice(0, 3, [])
    list.fill(1, 0, 0)
    list.copy_within(0, 0, 0)
    list.splice(0, 0, [])
    if list.length() != 0 or not list.at(0).is_none(): return panic("empty list")

test "radix formatting retains inclusive boundaries and parse errors":
    if (35).to_string_radix(2) != "100011" or (35).to_string_radix(36) != "z": return panic(
        "int radix"
    )

    let big = from_int(35)
    if big.to_string_radix(2) != "100011" or big.to_string_radix(36) != "z": return panic(
        "big radix"
    )

    let invalid: Result[Int, NumberError] = error(NumberError.InvalidInput)
    if parse_int("1", 1) != invalid: return panic("parse failure category")
    if not "invalid".parse_int().is_none(): return panic("optional parsing")

    let precision: Result[String, NumberError] = error(NumberError.InvalidInput)
    if (1.0).to_precision(0) != precision: return panic("precision failure category")

test "queue capacities retain omission none minimum maximum and full results":
    let queue = Queue[Int](1)
    if not queue.enqueue(1) or queue.enqueue(2): return panic("bounded queue")
    if queue.dequeue() != some(1) or not queue.dequeue().is_none(): return panic(
        "queue absence"
    )

    let unbounded = Queue[Int](none)
    let large = Queue[Int](9223372036854775807)
    if not unbounded.enqueue(1) or not large.enqueue(1): return panic(
        "queue capacity boundaries"
    )

    let priority = PriorityQueue[Int](compare, 1)
    if not priority.enqueue(1) or priority.enqueue(2): return panic("bounded priority")

    let unlimited = PriorityQueue[Int](compare, none)
    let large_priority = PriorityQueue[Int](compare, 9223372036854775807)
    if not unlimited.enqueue(1) or not large_priority.enqueue(1): return panic(
        "priority capacity boundaries"
    )
