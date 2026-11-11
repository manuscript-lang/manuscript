/*
Diffed redraw of a block of terminal rows.

A `Screen` remembers the rows it drew last. `draw` takes the rows the program wants now, finds the first row that
differs, and rewrites only from there down, so a prompt that grows a line at a time or a streaming answer repaints a
few rows instead of the whole block. Rows are plain strings that may carry escape sequences (see `@std/cli/style.ms`)
and must not be wider than the terminal; `wrap_text` and `truncate_text` produce rows that fit. The block sits at
the bottom of normal output, so scrollback above it is kept; `Screen.draw` clears everything only when a changed row has
already scrolled out of view. Every redraw is one write inside synchronized-output markers, so terminals that support
them show no half-drawn frame.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import new_screen from "@std/cli/screen.ms"
import raw_mode from "@std/cli/terminal.ms"

fn main() Unit!:
    raw := try raw_mode()
    var screen = new_screen()
    try screen.draw(raw, ["> hello", "status: ready"], 0, 7)
```
*/
import RawTerminal, terminal_size from "@std/cli/terminal.ms"

esc := "\u{1b}"

// Rows drawn so far and where the cursor was left, for diffing the next draw.
export type Screen:
	// The rows drawn last.
	previous: List[String]
	// The row, within `previous`, where the cursor was left.
	cursor_row: Int
	// Terminal height in rows, used to tell whether a changed row is still in view.
	height: Int

impl Screen:
	// Draws `rows` on `terminal` and leaves the cursor at `cursor_row` (an index into
	// `rows`, negative for the first) and `cursor_column`.
	var fn draw(
		terminal: RawTerminal,
		rows: List[String],
		cursor_row: Int,
		cursor_column: Int,
	) Unit!:
		return terminal.write(self.render(rows, cursor_row, cursor_column))

	// The bytes that turn what was drawn last into `rows`, which also become what was
	// drawn last. `draw` writes them; tests and custom outputs can use them directly.
	var fn render(rows: List[String], cursor_row: Int, cursor_column: Int) String:
		var diff = first_difference(self.previous, rows)
		last := self.previous.length() - 1
		unreachable := (
			not self.previous.is_empty()
			and diff < self.previous.length() - self.height
		)
		var out = "{esc}[?2026h"
		var at = self.cursor_row

		if unreachable:
			// A changed row scrolled out of reach: clear screen and scrollback and draw
			// everything.
			out = "{out}{esc}[2J{esc}[3J{esc}[H"
			at = 0
			diff = 0
		else:
			target := if diff > last: last else: diff
			target_row := if target < 0: 0 else: target
			out = "{out}{vertical(at, target_row)}"
			at = target_row

			if diff > last and last >= 0 and diff < rows.length():
				// Only new rows: step below the last drawn one.
				out = "{out}\r\n"
				at = diff

		var i = diff

		while i < rows.length():
			out = "{out}{esc}[2K{rows[i]}"
			at = i

			if i < rows.length() - 1:
				out = "{out}\r\n"
				at = i + 1

			i += 1

		out = "{out}{esc}[J"

		goal := if cursor_row < 0: 0 else: cursor_row
		out = "{out}{vertical(at, goal)}"
		if cursor_column > 0: out = "{out}{esc}[{cursor_column}C"
		out = "{out}{esc}[?2026l"
		self.previous = rows.clone()
		self.cursor_row = goal
		return out

	// Forgets what was drawn, for use after something wrote to the terminal behind the
	// screen; the next draw starts at the cursor.
	var fn reset() Unit:
		self.previous = List[String]()
		self.cursor_row = 0

		size := terminal_size()
		if size.is_ok(): self.height = size.get(none).rows

	// Updates the terminal height after a `Resize` event.
	var fn resize(rows: Int) Unit:
		self.height = rows

// A screen that starts drawing at the current cursor row; the height is the terminal's,
// or 24 when unknown.
// ms: effect std.console.read
export fn new_screen() Screen:
	size := terminal_size()
	rows := if size.is_error(): 24 else: size.get(none).rows
	return Screen(previous: List[String](), cursor_row: 0, height: rows)

fn first_difference(before: List[String], after: List[String]) Int:
	limit := if before.length() < after.length(): before.length() else: after.length()
	var i = 0
	while i < limit and before[i] == after[i]: i += 1
	return i

// The sequence moving the cursor from row `from` to row `to` within the block, then to
// the line start.
fn vertical(from: Int, to: Int) String:
	if from > to: return "{esc}[{from - to}A\r"
	if from < to: return "{esc}[{to - from}B\r"

	return "\r"
