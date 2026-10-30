import bench from "./harness.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import from_int from "@std/math.ms"
import compress, decompress from "@std/archive.ms"
import parse_timestamp from "@std/time.ms"
import PriorityQueue, Queue from "@std/queue.ms"

export fn bench_numbers() Unit:
    let rate: Decimal = 1.12345d

    bench(
        "bigint.factorial_1000",
        1000,
        fn() Int:
            var acc = from_int(1)
            for i in 1..1001:
                acc = acc.multiply(from_int(i))
            return acc.to_string_radix(10).length()
    )

    bench(
        "decimal.add_round",
        20000,
        fn() Int:
            var n = 0
            for i in 0..20000:
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
        fn() Int:
            if let b = compress(blob, "gzip", 6):
                return b.length()

            return 0
    )

    bench(
        "compress.roundtrip",
        blob.length(),
        fn() Int:
            if let b = compress(blob, "gzip", 6):
                return unpacked_length(b)

            return 0
    )

    bench(
        "time.parse_timestamp",
        20000,
        fn() Int:
            var n = 0
            for i in 0..20000:
                if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
                    n += t.unix_seconds() % 7
            return n
    )

    bench(
        "queue.enqueue_dequeue",
        200000,
        fn() Int:
            var q = Queue[Int]()
            for i in 0..100000:
                q.enqueue(i)

            var n = 0
            while not q.is_empty():
                n += q.dequeue().get(0)
            return n
    )

    bench(
        "priority_queue.enqueue_dequeue",
        100000,
        fn() Int:
            var q = PriorityQueue[Int]()
            for i in 0..50000:
                q.enqueue((i * 7919) % 10007)

            var n = 0
            while not q.is_empty():
                n += q.dequeue().get(0)
            return n
    )

fn unpacked_length(data: Bytes) Int:
    if let b = decompress(data, "gzip"):
        return b.length()

    return 0
