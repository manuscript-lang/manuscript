import (
    keep, measure from "@std/test/bench.ms",
    Bytes from "@std/bytes.ms",
    Decimal from "@std/math/decimal.ms",
    from_int from "@std/math/math.ms",
    compress, decompress, CompressionFormat from "@std/io/archive.ms",
    parse_timestamp from "@std/time.ms",
    PriorityQueue, Queue from "@std/collections/queue.ms",
)

fn unpacked_length(data: Bytes) Int:
    if b := decompress(data, CompressionFormat.Gzip): return b.length()

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
        base := from_int(7).pow(118).get(from_int(0))
        var acc = from_int(0)
        for i in 0..20000:
            acc = base * base
        return keep(acc.to_string_radix(10).length())

    try measure(20000, work)

bench "decimal.add_round":
    rate: Decimal = 1.12345d

    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..20000:
            if d := (i.to_decimal() + rate).round(2):
                n += d.truncate_to_int().get(0)
        return keep(n)

    try measure(20000, work)

bench "compress.gzip":
    blob := (
        "the quick brown fox jumps over the lazy dog "
        .repeat(20000)
        .get("")
        .to_bytes()
    )
    size := blob.length()

    fn work() Result[Unit, Error]:
        if b := compress(blob, CompressionFormat.Gzip): return keep(b.length())

        return keep(0)

    try measure(size, work)

bench "compress.roundtrip":
    blob := (
        "the quick brown fox jumps over the lazy dog "
        .repeat(20000)
        .get("")
        .to_bytes()
    )
    size := blob.length()

    fn work() Result[Unit, Error]:
        if b := compress(blob, CompressionFormat.Gzip):
            return keep(unpacked_length(b))

        return keep(0)

    try measure(size, work)

bench "time.parse_timestamp":
    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..20000:
            if t := parse_timestamp("2026-03-01T12:30:45.123Z"):
                n += t.unix_seconds() % 7
        return keep(n)

    try measure(20000, work)

bench "time.parse_timestamp_maximum_width":
    fn work() Result[Unit, Error]:
        var n = 0

        for i in 0..20000:
            t := try parse_timestamp("2026-03-01T12:30:45.123456789+05:30")
            n += t.nanoseconds()

        return keep(n)

    try measure(20000, work)

bench "time.parse_timestamp_oversized_fraction":
    text := "2026-03-01T12:30:45." + "0".repeat(65536).get() + "Z"

    fn work() Result[Unit, Error]:
        var n = 0

        for i in 0..1000:
            result := parse_timestamp(text)
            if result.is_ok() or result.err().kind != "EBADMSG":
                return error(Error("expected timestamp InvalidData"))

            n += 1

        return keep(n)

    try measure(1000, work)

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
