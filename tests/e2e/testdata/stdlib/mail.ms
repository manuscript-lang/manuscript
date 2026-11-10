import (
    expect_equal, expect_true from "@std/test/test.ms",
    parse_address,
    parse_address_list,
    parse_message,
    decode_words,
    Address from "@std/net/mail.ms",
)

test "addresses parse in each form":
    let bare = parse_address("ada@example.com").get()
    try expect_equal(bare.address, "ada@example.com")
    try expect_equal(bare.name, "")

    let named = parse_address("Ada Lovelace <ada@example.com>").get()
    try expect_equal(named.name, "Ada Lovelace")
    try expect_equal(named.address, "ada@example.com")

    let quoted = parse_address("\"Lovelace, Ada\" <ada@example.com>").get()
    try expect_equal(quoted.name, "Lovelace, Ada")
    try expect_equal(quoted.to_text(), "\"Lovelace, Ada\" <ada@example.com>")
    try expect_equal(named.to_text(), "Ada Lovelace <ada@example.com>")

test "bad addresses are errors":
    try expect_true(parse_address("").is_error())
    try expect_true(parse_address("no-at-sign").is_error())
    try expect_true(parse_address("Ada <ada@example.com").is_error())
    try expect_true(parse_address("@example.com").is_error())

test "address lists honor quoted commas":
    let list = parse_address_list("\"A, B\" <a@x.org>, c@y.org,").get()
    try expect_equal(list.length(), 2)
    try expect_equal(list[0].name, "A, B")
    try expect_equal(list[1].address, "c@y.org")
    try expect_equal(parse_address_list("").get().length(), 0)

test "messages split headers from body":
    let mail = parse_message(
        "From: a@x.org\r\nSubject: Hi\r\n there\r\n\r\nBody line\r\nsecond"
    ).get()
    try expect_equal(mail.headers.get("subject").get(""), "Hi there")
    try expect_equal(mail.body, "Body line\r\nsecond")

    let lf = parse_message("To: b@y.org\n\nhello").get()
    try expect_equal(lf.body, "hello")
    try expect_true(parse_message("  ").is_error())

test "encoded words decode":
    try expect_equal(decode_words("=?utf-8?B?SMOpbGxv?="), "Héllo")
    try expect_equal(decode_words("=?UTF-8?Q?caf=C3=A9_au_lait?="), "café au lait")
    try expect_equal(decode_words("=?iso-8859-1?Q?caf=E9?="), "café")
    try expect_equal(decode_words("=?utf-8?B?SGk=?= =?utf-8?B?IHRoZXJl?="), "Hi there")
    try expect_equal(decode_words("plain =?x"), "plain =?x")
    try expect_equal(
        parse_address("=?utf-8?B?SMOpbGxv?= <h@x.org>").get().name, "Héllo"
    )

test "encoded words keep literal text and scale linearly":
    try expect_equal(decode_words("a=?b ?=c"), "a=?b ?=c")
    try expect_equal(decode_words("x =?utf-8?B?SGk=?= y"), "x Hi y")
    try expect_equal(decode_words("=?bad?X?zz?= =?utf-8?B?SGk=?="), "=?bad?X?zz?= Hi")

    // A quadratic decoder would take minutes on this many words.
    let big = decode_words("=?utf-8?B?SGk=?= x ".repeat(50000).get())
    try expect_equal(big.scalar_length(), 50000 * 5)

test "address lists keep escaped quotes and backslashes inside names":
    let list = parse_address_list("\"A\\\", B\" <a@x.org>, c@y.org").get()
    try expect_equal(list.length(), 2)
    try expect_equal(list[0].name, "A\", B")
    try expect_equal(list[0].address, "a@x.org")
    try expect_equal(list[1].address, "c@y.org")

    let slash = parse_address_list("\"A\\\\\" <a@x.org>, c@y.org").get()
    try expect_equal(slash.length(), 2)
    try expect_equal(slash[0].name, "A\\")

test "the first blank line ends the headers whatever its line ending":
    let message = parse_message("Subject: hi\n\nline1\r\n\r\nline2").get()
    try expect_equal(message.body, "line1\r\n\r\nline2")

    let crlf = parse_message("Subject: hi\r\n\r\nline1\n\nline2").get()
    try expect_equal(crlf.body, "line1\n\nline2")
