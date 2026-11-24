// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, join from "@std/bytes.ms",
	panic from "@std/core.ms",
	base64_decode, base64_encode, hex_encode from "@std/data/encoding.ms",
	base64_decoded,
	base64_encoded,
	hex_decoded,
	hex_encoded from "@std/data/encoding_stream.ms",
	ReadStream, Source from "@std/io/io.ms",
	expect_equal, fail from "@std/test/test.ms",
)

// Hands out the chunks in order, then ends.
type Chunks:
	data Bytes
	size Int
	at Int

fn var Chunks.next() Bytes?!:
	if self.at >= self.data.length(): return ok(null)

	var end = self.at + self.size
	if end > self.data.length(): end = self.data.length()

	piece := self.data.slice(self.at, end)?
	self.at = end
	return ok(piece)

fn move Chunks.close() Void!:
	return ok()

fn chunked(move data Bytes, size Int) ReadStream[Bytes]:
	return ReadStream[Bytes](Chunks(data, size, 0))

type Texts:
	parts List[String]
	at Int

fn var Texts.next() String?!:
	if self.at >= self.parts.length(): return ok(null)

	part := self.parts[self.at].clone()
	self.at += 1
	return ok(part)

fn move Texts.close() Void!:
	return ok()

// Splits text into pieces of `size` characters.
fn pieces(text String, size Int) List[String]:
	var out List[String] = []
	var at = 0

	while at < text.length():
		var end = at + size
		if end > text.length(): end = text.length()
		out.append(text.slice(at, end))
		at = end

	return out

fn join_text(move input ReadStream[String]) String!:
	var source = input
	var out = ""

	while true:
		next := source.next()?
		text := next

		if text != null:
			out = out.concat(text)
		else:
			break

	return ok(out)

fn join_bytes(move input ReadStream[Bytes]) Bytes!:
	var source = input
	var out List[Bytes] = []

	while true:
		next := source.next()?
		data := next

		if data != null:
			out.append(data)
		else:
			break

	return ok(join(out))

test "base64 encoding matches the whole-value function under every chunk size":
	data := "hello, streams! \u{0}\u{ff}~~??".to_bytes()

	for size in 1..data.length() + 1:
		for url_safe in [false, true]:
			got := join_text(base64_encoded(chunked(data.clone(), size), url_safe))?
			if got != base64_encode(data.clone(), url_safe): return fail(
				f"size {size} url_safe {url_safe}"
			)

test "base64 decoding matches under every text piece size":
	data := "hello, streams! \u{0}\u{ff}~~??".to_bytes()
	text := base64_encode(data.clone())

	for size in 1..text.length() + 1:
		got := join_bytes(
			base64_decoded(ReadStream[String](Texts(pieces(text, size), 0)))
		)?
		if got != data: return fail(f"size {size}")

test "base64 decoding rejects malformed text and truncated groups":
	bad := join_bytes(base64_decoded(ReadStream[String](Texts(["aGVs", "bG8*"], 0))))
	expect_equal(bad.err().kind, "EBADMSG")?

	cut := join_bytes(base64_decoded(ReadStream[String](Texts(["aGVsb"], 0))))
	expect_equal(cut.err().kind, "EBADMSG")?

test "base64 decoding rejects data after padding at every chunk boundary":
	for text in ["Zg==Zg==", "Zm8=Zg==", "Zg==AAAA", "Zg==A", "Zg==="]:
		for url_safe in [false, true]:
			expect_equal(base64_decode(text, url_safe).err().kind, "EBADMSG")?

			for cut in 0..text.length() + 1:
				left := text.slice(0, cut)
				right := text.slice(cut, text.length())
				got := join_bytes(
					base64_decoded(
						ReadStream[String](
							Texts([left, "", right], 0)
						),
						url_safe,
					)
				)
				expect_equal(got.err().kind, "EBADMSG")?

test "base64 decoding permits empty chunks after terminal padding":
	for text in ["Zg==", "Zm8=", "Zm9v", ""]:
		for url_safe in [false, true]:
			for cut in 0..text.length() + 1:
				left := text.slice(0, cut)
				right := text.slice(cut, text.length())
				got := join_bytes(
					base64_decoded(
						ReadStream[String](
							Texts(
								[
									"", left, "", right, "", ""
								],
								0,
							)
						),
						url_safe,
					)
				)?
				expect_equal(got, base64_decode(text, url_safe)?)?

test "base64 terminal padding survives a rejected read":
	var same_chunk = base64_decoded(
		ReadStream[String](Texts(["Zg==A", "", "", "AAA", "", ""], 0))
	)
	expect_equal(same_chunk.next().err().kind, "EBADMSG")?
	expect_equal(same_chunk.next().err().kind, "EBADMSG")?
	expect_equal(same_chunk.next()?, null)?

	var later_chunk = base64_decoded(
		ReadStream[String](Texts(["Zg==", "A", "", "", "AAA", "", ""], 0))
	)
	expect_equal(
		(later_chunk.next()?) or panic("called Optional.get() on null"),
		"f".to_bytes(),
	)?
	expect_equal(later_chunk.next().err().kind, "EBADMSG")?
	expect_equal(later_chunk.next().err().kind, "EBADMSG")?
	expect_equal(later_chunk.next()?, null)?

test "hex steps round trip under every chunk size":
	data := "hex \u{0}\u{ff} data".to_bytes()

	for size in 1..data.length() + 1:
		text := join_text(hex_encoded(chunked(data.clone(), size)))?
		if text != hex_encode(data.clone()): return fail(f"encode size {size}")

		back := join_bytes(
			hex_decoded(ReadStream[String](Texts(pieces(text, size), 0)))
		)?
		if back != data: return fail(f"decode size {size}")

test "hex decoding rejects an odd tail":
	outcome := join_bytes(hex_decoded(ReadStream[String](Texts(["abc"], 0))))
	expect_equal(outcome.err().kind, "EBADMSG")?
