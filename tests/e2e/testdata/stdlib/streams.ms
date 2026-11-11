import (
	Bytes from "@std/bytes.ms",
	collect, copy, from_bytes, from_list, map, read_all from "@std/io/streams.ms",
	OpenMode, OpenOptions, open, read_file, temporary from "@std/os/fs.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
)

fn upper(chunk: Bytes) Bytes:
	return chunk.decode_utf8().get("").upper().to_bytes()

test "flows compose stream transforms":
	temporary := temporary("manuscript-streams-") | expect_ok?
	path := "{temporary.path()}/pipeline.bin"
	var output = open(path, OpenMode.Write, OpenOptions(permissions: 420)) | expect_ok?
	source := from_bytes("hello world".to_bytes(), 4)
	copied := copy(map(source, upper), output.writer()?)?
	output.close()?
	expect_equal(copied, 3)?
	expect_equal((read_file(path: path).wait() | expect_ok?), "HELLO WORLD".to_bytes())?

test "from_list and collect bridge lists and streams":
	doubled := map(from_list([1, 2, 3]), fn(n: Int) Int: n * 2)
	expect_equal((collect(doubled, none)?), [2, 4, 6])?

	limited := collect(from_list([1, 2, 3]), 2)
	expect_equal(limited.is_error(), true)?

test "read_all joins chunks and enforces its limit":
	expect_equal(
		(read_all(from_bytes("abcdef".to_bytes(), 4), none)?),
		"abcdef".to_bytes(),
	)?
	expect_equal(read_all(from_bytes("abcdef".to_bytes(), 4), 5).is_error(), true)?

test "from_bytes rejects a chunk size below one instead of never ending":
	for size in [0, -1]:
		var source = from_bytes("abc".to_bytes(), size)
		first := expect_error(source.next())?
		expect_equal(first.kind, "EINVAL")?
