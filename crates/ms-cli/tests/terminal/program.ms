import (
	TerminalEvent, EraseRegion, raw_mode from "@std/cli/terminal.ms",
	ReadStream from "@std/io/io.ms",
	promise, PromiseOptions from "@std/concurrency/promise.ms",
	stdout from "@std/io/io.ms",
	Duration, nanoseconds from "@std/time.ms",
)

fn describe(e: TerminalEvent) String:
	match e:
		Text(t): return "text:" + t
		Key(n, c, a, s): return "key:" + n + f" ctrl={c} alt={a} shift={s}"
		Resize(c, r): return f"resize:{c}x{r}"
		Paste(t): return "paste:" + t.replace("\n", "|")

fn next_event(var events: ReadStream[TerminalEvent], limit: Duration) TerminalEvent?!:
	return promise(fn: events.next()).with(
		options: PromiseOptions(timeout: limit)
	).wait()

export fn main() Int:
	raw := raw_mode(alternate_screen: false)

	if t := raw:
		var term = t
		void term.move_cursor(1, 2)
		void term.show_cursor(false)
		void term.erase(EraseRegion.LineEnd)
		void term.move_by(-1, 2)
		void term.set_title("t")
		if size := term.size():
			void stdout().write(f"size {size.columns}x{size.rows}\r\n")

		var events = term.events()
		var done = false

		while not done:
			next := next_event(var events, nanoseconds(5000000000))

			if maybe := next:
				if e := maybe:
					void stdout().write(describe(e.clone()) + "\r\n")
					done = describe(e) == "text:q"
				else:
					done = true
			else:
				void stdout().write("timeout\r\n")
				done = true

		void term.close()
		return 0

	void stdout().write("no raw mode\n")
	return 1
