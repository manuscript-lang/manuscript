// Formatting through `ms fmt`: the same formatter as the command line, so the editor
// and `ms fmt --check` never disagree.
import run_on_scratch from "./scratch.ms"

// The formatted text of `source`, or the formatter's message when it does not parse.
export fn format_document(path: String, source: String) Result[String, Error]:
	ran := run_on_scratch(path, source, ["fmt"])?

	if ran.output.exit_code != 0:
		message := ran.output.stderr.decode_utf8().get_or("").trim()
		return error(Error(message))

	return ok(ran.text.clone())
