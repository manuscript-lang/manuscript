// Interactive terminal front end: a raw-mode line editor with history, and streamed output.
import (
	monotonic from "@std/time.ms",
	sleep, hours from "@std/time.ms",
	Cancel, Signal, cancel_switch, local_promise from "@std/concurrency/promise.ms",
	ReadStream from "@std/io/io.ms",
	raw_mode, terminal_capabilities, terminal_size, RawTerminal, TerminalEvent from "@std/cli/terminal.ms",
	stdout, stderr from "@std/io/io.ms",
)

export fn write_out(text: String) Unit:
	var w = stdout()
	w.write(text).get(unit)
	w.flush().get(unit)

export fn write_err(text: String) Unit:
	var w = stderr()
	w.write(text).get(unit)
	w.flush().get(unit)

esc := "\u{1b}"
commands := [
	"/help", "/exit", "/session", "/tools", "/usage", "/model", "/thinking", "/compact",
	"/tree", "/fork", "/new"
]

export fn bold(text: String) String:
	return "{esc}[1m{text}{esc}[0m"

export fn dim(text: String) String:
	return "{esc}[2m{text}{esc}[0m"

export fn red(text: String) String:
	return "{esc}[31m{text}{esc}[0m"

export fn is_interactive() Bool:
	caps := terminal_capabilities()
	return caps.input_is_terminal and caps.output_is_terminal

// The editor and footer as screen rows, plus where the cursor sits among them.
type Frame:
	rows: List[String]
	cursor_row: Int
	cursor_column: Int

// Lays out the text in rows of at most `width` columns (wrapping and explicit newlines), then the footer.
fn layout(
	prompt_width: Int,
	prompt: String,
	chars: List[String],
	cursor: Int,
	width: Int,
	footer: String
) Frame:
	room := if width - prompt_width > 9: width - prompt_width - 1 else: 8
	var rows = List[String]()
	var row = ""
	var used = 0
	var cursor_row = 0
	var cursor_column = prompt_width
	var i = 0

	while i <= chars.length():
		if i == cursor:
			cursor_row = rows.length()
			cursor_column = prompt_width + used

		if i == chars.length(): break

		c := chars[i]

		if c == "\n":
			rows.append(row.clone())
			row = ""
			used = 0
		else:
			if used >= room:
				rows.append(row.clone())
				row = ""
				used = 0

				if i == cursor:
					cursor_row = rows.length()
					cursor_column = prompt_width

			row = "{row}{c}"
			used += 1

		i += 1

	rows.append(row.clone())

	var lines = List[String]()
	var n = 0

	for r in rows:
		lead := if n == 0: prompt.clone() else: " ".repeat(prompt_width).get("")
		lines.append("{lead}{r}")
		n += 1

	lines.append(dim(footer.take(width - 1)))
	return Frame(rows: lines, cursor_row: cursor_row, cursor_column: cursor_column)

// Draws `frame` over the `previous` one in place: unchanged rows are skipped, extra rows are cleared.
// `at` is the row the cursor was left on; returns nothing because the caller keeps `frame` for next time.
fn paint(previous: List[String], at: Int, frame: Frame) Unit:
	var out = ""
	if at > 0: out = "{esc}[{at}A"
	out = "{out}\r"

	var i = 0

	while i < frame.rows.length():
		changed := i >= previous.length() or previous[i] != frame.rows[i]
		if changed: out = "{out}{esc}[2K{frame.rows[i]}"
		if i < frame.rows.length() - 1: out = "{out}\r\n"
		i += 1

	out = "{out}{esc}[J"

	up := frame.rows.length() - 1 - frame.cursor_row
	if up > 0: out = "{out}{esc}[{up}A"
	out = "{out}\r"
	if frame.cursor_column > 0: out = "{out}{esc}[{frame.cursor_column}C"
	write_out(out)

fn columns() Int:
	size := terminal_size()
	if size.is_error(): return 80

	return size.get(none).columns

fn previous_word(chars: List[String], cursor: Int) Int:
	var at = cursor
	while at > 0 and chars[at - 1] == " ": at -= 1
	while at > 0 and chars[at - 1] != " ": at -= 1
	return at

