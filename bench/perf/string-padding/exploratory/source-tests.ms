import {expect_equal, expect_fault} from "@std/test.ms"

test "padding exact outputs cross cache and inline boundaries":
    try expect_equal("!".pad_start(1, "0"), "!")
    try expect_equal("!".pad_end(1, "0"), "!")
    try expect_equal("!".pad_start(1, "ab"), "!")
    try expect_equal("!".pad_end(1, "ab"), "!")
    try expect_equal("!".pad_start(1, "é🙂"), "!")
    try expect_equal("!".pad_end(1, "é🙂"), "!")
    try expect_equal("!".pad_start(2, "0"), "0!")
    try expect_equal("!".pad_end(2, "0"), "!0")
    try expect_equal("!".pad_start(2, "ab"), "a!")
    try expect_equal("!".pad_end(2, "ab"), "!a")
    try expect_equal("!".pad_start(2, "é🙂"), "é!")
    try expect_equal("!".pad_end(2, "é🙂"), "!é")
    try expect_equal("!".pad_start(15, "0"), "00000000000000!")
    try expect_equal("!".pad_end(15, "0"), "!00000000000000")
    try expect_equal("!".pad_start(15, "ab"), "ababababababab!")
    try expect_equal("!".pad_end(15, "ab"), "!ababababababab")
    try expect_equal("!".pad_start(15, "é🙂"), "é🙂é🙂é🙂é🙂é🙂é🙂é🙂!")
    try expect_equal("!".pad_end(15, "é🙂"), "!é🙂é🙂é🙂é🙂é🙂é🙂é🙂")
    try expect_equal("!".pad_start(16, "0"), "000000000000000!")
    try expect_equal("!".pad_end(16, "0"), "!000000000000000")
    try expect_equal("!".pad_start(16, "ab"), "abababababababa!")
    try expect_equal("!".pad_end(16, "ab"), "!abababababababa")
    try expect_equal("!".pad_start(16, "é🙂"), "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é!")
    try expect_equal("!".pad_end(16, "é🙂"), "!é🙂é🙂é🙂é🙂é🙂é🙂é🙂é")
    try expect_equal("!".pad_start(17, "0"), "0000000000000000!")
    try expect_equal("!".pad_end(17, "0"), "!0000000000000000")
    try expect_equal("!".pad_start(17, "ab"), "abababababababab!")
    try expect_equal("!".pad_end(17, "ab"), "!abababababababab")
    try expect_equal("!".pad_start(17, "é🙂"), "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂!")
    try expect_equal("!".pad_end(17, "é🙂"), "!é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂")
    try expect_equal("!".pad_start(31, "0"), "000000000000000000000000000000!")
    try expect_equal("!".pad_end(31, "0"), "!000000000000000000000000000000")
    try expect_equal("!".pad_start(31, "ab"), "ababababababababababababababab!")
    try expect_equal("!".pad_end(31, "ab"), "!ababababababababababababababab")
    try expect_equal("!".pad_start(31, "é🙂"), "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂!")
    try expect_equal("!".pad_end(31, "é🙂"), "!é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂")
    try expect_equal("!".pad_start(32, "0"), "0000000000000000000000000000000!")
    try expect_equal("!".pad_end(32, "0"), "!0000000000000000000000000000000")
    try expect_equal("!".pad_start(32, "ab"), "abababababababababababababababa!")
    try expect_equal("!".pad_end(32, "ab"), "!abababababababababababababababa")
    try expect_equal("!".pad_start(32, "é🙂"), "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é!")
    try expect_equal("!".pad_end(32, "é🙂"), "!é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é🙂é")
    try expect_equal("".pad_start(1, "0"), "0")
    try expect_equal("".pad_end(1, "0"), "0")
    try expect_equal("".pad_start(2, "x\u{0}y"), "x\u{0}")
    try expect_equal("".pad_end(2, "x\u{0}y"), "x\u{0}")
    try expect_equal(
        "".pad_start(17, "x\u{0}y"), "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}"
    )
    try expect_equal(
        "".pad_end(17, "x\u{0}y"), "x\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}yx\u{0}"
    )
    try expect_equal("é日😀".pad_start(4, "é🙂"), "éé日😀")
    try expect_equal("é日😀".pad_end(4, "é🙂"), "é日😀é")
    try expect_equal("é日😀".pad_start(5, "ab"), "abé日😀")
    try expect_equal("é日😀".pad_end(5, "ab"), "é日😀ab")
    try expect_equal("é日😀".pad_start(17, "é🙂"), "é🙂é🙂é🙂é🙂é🙂é🙂é🙂é日😀")
    try expect_equal("é日😀".pad_end(17, "é🙂"), "é日😀é🙂é🙂é🙂é🙂é🙂é🙂é🙂")

test "padding no-op cases preserve text":
    for target in [-9223372036854775808, -1, 0, 2, 3]:
        try expect_equal("é日😀".pad_start(target, "ab"), "é日😀")
        try expect_equal("é日😀".pad_end(target, "é🙂"), "é日😀")

    try expect_equal("é日😀".pad_start(9223372036854775807, ""), "é日😀")
    try expect_equal("".pad_end(9223372036854775807, ""), "")

test "large padding and small growth preserve exact bytes":
    let prefix = "q".repeat(1048575).get()
    try expect_equal("!".pad_start(1048576, "q"), prefix + "!")
    try expect_equal("!".pad_end(1048576, "q"), "!" + prefix)

    let mixed = "é日😀".repeat(116508).get()
    try expect_equal(mixed.pad_start(349527, "é🙂"), "é🙂é" + mixed)
    try expect_equal(mixed.pad_end(349527, "é🙂"), mixed + "é🙂é")

test "padding over the string limit faults before allocation":
    let start_message = try expect_fault(
        fn():
            let _ = "!".pad_start(9223372036854775807, "é🙂")
    )
    let end_message = try expect_fault(
        fn():
            let _ = "!".pad_end(9223372036854775807, "é🙂")
    )
    try expect_equal(start_message, "string: limit exceeded")
    try expect_equal(end_message, "string: limit exceeded")
