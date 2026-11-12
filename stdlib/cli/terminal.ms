/*
Terminal detection, size, and raw input with cursor and screen control, on Linux, macOS and Windows.

`terminal_capabilities` reports whether the standard streams are terminals and how many colors they support. `raw_mode` acquires a `RawTerminal` whose `events()` stream yields keys, text, pastes and resizes. Bracketed paste and the extended keyboard protocols are on while it is held, so a paste arrives as one `Paste` event and Shift-Enter, Ctrl-Enter and the like arrive as an `enter` key with modifiers on terminals that report them. Cursor moves, erasing, the title and raw `write` go through the terminal so they stay ordered with buffered program output; styling and width helpers are in `@std/cli/style.ms` and the diffed redraw in `@std/cli/screen.ms`.
*/
import (
	Closeable from "@std/core.ms",
	ReadStream, Source from "@std/io/io.ms",

	msstd_terminal_capabilities_colors,
	msstd_terminal_capabilities_error_is_terminal,
	msstd_terminal_capabilities_input_is_terminal,
	msstd_terminal_capabilities_output_is_terminal,
	msstd_terminal_capabilities_raw_mode,
	msstd_terminal_capabilities_resize_events,
	msstd_terminal_input_text,
	msstd_terminal_raw_mode,
	msstd_terminal_raw_terminal_close,
	msstd_terminal_raw_terminal_read,
	msstd_terminal_raw_terminal_set_restore,
	msstd_terminal_raw_terminal_share,
	msstd_terminal_raw_terminal_size_columns,
	msstd_terminal_raw_terminal_size_rows,
	msstd_terminal_raw_terminal_size_status,
	msstd_terminal_raw_terminal_write,
	msstd_terminal_size_columns,
	msstd_terminal_size_rows,
	msstd_terminal_size_status from "@std/internal/io.ms",
)

// Character columns and rows of a terminal window.
export type TerminalSize:
	// Width in character columns.
	columns: Int
	// Height in character rows.
	rows: Int

/*
What the current process can do with its standard streams as a terminal.
`colors` is 0 when output is not a terminal, `NO_COLOR` is set, or `TERM` is
`dumb`; otherwise 16, 256, or 16777216 from `TERM` and `COLORTERM`.
*/
export type TerminalCapabilities:
	// True when standard input is a terminal.
	input_is_terminal: Bool
	// True when standard output is a terminal.
	output_is_terminal: Bool
	// True when standard error is a terminal.
	error_is_terminal: Bool
	// True when `raw_mode` can succeed on this host and the streams are terminals.
	raw_mode: Bool
	// True when raw terminals deliver `Resize` events.
	resize_events: Bool
	// Supported color count, or 0 when color output should be avoided.
	colors: Int

/*
One decoded terminal input event. `Text` carries printable characters typed
together. `Key` names a non-printing or modified key: `enter`, `tab`,
`backspace`, `escape`, `space`, `up`, `down`, `left`, `right`, `home`, `end`,
`insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with
`ctrl` or `alt` set. `Paste` carries text pasted as one unit, line breaks as `\n`. `Resize`
carries the new size.
*/
export enum TerminalEvent:
	// Printable characters typed together.
	Text(
		// The typed characters in order, as valid UTF-8 text.
		text: String
	)
	// A named or modified key press.
	Key(
		// The key name, such as `enter`, `up`, or a lowercase letter.
		name: String,
		// True when Control was held.
		ctrl: Bool,
		// True when Alt was held.
		alt: Bool,
		// True when Shift was held for a named key.
		shift: Bool
	)
	// The terminal window changed size.
	Resize(
		// The new width in columns.
		columns: Int,
		// The new height in rows.
		rows: Int
	)
	// Text pasted through bracketed paste, delivered whole.
	Paste(
		// The pasted text with line breaks as `\n`.
		text: String
	)

// The part of the screen cleared by `RawTerminal.erase`.
export enum EraseRegion:
	Screen  // Every cell of the screen; the cursor does not move.
	Line  // The whole cursor line.
	LineEnd  // From the cursor to the end of the line.
	LineStart  // From the start of the line to the cursor.
	ScreenEnd  // From the cursor to the end of the screen.
	ScreenStart  // From the start of the screen to the cursor.
	Scrollback  // The scrollback buffer above the screen.

// What one escape sequence in the input turned out to be.
type Parsed:
	// 0 incomplete, 1 decoded, 2 dropped, 3 overlong, 4 paste start.
	kind: Int
	event: TerminalEvent?
	// Scalars consumed.
	used: Int

