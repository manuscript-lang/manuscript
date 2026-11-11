import (
	Bytes from "@std/bytes.ms",
	ReadStream, Source from "@std/io/io.ms",
	fold, from_bytes, from_list, lines, map from "@std/io/streams.ms",
	keep, measure from "@std/test/bench.ms",
)

type MemorySource:
	data: Bytes
	offset: Int

impl Source[Bytes] for MemorySource:
	var fn next() Bytes?!:
		if self.offset == self.data.length(): return ok(none)

		var end = self.offset + 65536
		if end > self.data.length():
			end = self.data.length()

		chunk := self.data.slice(self.offset, end).get().clone()
		self.offset = end
		return ok(chunk)

	var fn close() Unit!:
		self.offset = self.data.length()

fn source_text() String:
	var parts: List[String] = []
	for i in 0..100000:
		parts.append("line number {i} with some padding text\n")
	return parts.join("")

bench "io.lines":
	bytes := source_text().to_bytes()

	fn work() Result[Unit, Error]:
		var reader = lines(ReadStream[Bytes](MemorySource(bytes.clone(), 0)))
		var count = 0

		while true:
			next := reader.next()
			if next.is_error(): return keep(-1)
			if next.get().is_none(): break

			count += 1

		return keep(count)

	measure(10, work)?

fn counted(n: Int) List[Int]:
	var xs: List[Int] = []
	for i in 0..n:
		xs.append(i)
	return xs

fn plus(x: Int) Int:
	return x + 1

bench "io.stages.map3_fold":
	xs := counted(200000)

	fn work() Result[Unit, Error]:
		stream := map(map(map(from_list(xs.clone()), plus), plus), plus)
		total := fold(stream, 0, fn(a: Int, b: Int) Int: return a + b)?
		return keep(total)

	measure(10, work)?

bench "io.lines long fragmented":
	text := "x".repeat(262144)?
	data := "{text}\n".to_bytes()

	fn work() Unit!:
		var input = lines(from_bytes(data.clone(), 64))
		result := input.next()?
		input.close()?
		return keep(result.get("").byte_length())

	measure(1, work)?
