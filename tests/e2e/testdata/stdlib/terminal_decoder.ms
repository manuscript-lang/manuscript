import (
	TerminalEvent, terminal_decoder from "@std/cli/terminal.ms",
	from_scalars from "@std/string.ms",
	expect_equal from "@std/test/test.ms",
)

fn key(name: String, ctrl: Bool, alt: Bool, shift: Bool) TerminalEvent:
	return TerminalEvent.Key(name, ctrl, alt, shift)

fn plain(name: String) TerminalEvent:
	return key(name, false, false, false)

// Joins adjacent text events, so a split read compares equal to a whole one.
fn merged(events: List[TerminalEvent]) List[TerminalEvent]:
	var out = List[TerminalEvent]()

	for event in events:
		match event:
			Text(more):
				if out.length() > 0:
					last := out[out.length() - 1].clone()

					if joined := text_of(last):
						out[out.length() - 1] = TerminalEvent.Text(
							joined + more.clone()
						)
						continue
				out.append(TerminalEvent.Text(more.clone()))
			_: out.append(event.clone())

	return out

fn text_of(event: TerminalEvent) String?:
	match event:
		Text(text): return text.clone()
		_: return none

test "text, controls and named keys":
	var d = terminal_decoder()
	try expect_equal(
		d.decode("ab\r\u{3}\u{7f}\u{0}"),
		[
			TerminalEvent.Text("ab"), plain("enter"), key("c", true, false, false),
			plain("backspace"), key("space", true, false, false)
		]
	)
	try expect_equal(
		d.decode("\u{1b}[A\u{1b}[3~\u{1b}OP\u{1b}[Z\u{1b}[1;5C\u{1b}[1;2H"),
		[
			plain("up"), plain("delete"), plain("f1"), key("tab", false, false, true),
			key("right", true, false, false), key("home", false, false, true)
		]
	)
	try expect_equal(
		d.decode("\u{1b}b\u{1b}\u{1b}x"),
		[
			key("b", false, true, false), plain("escape"), key("x", false, true, false)
		]
	)

test "a lone escape waits for a flush and unknown sequences are dropped":
	var d = terminal_decoder()
	try expect_equal(d.decode("\u{1b}"), List[TerminalEvent]())
	try expect_equal(d.partial(), true)
	try expect_equal(d.flush(), [plain("escape")])
	try expect_equal(d.partial(), false)
	try expect_equal(d.decode("\u{1b}[999z\u{1b}[?25hz"), [TerminalEvent.Text("z")])
	try expect_equal(d.decode("\u{1b}[1;"), List[TerminalEvent]())
	try expect_equal(d.flush(), List[TerminalEvent]())

test "modified Enter arrives from the kitty and modifyOtherKeys protocols":
	var d = terminal_decoder()
	try expect_equal(
		d.decode(
			"\u{1b}[13;2u\u{1b}[27;5;13~\u{1b}[99;5u\u{1b}[9;2u\u{1b}[27u\u{1b}[13;2:3u"
		),
		[
			key("enter", false, false, true), key("enter", true, false, false),
			key("c", true, false, false), key("tab", false, false, true),
			plain("escape"), key("enter", false, false, true)
		]
	)

test "a bracketed paste is one event however the input is split":
	whole := "a\u{1b}[200~one\r\ntwo\rthree\u{1b}[A\u{1b}[201~b"
	expected := [
		TerminalEvent.Text("a"), TerminalEvent.Paste("one\ntwo\nthree\u{1b}[A"),
		TerminalEvent.Text("b")
	]
	var d = terminal_decoder()
	try expect_equal(merged(d.decode(whole)), expected)

	scalars := whole.scalar_values()
	var cut = 1

	while cut < scalars.length():
		var split = terminal_decoder()
		head := scalars.take(cut)
		tail := scalars.drop(cut)
		var events = split.decode(from_scalars(head).get(""))
		events.extend(split.decode(from_scalars(tail).get("")))
		try expect_equal(merged(events), expected)
		cut += 1

	var empty = terminal_decoder()
	try expect_equal(
		empty.decode("\u{1b}[200~\u{1b}[201~\u{1b}[A"),
		[TerminalEvent.Paste(""), plain("up")]
	)

test "an overlong CSI sequence is dropped whole however it is split":
	var d = terminal_decoder()
	long := "1".repeat(300).get("")
	try expect_equal(d.decode("\u{1b}[{long}"), List[TerminalEvent]())
	try expect_equal(d.decode("{long}mok"), [TerminalEvent.Text("ok")])

test "an unterminated paste keeps waiting":
	var d = terminal_decoder()
	try expect_equal(d.decode("\u{1b}[200~partial"), List[TerminalEvent]())
	try expect_equal(d.partial(), false)
	try expect_equal(d.flush(), List[TerminalEvent]())
	try expect_equal(
		d.decode(" more\u{1b}[201~"), [TerminalEvent.Paste("partial more")]
	)