// Reads a (possibly multi-line) prompt in an in-place editor with a footer line.
// Enter submits; Alt-Enter, or an Enter that arrives right behind other input (a paste), inserts a newline.
// Up and Down walk `history`; Tab completes slash commands; Ctrl-A/E/U/K/W and Alt-B/F edit as in a shell.
// Returns none on Ctrl-D with an empty editor, or Ctrl-C on an empty one.
export fn read_line(prompt: String, history: List[String], footer: String) String?!:
	raw := try raw_mode()
	var events = raw.events()
	var chars = List[String]()
	var cursor = 0
	var recall = history.length()
	var shown = List[String]()
	var at = 0
	var last = monotonic()
	width := prompt.display_width().get(2)
	var frame = layout(width, prompt, chars, cursor, columns(), footer)
	paint(shown, at, frame)
	shown = frame.rows.clone()
	at = frame.cursor_row

	while true:
		next := try events.next()
		if next.is_none(): return ok(none)

		now_tick := monotonic()
		burst := now_tick.difference(last).to_nanoseconds() < 15000000
		last = now_tick

		match next.get(none):
			Text(text):
				for c in text.chars():
					chars.insert(cursor, c.clone())
					cursor += 1
			Resize(_columns, _rows):
				write_err("")
			Key(name, ctrl, alt, _shift):
				if name == "enter" and (alt or burst):
					chars.insert(cursor, "\n")
					cursor += 1
				else if name == "enter":
					final := layout(width, prompt, chars, cursor, columns(), "")
					var kept = final.rows.take(final.rows.length() - 1)
					kept.append("")

					last_row := kept.length() - 1
					paint(
						shown,
						at,
						Frame(
							rows: kept, cursor_row: last_row, cursor_column: 0
						)
					)
					return ok(chars.join(""))

				if name == "tab" and chars.length() > 1 and chars[0] == "/":
					typed := chars.join("")
					found := commands.filter(fn c: c.starts_with(typed))

					if found.length() == 1:
						chars = "{found[0]} ".chars()
						cursor = chars.length()

				if ctrl and name == "c":
					if chars.is_empty():
						write_out("{esc}[J\r\n")
						return ok(none)

					chars = List[String]()
					cursor = 0

				if ctrl and name == "d" and chars.is_empty():
					write_out("{esc}[J\r\n")
					return ok(none)

				if name == "backspace" and cursor > 0:
					chars.remove(cursor - 1)
					cursor -= 1

				if name == "delete" and cursor < chars.length(): chars.remove(cursor)
				if name == "left" and cursor > 0: cursor -= 1
				if name == "right" and cursor < chars.length(): cursor += 1
				if name == "home" or (ctrl and name == "a"): cursor = 0
				if name == "end" or (ctrl and name == "e"): cursor = chars.length()

				if ctrl and name == "u":
					chars = chars.drop(cursor)
					cursor = 0

				if ctrl and name == "k": chars = chars.take(cursor)

				if ctrl and name == "w":
					start := previous_word(chars, cursor)
					chars = chars.take(start).concat(chars.drop(cursor))
					cursor = start

				if alt and name == "b": cursor = previous_word(chars, cursor)

				if alt and name == "f":
					while cursor < chars.length() and chars[cursor] == " ": cursor += 1
					while cursor < chars.length() and chars[cursor] != " ": cursor += 1

				if name == "up" and recall > 0:
					recall -= 1
					chars = history[recall].chars()
					cursor = chars.length()

				if name == "down" and recall < history.length():
					recall += 1
					chars = if recall < history.length(): history[recall].chars() else: List[
						String
					]()
					cursor = chars.length()

				if name == "space":
					chars.insert(cursor, " ")
					cursor += 1

		frame = layout(width, prompt, chars, cursor, columns(), footer)
		paint(shown, at, frame)
		shown = frame.rows.clone()
		at = frame.cursor_row

	return ok(none)

// Reads keys until Escape or Ctrl-C, then fires `stop`; ends quietly when the terminal closes.
fn watch_keys(raw: RawTerminal, stop: Cancel) Unit!:
	var keys = raw.events()

	while true:
		next := try keys.next()
		if next.is_none(): return ok(unit)

		if aborts(next.get(none)):
			stop.cancel()

			// Stay alive: dropping `stop` would free the switch, and its signals would stop reading as cancelled.
			try sleep(hours(1)).wait()
			return ok(unit)

	return ok(unit)

fn aborts(event: TerminalEvent) Bool:
	match event:
		Key(name, ctrl, _alt, _shift): return name == "escape" or (ctrl and name == "c")
		_: return false

// Runs `work` while Escape or Ctrl-C raise the signal it receives.
export fn with_abort[T](work: fn(Signal) T!) T!:
	stop := cancel_switch()
	raw := try raw_mode()
	signal := stop.signal()
	watcher := local_promise[Unit](fn: watch_keys(raw, stop))
	result := work(signal)
	watcher.cancel()
	return result
