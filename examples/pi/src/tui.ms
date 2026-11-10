// Interactive terminal front end: a raw-mode line editor with history, and streamed output.
import (
	raw_mode, terminal_capabilities, TerminalEvent from "@std/cli/terminal.ms",
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

export fn bold(text: String) String:
	return "{esc}[1m{text}{esc}[0m"

export fn dim(text: String) String:
	return "{esc}[2m{text}{esc}[0m"

export fn red(text: String) String:
	return "{esc}[31m{text}{esc}[0m"

export fn is_interactive() Bool:
	caps := terminal_capabilities()
	return caps.input_is_terminal and caps.output_is_terminal

// Redraws the prompt line: clears it, prints the text, and puts the cursor back at `cursor`.
fn redraw(prompt: String, chars: List[String], cursor: Int) Unit:
	back := chars.length() - cursor
	tail := if back > 0: "{esc}[{back}D" else: ""
	write_out("\r{esc}[2K{prompt}{chars.join("")}{tail}")

// Reads one line with editing keys. Returns none on Ctrl-D with an empty line or Ctrl-C.
// Up and Down walk `history`; Enter submits; Ctrl-A, Ctrl-E, Ctrl-U and Ctrl-W work as in a shell.
export fn read_line(prompt: String, history: List[String]) String?!:
	raw := try raw_mode()
	var events = raw.events()
	var chars = List[String]()
	var cursor = 0
	var recall = history.length()
	redraw(prompt, chars, cursor)

	while true:
		next := try events.next()
		if next.is_none(): return ok(none)

		match next.get(none):
			Text(text):
				for c in text.chars():
					chars.insert(cursor, c.clone())
					cursor += 1
			Resize(_columns, _rows):
				write_err("")
			Key(name, ctrl, _alt, _shift):
				if name == "enter":
					write_out("\r\n")
					return ok(chars.join(""))

				if ctrl and name == "c":
					write_out("\r\n")
					return ok(none)

				if ctrl and name == "d" and chars.is_empty():
					write_out("\r\n")
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
					chars = List[String]()
					cursor = 0

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

		redraw(prompt, chars, cursor)

	return ok(none)
