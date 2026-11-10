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

// Characters on screen in `text`: escape sequences take no room.
fn visible_length(text: String) Int:
	var n = 0
	var in_escape = false

	for c in text.chars():
		if in_escape:
			if c == "m" or c == "K" or c == "J" or c == "A" or c == "B" or c == "C": in_escape = false
			continue

		if c == esc:
			in_escape = true
			continue

		n += 1

	return n

// Splits `text` on newlines and wraps each line at `width` visible characters.
fn wrap_lines(text: String, width: Int) List[String]:
	var out = List[String]()

	for line in text.split("\n"):
		if visible_length(line) <= width:
			out.append(line.clone())
			continue

		var row = ""
		var used = 0
		var in_escape = false

		for c in line.chars():
			if in_escape:
				row = "{row}{c}"
				if c == "m": in_escape = false
				continue

			if c == esc:
				in_escape = true
				row = "{row}{c}"
				continue

			if used >= width:
				out.append("{row}{esc}[0m")
				row = ""
				used = 0

			row = "{row}{c}"
			used += 1

		out.append(row)

	return out

// The whole conversation as retained lines, drawn by diffing each new frame against the last one:
// only rows from the first change down are rewritten, and a change above the viewport redraws everything.
export type Screen:
	// Finished transcript rows.
	lines: List[String]
	// Rows of the component still streaming.
	live: List[String]
	// The last frame drawn and the row the cursor was left on.
	prev: List[String]
	at: Int
	width: Int
	height: Int

export fn new_screen() Screen:
	size := terminal_size()
	columns := if size.is_error(): 80 else: size.get(none).columns
	rows := if size.is_error(): 24 else: size.get(none).rows
	return Screen(
		lines: List[String](), live: List[String](), prev: List[String](), at: 0,
		width: columns, height: rows
	)

fn first_difference(before: List[String], after: List[String]) Int:
	limit := if before.length() < after.length(): before.length() else: after.length()
	var i = 0
	while i < limit and before[i] == after[i]: i += 1
	return i

impl Screen:
	// Appends finished text to the transcript.
	var fn commit(text: String) Unit:
		self.lines.extend(wrap_lines(text, self.width))

	// Replaces the streaming component's rows.
	var fn set_live(text: String) Unit:
		if text.is_empty():
			self.live = List[String]()
		else:
			self.live = wrap_lines(text, self.width)

	// Forgets everything drawn so far; used after output written behind the screen's back.
	var fn reset() Unit:
		self.lines = List[String]()
		self.live = List[String]()
		self.prev = List[String]()
		self.at = 0

		size := terminal_size()

		if size.is_ok():
			self.width = size.get(none).columns
			self.height = size.get(none).rows

	// Draws transcript, live rows and `tail`, leaving the cursor at `cursor_row` (within the tail) and `cursor_column`.
	var fn draw(tail: List[String], cursor_row: Int, cursor_column: Int) Unit:
		var frame = self.lines.clone()
		frame.extend(self.live)

		cursor_abs := frame.length() + cursor_row
		frame.extend(tail)

		var d = first_difference(self.prev, frame)
		full := self.prev.length() > 0 and d < self.prev.length() - self.height
		var out = ""
		var row = self.at
		last_prev := self.prev.length() - 1
		var create = false

		if full:
			out = "{esc}[2J{esc}[3J{esc}[H"
			row = 0
			d = 0
		else:
			var target = if d > last_prev: last_prev else: d
			if target < 0: target = 0
			if row > target: out = "{esc}[{row - target}A"
			if row < target: out = "{esc}[{target - row}B"
			row = target
			out = "{out}\r"
			create = d > last_prev and last_prev >= 0

		if create:
			out = "{out}\r\n"
			row = d

		var i = d

		while i < frame.length():
			out = "{out}{esc}[2K{frame[i]}"
			row = i

			if i < frame.length() - 1:
				out = "{out}\r\n"
				row = i + 1

			i += 1

		out = "{out}{esc}[J"

		target_row := if cursor_abs < 0: 0 else: cursor_abs
		if row > target_row: out = "{out}{esc}[{row - target_row}A"
		if row < target_row: out = "{out}{esc}[{target_row - row}B"
		out = "{out}\r"
		if cursor_column > 0: out = "{out}{esc}[{cursor_column}C"
		write_out(out)
		self.prev = frame
		self.at = target_row

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
export fn read_line(
	var screen: Screen, prompt: String, history: List[String], footer: String
) String?!:
	raw := try raw_mode()
	var events = raw.events()
	var chars = List[String]()
	var cursor = 0
	var recall = history.length()
	var last = monotonic()
	width := prompt.display_width().get(2)
	var frame = layout(width, prompt, chars, cursor, columns(), footer)
	screen.draw(frame.rows, frame.cursor_row, frame.cursor_column)

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
					kept := final.rows.take(final.rows.length() - 1)
					screen.commit(kept.join("\n"))
					screen.draw(List[String](), -1, 0)
					return ok(chars.join(""))

				if name == "tab" and chars.length() > 1 and chars[0] == "/":
					typed := chars.join("")
					found := commands.filter(fn c: c.starts_with(typed))

					if found.length() == 1:
						chars = "{found[0]} ".chars()
						cursor = chars.length()

				if ctrl and name == "c":
					if chars.is_empty():
						screen.draw(List[String](), -1, 0)
						return ok(none)

					chars = List[String]()
					cursor = 0

				if ctrl and name == "d" and chars.is_empty():
					screen.draw(List[String](), -1, 0)
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
		screen.draw(frame.rows, frame.cursor_row, frame.cursor_column)

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
