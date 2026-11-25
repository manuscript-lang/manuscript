// ms: allow_effect std.clock.read

import (
	Bytes, join from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
)

// Steps for streams. Each takes its input first, so a pipeline can be written with
// the `|` operator. A step pulls from its input only inside its own `next`, so a slow
// consumer slows every step and the source. Closing a step closes its input.

// Internal: lines of text, without their `\n` or `\r\n`, cut only at line ends. An
// unterminated last line comes at the end. `data` is the current chunk, `start` is
// the first unread byte in it, and `pending` holds earlier unfinished fragments.
type Lines {
	input ReadStream[Bytes]
	data Bytes
	start Int
	ended Bool
	pending List[Bytes]
	pending_size Int
	pending_cr Bool
	max_bytes Int?
}

// Internal: fails with `EOVERFLOW` when a line of `size` bytes is longer than the
// limit.
fn Lines.check(size Int) Void! {
	limit := self.max_bytes
	if limit != null {
		if size > limit { return error(Error("I/O: limit exceeded", kind: "EOVERFLOW")) }
	}
}

// Internal: decodes the held bytes in `[start, stop)` as one line. Bytes that are not
// UTF-8 fail with `EBADMSG` rather than becoming an empty line. The range is decoded
// in place, without first copying the line into a `Bytes`.
fn Lines.decode(start, stop Int) String! {
	text := self.data.decode_utf8_range(start, stop)
	if text != null { return ok(text) }

	return error(Error("I/O: line is not valid UTF-8", kind: "EBADMSG"))
}

// Internal: joins only a completed line. Incomplete chunks are copied once, not as a
// growing prefix.
fn var Lines.take(stop Int, terminated Bool) String! {
	if self.pending_size == 0 {
		var end = stop
		if terminated and end > self.start and self.data.get_or(end - 1, 0) == 13 {
			end -= 1
		}
		self.check(end - self.start)?

		from := self.start
		self.start = if terminated { stop + 1 } else { stop }
		return self.decode(from, end)
	}

	size := self.pending_size + stop - self.start
	cr := if stop > self.start {
		self.data.get_or(stop - 1, 0) == 13
	} else {
		self.pending_cr
	}
	trimmed := if terminated and cr { size - 1 } else { size }
	self.check(trimmed)?
	self.pending.append(self.data.slice(self.start, stop)?.clone())

	all := join(self.pending)
	self.pending = []
	self.pending_size = 0
	self.pending_cr = false
	self.start = if terminated { stop + 1 } else { stop }

	text := all.decode_utf8_range(0, trimmed)
	if text != null { return ok(text) }

	return error(Error("I/O: line is not valid UTF-8", kind: "EBADMSG"))
}

fn var Lines.next() String?! {
	while true {
		end := self.data.index_of_byte(10, self.start)

		if end != null {
			if self.pending_size > 0 { return ok(self.take(end, true)?) }

			var stop = end
			if stop > self.start and self.data.get_or(stop - 1, 0) == 13 {
				stop -= 1
			}
			self.check(stop - self.start)?

			from := self.start
			self.start = end + 1
			return ok(self.decode(from, stop)?)
		}

		if self.ended {
			if self.pending_size > 0 or self.start < self.data.length() {
				return ok(self.take(self.data.length(), false)?)
			}
			return ok(null)
		}

		// A trailing CR may belong to a split CRLF, so defer counting it until the
		// next chunk or EOF.
		rest := self.data.length() - self.start
		cr := if rest > 0 {
			self.data.get_or(self.data.length() - 1, 0) == 13
		} else {
			self.pending_cr
		}
		self.check(self.pending_size + rest - if cr { 1 } else { 0 })?

		chunk := self.input.next()?
		more := chunk

		if more != null {
			if rest > 0 {
				self.pending.append(
					self.data.slice(
						self.start,
						self.data.length(),
					)?.clone()
				)
				self.pending_size += rest
				self.pending_cr = cr
			}

			self.data = more
			self.start = 0
		} else {
			self.ended = true
		}
	}
}

fn move Lines.close() Void! {
	return self.input.close()
}

// Reads lines of text from a byte stream such as `stdin()`. It splits `input` at
// `\n` and removes a trailing `\r`. A line longer than `max_bytes` returns
// `EOVERFLOW`, and a line that is not valid UTF-8 returns `EBADMSG`.
export fn lines(
	move input ReadStream[Bytes],
	max_bytes Int? = null,
) ReadStream[String] {
	return ReadStream[String](
		Lines(input, "".to_bytes(), 0, false, [], 0, false, max_bytes)
	)
}

type Mapped[T, U] {
	input ReadStream[T]
	f fn(T) U
}

fn var Mapped[T, U].next() U?! {
	item := self.input.next()?
	value := item
	if value != null { return ok(self.f(value)) }

	return ok(null)
}

fn move Mapped[T, U].close() Void! {
	return self.input.close()
}

// Returns a stream of `f` applied to each item of `input`. Closing it closes
// `input`.
export fn map[T, U](move input ReadStream[T], f fn(T) U) ReadStream[U] {
	return ReadStream[U](Mapped[T, U](input, f))
}

type Filtered[T] {
	input ReadStream[T]
	keep fn(T) Bool
}

fn var Filtered[T].next() T?! {
	while true {
		item := self.input.next()?
		value := item

		if value != null {
			if self.keep(value) { return ok(value) }
		} else {
			return ok(null)
		}
	}
}

fn move Filtered[T].close() Void! {
	return self.input.close()
}

// Returns a stream of the items of `input` for which `keep` is true, in order.
// Closing it closes `input`.
export fn filter[T](move input ReadStream[T], keep fn(T) Bool) ReadStream[T] {
	return ReadStream[T](Filtered[T](input, keep))
}

// Internal: the first `left` items of another stream; it never pulls past them.
type Taker[T] {
	input ReadStream[T]
	left Int
}

fn var Taker[T].next() T?! {
	if self.left <= 0 { return ok(null) }

	item := self.input.next()?
	self.left -= 1
	return ok(item)
}

fn move Taker[T].close() Void! {
	return self.input.close()
}

// Returns a stream of at most the first `count` items of `input`, then the end. Later
// items are never read, so `take` can end an endless stream. A failed read does not
// count as an item. A `count` of 0 or less gives an empty stream. Closing it closes
// `input`.
export fn take[T](move input ReadStream[T], count Int) ReadStream[T] {
	return ReadStream[T](Taker[T](input, count))
}
