import (
    hex_decode, hex_encode from "@std/data/encoding.ms",
    Bytes from "@std/bytes.ms",
    expect_equal from "@std/test/test.ms",
)

test "hex preflight preserves byte lengths and error precedence":
    let invalid: Bytes! = error(Error("encoding: invalid data", kind: "EBADMSG"))
    let negative: Bytes! = error(Error("encoding: invalid input", kind: "EINVAL"))
    let limited: Bytes! = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
    for text in ["", "a", "aaa", "zz", "é", "éa"]:
        try expect_equal(hex_decode(text, -1), negative)
    for text in ["aaa", "zz", "é", "éa"]:
        try expect_equal(hex_decode(text, 0), limited)
    for text in ["a", "zz", "é", "éa"]:
        try expect_equal(hex_decode(text, 1), invalid)
    try expect_equal(hex_decode("a", 0), invalid)
    try expect_equal(hex_decode("", 0), ok(Bytes([])))
    try expect_equal(hex_decode("00fF", 2), ok(Bytes([0, 255])))
    try expect_equal(hex_decode("00fF", none), ok(Bytes([0, 255])))

test "hex limits and round trips preserve actual nested byte views":
    let storage = Bytes([255, 254, 0, 15, 16, 127, 128, 253])
    let outer = storage.view(1, 8)
    let data = outer.view(1, 6)
    let text = hex_encode(data)
    try expect_equal(text, "000f107f80")
    try expect_equal(hex_decode(text, 5), ok(Bytes([0, 15, 16, 127, 128])))

    let limited: Bytes! = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
    try expect_equal(hex_decode(text, 4), limited)

test "hex rejects large over budget and odd inputs before digit validation":
    let text = "00".repeat(524288).get()
    let limited: Bytes! = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
    let invalid: Bytes! = error(Error("encoding: invalid data", kind: "EBADMSG"))
    try expect_equal(hex_decode(text, 0), limited)
    try expect_equal(hex_decode(text + "z", 524287), limited)
    try expect_equal(hex_decode(text + "z", 524288), invalid)
