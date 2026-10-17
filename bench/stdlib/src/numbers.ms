import {bench} from "./harness.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import {from_int} from "@std/bigint.ms"
import {compress, decompress} from "@std/compress.ms"
import {parse_timestamp} from "@std/time.ms"
import {PriorityQueue, Queue} from "@std/queues.ms"

export fn bench_numbers() -> Unit:
    let rate: Decimal = 1.12345d
    bench(
        "bigint.factorial_1000",
        1000,
        fn() -> Int:
            var acc = from_int(1)
            var i = 1

            while i <= 1000:
                acc = acc.multiply(from_int(i))
                i = i + 1

            return acc.to_string(radix: 10).length()
    )
    bench(
        "decimal.add_round",
        20000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 20000:
                if let d = (i.to_decimal() + rate).round(places: 2): n = (
                    n
                    + d.truncate_to_int().unwrap_or(0)
                )
                i = i + 1

            return n
    )
    let blob = (
        "the quick brown fox jumps over the lazy dog "
        .repeat(20000)
        .unwrap_or("")
        .to_bytes()
    )
    bench(
        "compress.gzip",
        blob.length(),
        fn() -> Int:
            if let b = compress(data: blob, format: "gzip", level: 6): return b.length()

            return 0
    )
    bench(
        "compress.roundtrip",
        blob.length(),
        fn() -> Int:
            if let b = compress(
                data: blob,
                format: "gzip",
                level: 6
            ): return unpacked_length(b)

            return 0
    )
    bench(
        "time.parse_timestamp",
        20000,
        fn() -> Int:
            var n = 0
            var i = 0

            while i < 20000:
                if let t = parse_timestamp(text: "2026-03-01T12:30:45.123Z"): n = (
                    n
                    + t.unix_seconds() % 7
                )
                i = i + 1

            return n
    )
    bench(
        "queue.enqueue_dequeue",
        200000,
        fn() -> Int:
            let q = Queue[Int]()
            var i = 0

            while i < 100000:
                q.enqueue(i)
                i = i + 1

            var n = 0
            while not q.is_empty():
                n = n + q.dequeue().unwrap_or(0)
            return n
    )
    bench(
        "priority_queue.enqueue_dequeue",
        100000,
        fn() -> Int:
            let q = PriorityQueue[Int](
                compare: fn(left: Int, right: Int) -> Int: (
                    left
                    - right
                )
            )
            var i = 0

            while i < 50000:
                q.enqueue((i * 7919) % 10007)
                i = i + 1

            var n = 0
            while not q.is_empty():
                n = n + q.dequeue().unwrap_or(0)
            return n
    )

fn unpacked_length(data: Bytes) -> Int:
    if let b = decompress(data: data, format: "gzip"): return b.length()

    return 0
