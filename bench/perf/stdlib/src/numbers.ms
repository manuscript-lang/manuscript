from "@std/collections.ms" import range
from "./harness.ms" import bench
from "@std/bytes.ms" import Bytes
from "@std/decimal.ms" import Decimal
from "@std/math.ms" import from_int
from "@std/archive.ms" import compress, decompress
from "@std/time.ms" import parse_timestamp
from "@std/queue.ms" import PriorityQueue, Queue

export def bench_numbers() -> Unit:
    let rate: Decimal = 1.12345d

    bench(
        "bigint.factorial_1000",
        1000,
        lambda () -> Int:
            var acc = from_int(1)
            for i in range(1, 1001):
                acc = acc.multiply(from_int(i))
            return acc.to_string_radix(10).length()
    )

    bench(
        "bigint.multiply_100_digits",
        20000,
        lambda () -> Int:
            let base = from_int(7).pow(118).get(from_int(0))
            var acc = base
            for i in range(0, 20000):
                acc = base * base
            return acc.to_string_radix(10).length()
    )

    bench(
        "decimal.add_round",
        20000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 20000):
                if let d = (i.to_decimal() + rate).round(2):
                    n += d.truncate_to_int().get(0)
            return n
    )

    let blob = (
        "the quick brown fox jumps over the lazy dog "
        .repeat(20000)
        .get("")
        .to_bytes()
    )

    bench(
        "compress.gzip",
        blob.length(),
        lambda () -> Int:
            if let b = compress(blob, "gzip", 6):
                return b.length()

            return 0
    )

    bench(
        "compress.roundtrip",
        blob.length(),
        lambda () -> Int:
            if let b = compress(blob, "gzip", 6):
                return unpacked_length(b)

            return 0
    )

    bench(
        "time.parse_timestamp",
        20000,
        lambda () -> Int:
            var n = 0
            for i in range(0, 20000):
                if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
                    n += t.unix_seconds() % 7
            return n
    )

    bench(
        "queue.enqueue_dequeue",
        200000,
        lambda () -> Int:
            var q = Queue[Int]()
            for i in range(0, 100000):
                q.enqueue(i)

            var n = 0
            while not q.is_empty():
                n += q.dequeue().get(0)
            return n
    )

    bench(
        "priority_queue.enqueue_dequeue",
        100000,
        lambda () -> Int:
            var q = PriorityQueue[Int]()
            for i in range(0, 50000):
                q.enqueue((i * 7919) % 10007)

            var n = 0
            while not q.is_empty():
                n += q.dequeue().get(0)
            return n
    )

def unpacked_length(data: Bytes) -> Int:
    if let b = decompress(data, "gzip"):
        return b.length()

    return 0
