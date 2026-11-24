import (
	Bytes from "@std/bytes.ms",
	ReadStream, Source from "@std/io/io.ms",
	lines, map from "@std/io/steps.ms",
	fold, from_bytes, from_list from "@std/io/streams.ms",
)

type MemorySource:
	data Bytes
	offset Int

fn var MemorySource.next() Bytes?!:
	if self.offset == self.data.length(): return ok(null)

	var end = self.offset + 65536
	if end > self.data.length():
		end = self.data.length()

	chunk := self.data.slice(self.offset, end).get().clone()
	self.offset = end
	return ok(chunk)

fn move MemorySource.close() Void!:
	self.offset = self.data.length()

fn source_text() String:
	var parts List[String] = []
	for i in 0..100000:
		parts.append(f"line number {i} with some padding text\n")
	return parts.join("")

type BenchData:
	bytes Bytes
	xs List[Int]
	text String
	data Bytes

fn make_fixture() BenchData:
	bytes := source_text().to_bytes()
	xs := counted(200000)
	text := "x".repeat(262144)
	data := f"{text}\n".to_bytes()
	return BenchData(bytes: bytes, xs: xs, text: text, data: data)

bench "io.lines" per 10:
	var reader = lines(ReadStream[Bytes](MemorySource(fixture.bytes.clone(), 0)))
	var count = 0

	while true:
		if reader.next().get() == null: break

		count += 1

	count

fn counted(n Int) List[Int]:
	var xs List[Int] = []
	for i in 0..n:
		xs.append(i)
	return xs

fn plus(x Int) Int:
	return x + 1

bench "io.stages.map3_fold" per 10:
	stream := map(map(map(from_list(fixture.xs.clone()), plus), plus), plus)
	total := fold(stream, 0, fn(a Int, b Int) Int: return a + b)?
	total

bench "io.lines long fragmented":
	var input = lines(from_bytes(fixture.data.clone(), 64))
	result := input.next()?
	input.close()?
	(result or "").length()
