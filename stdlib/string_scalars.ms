import Bytes from "@std/bytes.ms"

// Reads a string's scalars one at a time, decoding its UTF-8 bytes where it stands.
export type ScalarSource:
	// The UTF-8 text, encoded once by `String.stream`.
	bytes: Bytes
	// Byte offset of the next scalar, always on a scalar boundary.
	at: Int

// The next scalar as a one-scalar String, or none at the end.
fn var ScalarSource.next() String?!:
	if self.at >= self.bytes.length(): return ok(none)

	stop := self.at + scalar_width(self.bytes.get(self.at).to_int())
	scalar := self.bytes.decode_utf8_range(self.at, stop)
	self.at = stop
	return ok(scalar)

// Releases nothing; the bytes are owned by the source.
fn var ScalarSource.close() Unit!:
	return ok(unit)

// Bytes in the scalar a lead byte starts.
fn scalar_width(lead: Int) Int:
	if lead < 128: return 1
	if lead < 224: return 2
	if lead < 240: return 3

	return 4