fn key(name: String, ctrl: Bool, alt: Bool, shift: Bool) TerminalEvent:
	return TerminalEvent.Key(name, ctrl, alt, shift)

fn plain(name: String) TerminalEvent:
	return key(name, false, false, false)

fn control(b: Int, alt: Bool) TerminalEvent:
	if b == 13 or b == 10: return key("enter", false, alt, false)
	if b == 9: return key("tab", false, alt, false)
	if b == 127 or b == 8: return key("backspace", false, alt, false)
	if b == 0: return key("space", true, alt, false)

	letters := "abcdefghijklmnopqrstuvwxyz[\\]^_"
	return key(letters.get(b - 1, default: "?"), true, alt, false)

fn tilde_key(n: Int) String:
	var names = Map[Int, String]()
	names[1] = "home"
	names[7] = "home"
	names[2] = "insert"
	names[3] = "delete"
	names[4] = "end"
	names[8] = "end"
	names[5] = "page_up"
	names[6] = "page_down"
	names[11] = "f1"
	names[12] = "f2"
	names[13] = "f3"
	names[14] = "f4"
	names[15] = "f5"
	names[17] = "f6"
	names[18] = "f7"
	names[19] = "f8"
	names[20] = "f9"
	names[21] = "f10"
	names[23] = "f11"
	names[24] = "f12"
	if found := names.get(n): return found.clone()

	return ""

fn letter_key(c: Int) String:
	if c == 65: return "up"
	if c == 66: return "down"
	if c == 67: return "right"
	if c == 68: return "left"
	if c == 72: return "home"
	if c == 70: return "end"
	if c == 80: return "f1"
	if c == 81: return "f2"
	if c == 82: return "f3"
	if c == 83: return "f4"

	return ""

// Applies an xterm modifier parameter (1 plus shift 1, alt 2, ctrl 4) to a key event.
fn with_modifiers(event: TerminalEvent, modifier: Int) TerminalEvent:
	if modifier <= 1: return event.clone()

	bits := modifier - 1

	match event:
		Key(name, _ctrl, _alt, _shift):
			return key(
				name.clone(),
				bits / 4 % 2 == 1,
				bits / 2 % 2 == 1,
				bits % 2 == 1,
			)
		Text(_text): return event.clone()
		Resize(_columns, _rows): return event.clone()
		Paste(_text): return event.clone()

ascii := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz\{|\}~"

// The key a Unicode code point reported by `CSI u` or modifyOtherKeys names.
fn code_key(code: Int) TerminalEvent?:
	if code == 13 or code == 57414: return plain("enter")
	if code == 9: return plain("tab")
	if code == 27: return plain("escape")
	if code == 127 or code == 8: return plain("backspace")
	if code == 32: return plain("space")
	if code < 32: return none

	// Printable ASCII only; other code points are not reported as keys.
	if code > 126: return none

	return plain(ascii.get(code - 32, default: " "))

// The first colon-separated sub-parameter of a CSI parameter, as a number.
fn first_number(part: String) Int:
	head := part.split(":")[0].clone()
	return head.parse_int().get(0)

// The key a CSI sequence with parameters `params` and final byte `last` reports, if
// any.
fn csi_key(params: String, last: Int) TerminalEvent?:
	numbers := params.split(";").map(first_number)
	modifier := numbers.get(1, default: 1)
	if last == 90: return key("tab", false, false, true)

	var event: TerminalEvent? = none

	if last == 117:
		event = code_key(numbers[0])
	else if last == 126 and numbers[0] == 27:
		event = code_key(numbers.get(2, default: 0))
	else if last == 126:
		name := tilde_key(numbers[0])
		if not name.is_empty(): event = plain(name)
	else:
		name := letter_key(last)
		if not name.is_empty(): event = plain(name)

	if found := event: return with_modifiers(found, modifier)

	return none

fn parsed(kind: Int, used: Int) Parsed:
	return Parsed(kind: kind, event: none, used: used)

fn decoded(event: TerminalEvent, used: Int) Parsed:
	return Parsed(kind: 1, event: event, used: used)

// The scalar value of a one-scalar string.
fn code_of(c: String) Int:
	return c.scalar_at(0, -1)

// Concatenates `parts` in order. Pairwise merging keeps a long paste linear-ish without
// a string builder, which would make this module import a cycle.
fn concat_all(parts: List[String]) String:
	var level = parts.clone()

	while level.length() > 1:
		var next = List[String](reserve: level.length() / 2 + 1)
		var i = 0

		while i + 1 < level.length():
			next.append(level[i] + level[i + 1])
			i += 2

		if i < level.length(): next.append(level[i].clone())
		level = next

	if level.is_empty(): return ""

	return level[0].clone()

