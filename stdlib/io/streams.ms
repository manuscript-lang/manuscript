import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	ReadStream, WriteStream from "@std/io/io.ms",
)

// Builds streams from values and drains them into values: `from_list`, `from_bytes`,
// `fold`, `collect`, `read_all` and `copy`. Steps between them are in
// `@std/io/steps.ms`; handing a stream to another thread is `@std/io/forward.ms`.

// Internal: the items of a list, in order. The list belongs to the stream and is held
// last item first, so `pop` moves the next one out.
type ListSource[T]:
	items: List[T]

fn var ListSource[T].next() move T?!:
	return ok(self.items.pop())

fn move ListSource[T].close() Void!:
	return ok()

// Returns a stream that yields copies of the items of `items` in order and then ends.
// The items must be Clonable: a resource has one owner and cannot be copied, so move
// it into a custom `Source` instead.
export fn from_list[T: Clonable](items: List[T]) ReadStream[T]:
	var reversed = items.clone()
	reversed.reverse()
	return ReadStream[T](ListSource[T](reversed))

// Internal: chunks of at most `chunk` bytes of `data`.
type BytesSource:
	data: Bytes
	at: Int
	chunk: Int

fn var BytesSource.next() move Bytes?!:
	if self.chunk < 1:
		return error(Error("I/O: chunk size must be positive", kind: "EINVAL"))
	if self.at >= self.data.length(): return ok(null)

	stop := (self.at + self.chunk).min(self.data.length())
	piece := self.data.slice(self.at, stop)?
	self.at = stop
	return ok(piece)

fn move BytesSource.close() Void!:
	return ok()

// Returns a stream that yields `data` in chunks of at most `chunk_bytes` bytes and
// then ends. A `chunk_bytes` below 1 makes the first read fail with `EINVAL`.
export fn from_bytes(move data: Bytes, chunk_bytes: Int = 65536) ReadStream[Bytes]:
	return ReadStream[Bytes](BytesSource(data, 0, chunk_bytes))

// Combines the items of `input` in order into one value: `f` takes the value so far
// and the next item, starting from `start`. A failed read returns its error.
export fn fold[T, S](input: ReadStream[T], start: S, f: fn(S, T) S) S!:
	var source = input
	var total = start
	for item in source:
		total = f(total, item)
	return ok(total)

// Returns every item of `input`, in order. More than `max_items` items returns
// `EOVERFLOW`.
export fn collect[T](input: ReadStream[T], max_items: Int?) List[T]!:
	var source = input
	var items: List[T] = []

	for item in source:
		items.append(item)

		limit := max_items
		if limit != null:
			if items.length() > limit:
				return error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))

	return ok(items)

// Returns all bytes of `input`. More than `max_bytes` bytes returns `EOVERFLOW`.
export fn read_all(input: ReadStream[Bytes], max_bytes: Int?) Bytes!:
	var source = input
	var all = BytesBuilder()
	var first: Bytes? = none
	var total = 0

	for chunk in source:
		total += chunk.length()

		limit := max_bytes
		if limit != null:
			if total > limit:
				return error(Error("I/O: limit exceeded", kind: "EOVERFLOW"))

		// A stream that ends after one chunk (a file read in one piece) hands that
		// chunk back uncopied.
		if held := first:
			all.append_bytes(held)
			first = none

		if total == chunk.length():
			first = chunk
		else:
			all.append_bytes(chunk)

	if one := first: return ok(one)

	return ok(all.build())

// Moves every item of `input` to `output`, pulling the next item only after `write`
// accepts the last, then flushes `output`. Returns the number of items moved.
export fn copy[T](input: ReadStream[T], output: WriteStream[T]) Int!:
	var source = input
	var sink = output
	var count = 0

	for item in source:
		sink.write(item)?
		count += 1

	sink.flush()?
	return ok(count)
