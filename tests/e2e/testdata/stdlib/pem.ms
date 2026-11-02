import expect_equal, expect_ok, expect_true from "@std/test/test.ms"
import parse, encode_all, PemBlock, PemError from "@std/data/pem.ms"

let SAMPLE = "noise\n-----BEGIN NOTE-----\naGVsbG8gd29ybGQ=\n-----END NOTE-----\n-----BEGIN EMPTY-----\n-----END EMPTY-----\n"

test "parse finds blocks and ignores surrounding text":
    let blocks = parse(SAMPLE).get()
    try expect_equal(blocks.length(), 2)
    try expect_equal(blocks[0].label, "NOTE")
    try expect_equal(blocks[0].data.decode_utf8().get(""), "hello world")
    try expect_equal(blocks[1].data.length(), 0)

test "encode wraps at 64 columns and round-trips":
    let data = "x".repeat(100).get().to_bytes()
    let text = encode_all([PemBlock(label: "BLOB", data: data)])
    try expect_equal(text.lines()[1].length(), 64)

    let back = parse(text).get()
    try expect_equal(back[0].data.length(), 100)
    try expect_equal(back[0].label, "BLOB")

test "headers round-trip":
    var headers = Map[String, String]()
    headers.add("Proc-Type", "4,ENCRYPTED")

    let text = encode_all(
        [PemBlock(label: "KEY", headers: headers, data: "k".to_bytes())]
    )
    let back = parse(text).get()
    try expect_equal(back[0].headers.get("Proc-Type").get(""), "4,ENCRYPTED")
    try expect_equal(back[0].data.decode_utf8().get(""), "k")

test "malformed armor is an error":
    try expect_true(parse("-----BEGIN A-----\nAAAA\n").is_error())
    try expect_true(parse("-----BEGIN A-----\nAAAA\n-----END B-----\n").is_error())
    try expect_true(parse("-----BEGIN A-----\n!!!!\n-----END A-----\n").is_error())
