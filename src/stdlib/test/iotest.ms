// ms: allow_effect std.clock.read

import (
	Bytes from "@std/bytes.ms",
	ReadStream, WriteStream from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
	fail from "@std/test/test.ms",
)

/*
Misbehaving streams for testing code that reads and writes. Each wrapper takes its input first, like the
helpers in `@std/io/streams.ms`, so `from_bytes(data) | one_byte` is a reader that trickles.
`check_reader` checks that a `ReadStream[Bytes]` you wrote behaves like a well-formed stream.
*/
type OneByte {
	input ReadStream[Bytes]
	held Bytes?
}

fn var OneByte.next() move Bytes?! {
	var data = "".to_bytes()
	held := self.held.clone()

	if held != null {
		data = held
	} else {
		fresh := self.input.next()?
		next := fresh

		if next != null {
			data = next.clone()
		} else {
			return ok(null)
		}
	}

	if data.length() <= 1 {
		self.held = null
		return ok(data)
	}

	self.held = data.slice(1, data.length())?.clone()
	return ok(data.slice(0, 1)?.clone())
}

fn move OneByte.close() Void! {
	return self.input.close()
}

// Returns `input` limited to one byte per read. This exposes code that assumes a read
// fills its buffer.
export fn one_byte(move input ReadStream[Bytes]) ReadStream[Bytes] {
	return ReadStream[Bytes](OneByte(input, null))
}

type FailAfter {
	input ReadStream[Bytes]
	remaining Int
	cause Error
}

fn var FailAfter.next() move Bytes?! {
	if self.remaining <= 0 { return error(self.cause.clone()) }

	chunk := self.input.next()?
	data := chunk

	if data != null {
		if data.length() > self.remaining {
			head := data.slice(0, self.remaining)?
			self.remaining = 0
			return ok(head)
		}

		self.remaining -= data.length()
	}

	return ok(chunk)
}

fn move FailAfter.close() Void! {
	return self.input.close()
}

// Returns a stream that delivers `after` bytes of `input` and then fails every read
// with `cause`, even if `input` has ended. Use it to check that a parser reports a
// truncated or broken source instead of treating it as a clean end of input.
export fn fail_after(
	move input ReadStream[Bytes],
	after Int,
	move cause Error,
) ReadStream[Bytes] {
	return ReadStream[Bytes](FailAfter(input, after, cause))
}

type FailingSink {
	output WriteStream[Bytes]
	remaining Int
	cause Error
}

fn var FailingSink.write(move value Bytes) Void! {
	size := value.length()

	if size <= self.remaining {
		self.remaining -= size
		return self.output.write(value)
	}

	// Like a full disk: the prefix that fits is written, then the write fails.
	prefix := self.remaining
	self.remaining = 0
	if prefix > 0 {
		self.output.write(value.slice(0, prefix)?)?
	}
	return error(self.cause.clone())
}

fn var FailingSink.flush() Void! {
	return self.output.flush()
}

fn move FailingSink.close() Void! {
	return self.output.close()
}

// Returns a writer that passes `after` bytes through to `output`, writes the part of
// the write that fits under the limit, and then fails that write and every later one
// with `cause`. Use it to check error handling on a full disk or closed pipe.
export fn fail_writer_after(
	move output WriteStream[Bytes],
	after Int,
	move cause Error,
) WriteStream[Bytes] {
	return WriteStream[Bytes](FailingSink(output, after, cause))
}

// Checks that `make` builds a well-behaved `ReadStream[Bytes]` over exactly
// `expected`: whole reads, one-byte reads, and an end of input that stays ended.
// `make` is called once per check, so each check starts from the beginning. Fails the
// test if any check does not hold.
export fn check_reader(make fn() ReadStream[Bytes], expected Bytes) Void! {
	all := read_all(make())
	if all.is_error() { return fail("check_reader: reading everything failed") }
	if all.get() != expected {
		return fail(
			f"check_reader: read {all.get().length()} bytes, expected {expected.length()}; content differs"
		)
	}

	slow := read_all(one_byte(make()))
	if slow.is_error() { return fail("check_reader: one-byte reads failed") }
	if slow.get() != expected {
		return fail("check_reader: one-byte reads returned different content")
	}

	var again = make()
	var total = 0

	while true {
		chunk := again.next()
		if chunk.is_error() { return fail("check_reader: a read failed") }

		piece := chunk.get()

		if piece != null {
			total += piece.length()
		} else {
			break
		}
	}

	after_end := again.next()
	if after_end.is_error() or (after_end.get() != null) {
		return fail("check_reader: a read after end of input must return none again")
	}
	if total != expected.length() {
		return fail(
			f"check_reader: chunked reads returned {total} bytes, expected {expected.length()}"
		)
	}
}
