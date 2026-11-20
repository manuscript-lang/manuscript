// Running the `ms` binary under test on one fixture and capturing what it did.
import (
	Bytes from "@std/bytes.ms",
	RunOptions, run from "@std/os/process.ms",
	Duration, milliseconds from "@std/time.ms",
)

export type Output:
	code: Int = 0
	stdout: String = ""
	stderr: String = ""
	timed_out: Bool = false
	// Set when the program could not start.
	spawn_error: String = ""

// The UTF-8 text of `data`, each byte that is not part of a valid scalar replaced by
// U+FFFD.
export fn lossy(data: Bytes) String:
	if text := data.decode_utf8(): return text

	var out = ""
	var at = 0
	size := data.length()

	while at < size:
		lead := data.get(at)
		width := if lead < 128: 1 else if lead >= 240: 4 else if lead >= 224: 3 else if lead >= 192: 2 else: 1

		if at + width <= size:
			if piece := data.decode_utf8_range(at, at + width):
				out += piece
				at += width
				continue

		out += "\u{FFFD}"
		at += 1

	return out

// The seconds of a timeout as the whole milliseconds a deadline counts.
export fn deadline(seconds: Float) Duration:
	return milliseconds((seconds * 1000.0).truncate_to_int().get_or(0))

// Runs `program` with `arguments` in `cwd`, feeding `stdin`, and stops it after
// `timeout`.
export fn execute(
	program: String,
	arguments: List[String],
	cwd: String,
	stdin: Bytes,
	timeout: Duration,
	env: Map[String, String],
) Output:
	options := RunOptions(input: stdin, timeout: timeout, cwd: cwd, env: env)
	finished := run(program, arguments, options).wait()

	if finished.is_error():
		failure := finished.err()
		if failure.kind == "ETIMEDOUT": return Output(code: 127, timed_out: true)

		return Output(code: 127, spawn_error: f"{program}: {failure.message}")

	done := finished.get()
	return Output(
		code: done.exit_code,
		stdout: lossy(done.stdout),
		stderr: lossy(done.stderr),
	)