// Reads the CSI sequence starting at `at` (`ESC [`).
fn csi_at(buf: List[String], at: Int) Parsed:
	start := at + 2
	var j = start

	while j < buf.length():
		c := code_of(buf[j])
		is_param := c >= 32 and c <= 63
		if j - start >= 128 and is_param: return parsed(3, j - at)

		if c >= 64 and c <= 126:
			params := concat_all(buf.slice(start, j).get(List[String]()))
			if c == 126 and params == "200": return parsed(4, j + 1 - at)
			if event := csi_key(params, c): return decoded(event, j + 1 - at)

			return parsed(2, j + 1 - at)

		if not is_param: return parsed(2, j - at)

		j += 1

	return parsed(0, 0)

// Reads the escape sequence starting at `at`, which holds ESC.
fn escape_at(buf: List[String], at: Int) Parsed:
	if at + 1 >= buf.length(): return parsed(0, 0)

	c := code_of(buf[at + 1])
	if c == 91: return csi_at(buf, at)

	if c == 79:
		if at + 2 >= buf.length(): return parsed(0, 0)

		name := letter_key(code_of(buf[at + 2]))
		if name.is_empty(): return parsed(2, 3)

		return decoded(plain(name), 3)

	if c == 27: return decoded(plain("escape"), 1)
	if c < 32 or c == 127: return decoded(control(c, true), 2)
	if c == 32: return decoded(key("space", false, true, false), 2)

	return decoded(key(buf[at + 1].clone(), false, true, false), 2)

paste_end := ["\u{1b}", "[", "2", "0", "1", "~"]
// A paste longer than this many scalars keeps its most recent ones.
max_paste := 16777216

// Paste text with CRLF and lone CR line breaks turned into LF.
fn normalise_paste(body: List[String]) String:
	var out = List[String](reserve: body.length())
	var i = 0

	while i < body.length():
		c := body[i].clone()

		if c == "\r":
			out.append("\n")
			if i + 1 < body.length() and body[i + 1] == "\n": i += 1
		else:
			out.append(c)

		i += 1

	return concat_all(out)

/*
Turns terminal input text into `TerminalEvent`s. `decode` takes what a read returned and may hold back an
incomplete escape sequence for the next call; `flush` resolves a held lone escape into the Escape key once input
has gone quiet. Bracketed pastes become one `Paste` event however the input is split. `Resize` events do not come
from input; the event stream adds them.
*/
export type TerminalDecoder:
	// Characters of an escape sequence that is not complete yet.
	pending: List[String]
	// True between the paste start and end markers.
	pasting: Bool
	// Characters of the paste so far.
	paste: List[String]
	// True while the rest of an overlong CSI sequence is being dropped.
	discarding: Bool

// True when an escape sequence is waiting for more input.
fn TerminalDecoder.partial() Bool:
	return not self.pending.is_empty() and not self.pasting

// Resolves a held lone escape into the Escape key and drops any other unfinished
// sequence.
fn var TerminalDecoder.flush() List[TerminalEvent]:
	var out = List[TerminalEvent]()
	if not self.partial(): return out

	if self.pending.length() == 1: out.append(plain("escape"))
	self.pending = List[String]()
	return out

// Takes pasted characters from `buf` at `at`; returns where ordinary input resumes.
fn var TerminalDecoder.take_paste(
	buf: List[String],
	at: Int,
	var out: List[TerminalEvent],
) Int:
	old := self.paste.length()
	var taken = at

	while taken < buf.length():
		self.paste.append(buf[taken].clone())
		taken += 1

	var j = if old > 5: old - 5 else: 0
	last := self.paste.length() - paste_end.length()

	while j <= last:
		var k = 0
		while k < paste_end.length() and self.paste[j + k] == paste_end[k]: k += 1

		if k == paste_end.length():
			out.append(TerminalEvent.Paste(normalise_paste(self.paste.take(j))))

			used := j + paste_end.length() - old
			self.paste = List[String]()
			self.pasting = false
			return at + used

		j += 1

	if self.paste.length() > max_paste: self.paste = self.paste.drop(max_paste / 2)
	return buf.length()

