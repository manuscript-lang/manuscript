// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Address,
	decode_words,
	parse_address,
	parse_address_list,
	parse_message from "@std/net/mail.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "addresses parse in each form":
	bare := parse_address("ada@example.com").get()
	expect_equal(bare.address, "ada@example.com")?
	expect_equal(bare.name, "")?

	named := parse_address("Ada Lovelace <ada@example.com>").get()
	expect_equal(named.name, "Ada Lovelace")?
	expect_equal(named.address, "ada@example.com")?

	quoted := parse_address("\"Lovelace, Ada\" <ada@example.com>").get()
	expect_equal(quoted.name, "Lovelace, Ada")?
	expect_equal(quoted.to_text(), "\"Lovelace, Ada\" <ada@example.com>")?
	expect_equal(named.to_text(), "Ada Lovelace <ada@example.com>")?

test "bad addresses are errors":
	expect_true(parse_address("").is_error())?
	expect_true(parse_address("no-at-sign").is_error())?
	expect_true(parse_address("Ada <ada@example.com").is_error())?
	expect_true(parse_address("@example.com").is_error())?

test "address lists honor quoted commas":
	list := parse_address_list("\"A, B\" <a@x.org>, c@y.org,").get()
	expect_equal(list.length(), 2)?
	expect_equal(list[0].name, "A, B")?
	expect_equal(list[1].address, "c@y.org")?
	expect_equal(parse_address_list("").get().length(), 0)?

test "messages split headers from body":
	mail := parse_message(
		"From: a@x.org\r\nSubject: Hi\r\n there\r\n\r\nBody line\r\nsecond"
	).get()
	expect_equal(mail.headers.get("subject").get(""), "Hi there")?
	expect_equal(mail.body, "Body line\r\nsecond")?

	lf := parse_message("To: b@y.org\n\nhello").get()
	expect_equal(lf.body, "hello")?
	expect_true(parse_message("  ").is_error())?

test "encoded words decode":
	expect_equal(decode_words("=?utf-8?B?SMOpbGxv?="), "Héllo")?
	expect_equal(decode_words("=?UTF-8?Q?caf=C3=A9_au_lait?="), "café au lait")?
	expect_equal(decode_words("=?iso-8859-1?Q?caf=E9?="), "café")?
	expect_equal(decode_words("=?utf-8?B?SGk=?= =?utf-8?B?IHRoZXJl?="), "Hi there")?
	expect_equal(decode_words("plain =?x"), "plain =?x")?
	expect_equal(parse_address("=?utf-8?B?SMOpbGxv?= <h@x.org>").get().name, "Héllo")?

test "encoded words keep literal text and scale linearly":
	expect_equal(decode_words("a=?b ?=c"), "a=?b ?=c")?
	expect_equal(decode_words("x =?utf-8?B?SGk=?= y"), "x Hi y")?
	expect_equal(decode_words("=?bad?X?zz?= =?utf-8?B?SGk=?="), "=?bad?X?zz?= Hi")?

	// A quadratic decoder would take minutes on this many words.
	big := decode_words("=?utf-8?B?SGk=?= x ".repeat(50000).get())
	expect_equal(big.scalar_length(), 50000 * 5)?

test "address lists keep escaped quotes and backslashes inside names":
	list := parse_address_list("\"A\\\", B\" <a@x.org>, c@y.org").get()
	expect_equal(list.length(), 2)?
	expect_equal(list[0].name, "A\", B")?
	expect_equal(list[0].address, "a@x.org")?
	expect_equal(list[1].address, "c@y.org")?

	slash := parse_address_list("\"A\\\\\" <a@x.org>, c@y.org").get()
	expect_equal(slash.length(), 2)?
	expect_equal(slash[0].name, "A\\")?

test "the first blank line ends the headers whatever its line ending":
	message := parse_message("Subject: hi\n\nline1\r\n\r\nline2").get()
	expect_equal(message.body, "line1\r\n\r\nline2")?

	crlf := parse_message("Subject: hi\r\n\r\nline1\n\nline2").get()
	expect_equal(crlf.body, "line1\n\nline2")?
