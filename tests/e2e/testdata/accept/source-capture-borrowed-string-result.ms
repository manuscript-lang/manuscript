import (
	Closeable from "@std/core.ms",
	append_file, read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_ok from "@std/test/test.ms",
)

type TextOwner:
	text: String
	log: String
	id: Int

fn var TextOwner.close() Unit!:
	append_file(self.log, "{self.id},").wait()?
	self.text = "closed"

fn TextOwner.read() String: self.text

fn TextOwner.read_default(_tag: Int = 0) String: self.text

fn owner(id: Int, log: String) TextOwner:
	return TextOwner("payload-{id}", log, id)

fn ordinary(log: String) String:
	read := owner(1, log).read
	return read()

fn defaulted(log: String) String:
	read := owner(2, log).read_default
	return read()

fn explicit_default(log: String) String:
	read := owner(3, log).read_default
	return read(9)

fn repeated(log: String) List[String]:
	read := owner(4, log).read
	first := read()
	second := read()
	return [first, second]

fn repeated_default(log: String) List[String]:
	read := owner(5, log).read_default
	first := read()
	second := read(7)
	return [first, second]

test "borrowed String method results outlive their owning source environments":
	tmp := temporary("source-capture-string-") | expect_ok?
	log := "{tmp.path()}/log"
	write_file(log, "").wait()?

	first := ordinary(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,")?
	expect_equal(first, "payload-1")?

	second := defaulted(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,")?
	expect_equal(second, "payload-2")?

	third := explicit_default(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,")?
	expect_equal(third, "payload-3")?

	fourth := repeated(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,")?
	expect_equal(fourth, ["payload-4", "payload-4"])?

	fifth := repeated_default(log.clone())
	expect_equal(read_file(log).wait().get().decode_utf8().get(""), "1,2,3,4,5,")?
	expect_equal(fifth, ["payload-5", "payload-5"])?