// Decodes input text into events.
fn var TerminalDecoder.decode(text: String) List[TerminalEvent]:
	buf := self.pending.concat(text.chars())
	self.pending = List[String]()

	var out = List[TerminalEvent]()
	var run = List[String]()
	var i = 0

	while i < buf.length():
		b := code_of(buf[i])

		if self.pasting:
			i = self.take_paste(buf, i, var out)
			continue

		if self.discarding:
			if b >= 64 and b <= 126: self.discarding = false
			if b < 32 or b > 126: self.discarding = false
			if b >= 32 and b <= 126: i += 1
			continue

		if b != 27 and b >= 32 and b != 127:
			run.append(buf[i].clone())
			i += 1
			continue

		if not run.is_empty():
			out.append(TerminalEvent.Text(concat_all(run)))
			run = List[String]()

		if b != 27:
			out.append(control(b, false))
			i += 1
			continue

		r := escape_at(buf, i)

		if r.kind == 0:
			self.pending = buf.drop(i)
			return out

		if r.kind == 3: self.discarding = true

		if r.kind == 4:
			self.pasting = true
			self.paste = List[String]()

		if event := r.event: out.append(event.clone())
		i += r.used

	if not run.is_empty(): out.append(TerminalEvent.Text(concat_all(run)))
	return out

// A decoder with nothing pending.
export fn terminal_decoder() TerminalDecoder:
	return TerminalDecoder(
		pending: List[String](),
		pasting: false,
		paste: List[String](),
		discarding: false,
	)

fn read_size(handle: NativeRawTerminal) TerminalSize?:
	if msstd_terminal_raw_terminal_size_status(handle).is_error(): return none
	return TerminalSize(
		columns: msstd_terminal_raw_terminal_size_columns(handle),
		rows: msstd_terminal_raw_terminal_size_rows(handle),
	)

fn resized(before: TerminalSize?, now: TerminalSize) Bool:
	if last := before: return last.columns != now.columns or last.rows != now.rows
	return false

// Reads text from a raw terminal's native handle and decodes it into events.
type TerminalEvents:
	handle: RawHandle
	decoder: TerminalDecoder
	queue: List[TerminalEvent]
	size: TerminalSize?

fn var TerminalEvents.next() TerminalEvent?!:
	while true:
		if not self.queue.is_empty():
			event := self.queue[0].clone()
			self.queue.remove(0)
			return ok(event)

		// Window changes carry no input, so compare the size on every wake.
		now := read_size(self.handle.native)

		if current := now:
			if resized(self.size, current):
				self.size = current.clone()
				return ok(TerminalEvent.Resize(current.columns, current.rows))

			self.size = current.clone()

		waiting := self.decoder.partial()
		ready := msstd_terminal_raw_terminal_read(self.handle.native, waiting)?

		if ready.is_some():
			for event in self.decoder.decode(msstd_terminal_input_text()):
				self.queue.append(event.clone())
		else if waiting:
			// A quiet pause resolves a lone escape into the Escape key.
			for event in self.decoder.flush():
				self.queue.append(event.clone())

	return ok(none)

fn var TerminalEvents.close() Unit!:
	return ok(unit)

esc := "\u{1b}"
// Cursor positions beyond this are refused: older terminals cannot take larger numbers.
max_position := 65534

// The runtime handle behind a `RawTerminal`.
export extern type NativeRawTerminal

/*
Raw terminal input and cursor control. Closing it, or leaving the
scope that acquired it by return, error, fault, or cancellation, restores the
original terminal settings, shows the cursor, and leaves the alternate screen.
In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
*/
export type RawTerminal:
	// The runtime handle; the event stream holds another on the same terminal.
	handle: RawHandle

// Restores the terminal; closing again does nothing.
fn var RawTerminal.close() Unit!:
	msstd_terminal_raw_terminal_close(self.handle.native)

// Input events as a stream: keys, text and resizes, one per read. Waits honor
// cancellation and promise timeouts. The stream ends with an error once the
// terminal is closed; closing the stream leaves the terminal open.
fn RawTerminal.events() ReadStream[TerminalEvent]:
	return ReadStream[TerminalEvent](
		TerminalEvents(
			RawHandle(
				msstd_terminal_raw_terminal_share(self.handle.native)
			),
			terminal_decoder(),
			List[TerminalEvent](),
			read_size(self.handle.native),
		)
	)

// Returns the current terminal size, or `EBADF` after close.
fn RawTerminal.size() TerminalSize!:
	msstd_terminal_raw_terminal_size_status(self.handle.native)?
	return ok(
		TerminalSize(
			columns: msstd_terminal_raw_terminal_size_columns(
				self.handle.native
			),
			rows: msstd_terminal_raw_terminal_size_rows(self.handle.native),
		)
	)

// Writes text or escape sequences to the terminal, after any buffered program
// output. Fails with `EBADF` after close.
fn RawTerminal.write(text: String) Unit!:
	return msstd_terminal_raw_terminal_write(self.handle.native, text)

