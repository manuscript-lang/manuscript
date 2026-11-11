import (
	PemBlock, encode_all, parse from "@std/data/pem.ms",
	expect_equal, expect_ok, expect_true from "@std/test/test.ms",
)

SAMPLE := "noise\n-----BEGIN NOTE-----\naGVsbG8gd29ybGQ=\n-----END NOTE-----\n-----BEGIN EMPTY-----\n-----END EMPTY-----\n"

test "parse finds blocks and ignores surrounding text":
	blocks := parse(SAMPLE).get()
	expect_equal(blocks.length(), 2)?
	expect_equal(blocks[0].label, "NOTE")?
	expect_equal(blocks[0].data.decode_utf8().get(""), "hello world")?
	expect_equal(blocks[1].data.length(), 0)?

test "encode wraps at 64 columns and round-trips":
	data := "x".repeat(100).get().to_bytes()
	text := encode_all([PemBlock(label: "BLOB", data: data)])
	expect_equal(text.lines()[1].length(), 64)?

	back := parse(text).get()
	expect_equal(back[0].data.length(), 100)?
	expect_equal(back[0].label, "BLOB")?

test "headers round-trip":
	var headers = Map[String, String]()
	headers.add("Proc-Type", "4,ENCRYPTED")

	text := encode_all([PemBlock(label: "KEY", headers: headers, data: "k".to_bytes())])
	back := parse(text).get()
	expect_equal(back[0].headers.get_or("Proc-Type", ""), "4,ENCRYPTED")?
	expect_equal(back[0].data.decode_utf8().get(""), "k")?

test "malformed armor is an error":
	expect_true(parse("-----BEGIN A-----\nAAAA\n").is_error())?
	expect_true(parse("-----BEGIN A-----\nAAAA\n-----END B-----\n").is_error())?
	expect_true(parse("-----BEGIN A-----\n!!!!\n-----END A-----\n").is_error())?
