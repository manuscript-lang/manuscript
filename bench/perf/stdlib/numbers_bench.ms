import (
	Bytes from "@std/bytes.ms",
	PriorityQueue, Queue from "@std/collections/queue.ms",
	CompressionFormat, compress, decompress from "@std/io/archive.ms",
	Decimal from "@std/math/decimal.ms",
	big_int_of_int from "@std/math/math.ms",
	parse_timestamp from "@std/time.ms",
)

fn unpacked_length(data Bytes) Int {
	if b := decompress(data, CompressionFormat.Gzip) { return b.length() }
	return 0
}

type BenchData {
	rate Decimal
	text String
	blob Bytes
}

fn make_fixture() BenchData {
	rate Decimal := 1.12345d
	text := "2026-03-01T12:30:45." + "0".repeat(65536) + "Z"
	blob := "the quick brown fox jumps over the lazy dog ".repeat(20000).to_bytes()
	return BenchData(rate: rate, text: text, blob: blob)
}

bench "bigint.factorial_1000" per 1000 {
	var acc = big_int_of_int(1)
	for i in 1..1001 {
		acc = acc.multiply(big_int_of_int(i))
	}
	acc.to_string().length()
}

bench "bigint.multiply_100_digits" per 20000 {
	base := big_int_of_int(7).pow(118).get_or(big_int_of_int(0))
	var acc = big_int_of_int(0)
	for i in 0..20000 {
		acc = base * base
	}
	acc.to_string().length()
}

bench "decimal.add_round" per 20000 {
	var n = 0
	for i in 0..20000 {
		if d := (i.to_decimal() + fixture.rate).round(2) {
			n += d.truncate_to_int() or 0
		}
	}
	n
}

// The blob is 880000 bytes, which both benches report their time per byte of.
bench "compress.gzip" per 880000 {
	compress(fixture.blob, CompressionFormat.Gzip).get().length()
}

bench "compress.roundtrip" per 880000 {
	unpacked_length(compress(fixture.blob, CompressionFormat.Gzip).get())
}

bench "time.parse_timestamp" per 20000 {
	var n = 0
	for i in 0..20000 {
		if t := parse_timestamp("2026-03-01T12:30:45.123Z") {
			n += t.unix_seconds() % 7
		}
	}
	n
}

bench "time.parse_timestamp_maximum_width" per 20000 {
	var n = 0

	for i in 0..20000 {
		t := parse_timestamp("2026-03-01T12:30:45.123456789+05:30")?
		n += t.nanoseconds()
	}

	n
}

bench "time.parse_timestamp_oversized_fraction" per 1000 {
	var n = 0

	for i in 0..1000 {
		result := parse_timestamp(fixture.text)
		if result.is_ok() or result.err().kind != "EBADMSG" {
			return error(Error("expected timestamp InvalidData"))
		}

		n += 1
	}

	n
}

bench "queue.enqueue_dequeue" per 200000 {
	var q = Queue[Int]()
	for i in 0..100000 {
		q.enqueue(i)
	}

	var n = 0
	while not q.is_empty() {
		n += q.dequeue() or 0
	}
	n
}

bench "priority_queue.enqueue_dequeue" per 100000 {
	var q = PriorityQueue[Int]()
	for i in 0..50000 {
		q.enqueue((i * 7919) % 10007)
	}

	var n = 0
	while not q.is_empty() {
		n += q.dequeue() or 0
	}
	n
}
