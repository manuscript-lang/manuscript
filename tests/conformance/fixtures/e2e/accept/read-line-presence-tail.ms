// conform: tags=testing,tier-io
// conform: phase=test
import (
	ReadStream from "@std/io/io.ms",
	lines from "@std/io/steps.ms",
	from_bytes from "@std/io/streams.ms",
	OpenMode, OpenOptions, open, temporary, write_file from "@std/os/fs.ms",
	expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms",
)

// A line read answers `String?`: an empty line is present, and only the end of the
// stream is none.
fn present(var input ReadStream[String]) Bool!:
	line := input.next()?
	return ok(line != null)

test "presence keeps empty CRLF lines and following text":
	var input = lines(from_bytes("\r\nλ\nlast".to_bytes(), 2))
	present(input) | expect_ok? | expect_true?
	(input.next()?) | expect_equal("λ")?
	present(input) | expect_ok? | expect_true?
	(present(input) | expect_ok? | expect_false?)
	(present(input) | expect_ok? | expect_false?)

test "presence retains limits":
	var input = lines(from_bytes("abc\nx\n".to_bytes(), 2), 2)
	present(input).is_error() | expect_true?

test "presence and text reads share buffered consumption":
	temporary := temporary("manuscript-presence-") | expect_ok?
	path := f"{temporary.path()}/lines"
	_written := write_file(path, "\nλ\r\nlast").wait() | expect_ok?
	handle := open(path, OpenMode.Read, OpenOptions(permissions: 384)) | expect_ok?
	var input = lines(handle.reader()?)
	present(input) | expect_ok? | expect_true?
	(input.next()?) | expect_equal("λ")?
	present(input) | expect_ok? | expect_true?
	(present(input) | expect_ok? | expect_false?)