// Moves the cursor to a zero-based row and column; negative or very large values
// return `EINVAL`.
fn RawTerminal.move_cursor(row: Int, column: Int) Unit!:
	if row < 0 or column < 0 or row > max_position or column > max_position:
		return error(Error("terminal: position out of range", kind: "EINVAL"))
	return self.write("{esc}[{row + 1};{column + 1}H")

// Moves the cursor down by `rows` and right by `columns`; negative values move up
// and left. The cursor stops at the screen edge.
fn RawTerminal.move_by(rows: Int, columns: Int) Unit!:
	var out = ""
	if rows < 0: out = "{out}{esc}[{0 - rows}A"
	if rows > 0: out = "{out}{esc}[{rows}B"
	if columns > 0: out = "{out}{esc}[{columns}C"
	if columns < 0: out = "{out}{esc}[{0 - columns}D"
	if out.is_empty(): return ok(unit)

	return self.write(out)

// Moves the cursor to a zero-based column of its current row.
fn RawTerminal.move_to_column(column: Int) Unit!:
	if column < 0 or column > max_position:
		return error(Error("terminal: position out of range", kind: "EINVAL"))
	return self.write("{esc}[{column + 1}G")

// Remembers the cursor position for `restore_cursor`.
fn RawTerminal.save_cursor() Unit!:
	return self.write("{esc}7")

// Returns to the position remembered by `save_cursor`.
fn RawTerminal.restore_cursor() Unit!:
	return self.write("{esc}8")

// Shows or hides the cursor until the terminal is restored on close.
fn RawTerminal.show_cursor(visible: Bool) Unit!:
	return self.write(if visible: "{esc}[?25h" else: "{esc}[?25l")

// Erases the selected screen region without moving the cursor.
fn RawTerminal.erase(region: EraseRegion) Unit!:
	match region:
		Screen: return self.write("{esc}[2J")
		Line: return self.write("{esc}[2K")
		LineEnd: return self.write("{esc}[K")
		LineStart: return self.write("{esc}[1K")
		ScreenEnd: return self.write("{esc}[J")
		ScreenStart: return self.write("{esc}[1J")
		Scrollback: return self.write("{esc}[3J")

// Erases the screen and moves the cursor to the top left.
fn RawTerminal.clear() Unit!:
	return self.write("{esc}[2J{esc}[H")

// Sets the window title; control characters are removed first.
fn RawTerminal.set_title(title: String) Unit!:
	clean := title.replace("\u{7}", "").replace(esc, "").replace("\u{9c}", "")
	return self.write("{esc}]2;{clean}\u{7}")

// What the native `raw_mode` returns: the runtime handle itself.
export opaque type RawHandle:
	// The runtime terminal handle.
	native: NativeRawTerminal

// Reports terminal availability and color support without changing terminal state.
// ms: effect std.console.read
export fn terminal_capabilities() TerminalCapabilities:
	return TerminalCapabilities(
		input_is_terminal: msstd_terminal_capabilities_input_is_terminal(),
		output_is_terminal: msstd_terminal_capabilities_output_is_terminal(),
		error_is_terminal: msstd_terminal_capabilities_error_is_terminal(),
		raw_mode: msstd_terminal_capabilities_raw_mode(),
		resize_events: msstd_terminal_capabilities_resize_events(),
		colors: msstd_terminal_capabilities_colors(),
	)

// Returns the terminal size, or `ENOTTY` when output is redirected.
// ms: effect std.console.read
export fn terminal_size() TerminalSize!:
	msstd_terminal_size_status()?
	return ok(
		TerminalSize(
			columns: msstd_terminal_size_columns(),
			rows: msstd_terminal_size_rows(),
		)
	)

// Acquires raw input with an optional alternate screen; returns `EBUSY` while another
// raw terminal is open and `ENOTTY` when streams are redirected.
// ms: effect std.console.read
// ms: effect std.console.write
export fn raw_mode(alternate_screen: Bool = false) RawTerminal!:
	native := msstd_terminal_raw_mode()?
	leave := if alternate_screen: "{esc}[?1049l" else: ""
	enter := if alternate_screen: "{esc}[?1049h" else: ""

	// The restore text runs on close, at scope exit and at process exit: cursor, key
	// protocols, paste, screen.
	msstd_terminal_raw_terminal_set_restore(
		native,
		"{esc}[?25h{esc}[<u{esc}[>4;0m{esc}[?2004l{leave}",
	)
	msstd_terminal_raw_terminal_write(native, "{enter}{esc}[?2004h{esc}[>4;2m{esc}[>1u")?
	return ok(RawTerminal(handle: RawHandle(native)))
