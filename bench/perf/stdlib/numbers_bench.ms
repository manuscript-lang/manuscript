import keep, measure from "@std/bench.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import from_int from "@std/math.ms"
import compress, decompress from "@std/archive.ms"
import parse_timestamp from "@std/time.ms"
import PriorityQueue, Queue from "@std/queue.ms"

fn unpacked_length(data: Bytes) Int:
    if let b = decompress(data, "gzip"):
        return b.length()

    return 0

bench "bigint.factorial_1000":
    fn work() Result[Unit, Error]:
        var acc = from_int(1)
        for i in 1..1001:
            acc = acc.multiply(from_int(i))
        return keep(acc.to_string_radix(10).length())

    try measure(1000, work)

bench "bigint.multiply_100_digits":
    fn work() Result[Unit, Error]:
        let base = from_int(7).pow(118).get(from_int(0))
        var acc = from_int(0)
        for i in 0..20000:
            acc = base * base
        return keep(acc.to_string_radix(10).length())

    try measure(20000, work)

bench "decimal.add_round":
    let rate: Decimal = 1.12345d

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..20000:
            if let d = (i.to_decimal() + rate).round(2):
                n += d.truncate_to_int().get(0)
        return keep(n)

    try measure(20000, work)

bench "compress.gzip":
    let blob = (
        "the quick brown fox jumps over the lazy dog "
        .repeat(20000)
        .get("")
        .to_bytes()
    )
    let size = blob.length()

    fn work() Result[Unit, Error]:
        if let b = compress(blob, "gzip", 6):
            return keep(b.length())

        return keep(0)

    try measure(size, work)

bench "compress.roundtrip":
    let blob = (
        "the quick brown fox jumps over the lazy dog "
        .repeat(20000)
        .get("")
        .to_bytes()
    )
    let size = blob.length()

    fn work() Result[Unit, Error]:
        if let b = compress(blob, "gzip", 6):
            return keep(unpacked_length(b))

        return keep(0)

    try measure(size, work)

bench "time.parse_timestamp":
    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..20000:
            if let t = parse_timestamp("2026-03-01T12:30:45.123Z"):
                n += t.unix_seconds() % 7
        return keep(n)

    try measure(20000, work)

bench "queue.enqueue_dequeue":
    fn work() Result[Unit, Error]:
        var q = Queue[Int]()
        for i in 0..100000:
            q.enqueue(i)

        var n = 0
        while not q.is_empty():
            n += q.dequeue().get(0)
        return keep(n)

    try measure(200000, work)

bench "priority_queue.enqueue_dequeue":
    fn work() Result[Unit, Error]:
        var q = PriorityQueue[Int]()
        for i in 0..50000:
            q.enqueue((i * 7919) % 10007)

        var n = 0
        while not q.is_empty():
            n += q.dequeue().get(0)
        return keep(n)

    try measure(100000, work)
