import Closeable, Iterator from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import (
    msstd_terminal_event_kind,
    msstd_terminal_event_text,
    msstd_terminal_event_ctrl,
    msstd_terminal_event_alt,
    msstd_terminal_event_shift,
    msstd_terminal_event_columns,
    msstd_terminal_event_rows,
    msstd_io_copy,
    msstd_io_read_all,
    msstd_io_read_line,
    msstd_io_redirect_null,
    msstd_io_stdin,
    msstd_io_stdout,
    msstd_io_stderr,
    msstd_io_files,
    msstd_io_terminal,
    msstd_terminal_raw_terminal_close,
    msstd_terminal_raw_terminal_next_event,
    msstd_terminal_raw_terminal_size_status,
    msstd_terminal_raw_terminal_size_columns,
    msstd_terminal_raw_terminal_size_rows,
    msstd_terminal_raw_terminal_move_cursor,
    msstd_terminal_raw_terminal_show_cursor,
    msstd_terminal_raw_terminal_erase
) from "@std/internal/io.ms"

# A file-like byte stream that returns `none` at end of input.
export interface File:
    # Releases the file resource; retained aliases do not extend its open lifetime.
    fn close() Unit
    # Returns a byte chunk or none at EOF; max_bytes is a positive chunk size, not a total budget.
    # Omission/none uses the native 64 KiB chunk; source implementations define their own buffering.
    fn read(max_bytes: Int?) Bytes?!

# Opens read-only file resources using the current host's default filesystem.
# Native open failures (including missing paths and permission denial) become an `Error` of kind `Unavailable`.
interface Files:
    # Opens path for read-only access; native missing, denied, and other open failures become Unavailable.
    fn open(path: String) File!

# A readable byte stream. Each read returns a chunk or `none` at end of stream.
export interface ReadStream:
    # Releases this implementation's read resource; ownership of underlying handles is implementation-defined.
    var fn close() Unit
    # Returns a chunk or none at EOF; a final nonempty chunk can precede EOF.
    # A supplied positive max_bytes requests a chunk size; native omission/none uses 64 KiB.
    var fn read(max_bytes: Int? = none) Bytes?!

# A writable byte stream. Successful write accepts all bytes; failure may leave an external prefix.
# Buffering/flush depends on the implementation: native stderr is unbuffered and native stdout is buffered when not a terminal (flush drains it),
# while FileHandle.writer().flush synchronizes the file. Success does not acknowledge peer processing.
export interface WriteStream:
    # Releases this implementation's write resource; close does not imply a successful flush.
    var fn close() Unit
    # Completes implementation-specific buffering or synchronization; native stdout drains its buffer and stderr has none.
    # File-handle writers synchronize the file, and failures keep their `Error` kind.
    var fn flush() Unit!
    # Accepts the complete input on success; a source implementation may buffer until flush.
    var fn write(data: String) Unit!
    # Accepts the complete bytes on success, with the buffering rules of write.
    var fn write_bytes(data: Bytes) Unit!

# Copies bytes until end of input and returns the count. Input beyond `max_bytes` returns LimitExceeded.
export fn copy(input: ReadStream, output: WriteStream, max_bytes: Int?) Int!:
    return msstd_io_copy(input, output, max_bytes)

# Reads a stream completely into memory. Supply a limit for untrusted streams.
export fn read_all(input: ReadStream, max_bytes: Int?) Bytes!:
    return msstd_io_read_all(input, max_bytes)

# Reads one line from a stream such as `stdin()`, omitting its line ending; returns `none` at end of stream.
# `max_bytes` counts the terminator: a newline-ended line must be shorter than it, an unterminated last line may equal it. To read every line, iterate `lines(input)`.
export fn read_line(input: ReadStream, max_bytes: Int?) String?!:
    return msstd_io_read_line(input, max_bytes)

# Lines of a stream, read on demand. `for line in reader:` walks the lines without their
# terminators (`\n` or `\r\n`) and stops at end of input, at the first I/O error, or at a line
# longer than `max_bytes`; `error()` then tells the last two apart from a clean end.
#
# Iterate a `var` reader with `for` so the loop advances it in place and `error()` can be read
# afterwards; see "Read standard input line by line" in the common tasks guide.
export type LineReader:
    # The stream being read.
    input: ReadStream
    # Per-line byte limit, or none for no limit.
    max_bytes: Int?
    # The error that ended iteration, if any.
    failure: Error?

impl LineReader:
    # Returns the I/O error that ended iteration, or none after a clean end of input
    # (and while lines remain). A line over the limit reports `LimitExceeded`.
    fn error() Error?:
        return self.failure.clone()

impl Iterator[String] for LineReader:
    # Returns the next line, or none at end of input or after an error (see `error()`).
    var fn next() String?:
        if self.failure.is_some():
            return none

        let line = read_line(self.input, self.max_bytes)

        if line.is_error():
            self.failure = line.err().clone()
            return none

        let text = line.get()
        if text.is_none():
            return none

        return text.get().clone()

# Returns a reader over the lines of `input`, for `for line in reader:`. `max_bytes` bounds each
# line, as in `read_line`.
export fn lines(input: ReadStream, max_bytes: Int?) LineReader:
    return LineReader(input, max_bytes, none)

# Returns the process standard-input stream.
export fn stdin() ReadStream:
    return msstd_io_stdin()

# Returns the process standard-output stream.
export fn stdout() WriteStream:
    return msstd_io_stdout()

# Returns the process standard-error stream.
export fn stderr() WriteStream:
    return msstd_io_stderr()

# One of this process's three standard streams.
export type StdStream:
    # Standard input; once redirected it reads as end of file.
    case Input
    # Standard output; once redirected its writes are discarded.
    case Output
    # Standard error; once redirected its writes are discarded.
    case Error

# Points the process's own standard stream at the null device (`/dev/null`, or `NUL` on Windows): input reads as end of file and output is discarded.
# This replaces the descriptor itself, so it also affects children started afterwards that inherit it. Buffered standard output is written first. The change cannot be undone.
export fn redirect_to_null(stream: StdStream) Unit!:
    var which = 2

    match stream:
        Input: which = 0
        Output: which = 1
        Error: which = 2

    return msstd_io_redirect_null(which)

# Returns file operations for the current host.
fn host_files() Files:
    return msstd_io_files()

# Character columns and rows of a terminal window.
export type TerminalSize:
    # Width in character columns.
    columns: Int
    # Height in character rows.
    rows: Int

# What the current process can do with its standard streams as a terminal.
# `colors` is 0 when output is not a terminal, `NO_COLOR` is set, or `TERM` is
# `dumb`; otherwise 16, 256, or 16777216 from `TERM` and `COLORTERM`.
export type TerminalCapabilities:
    # True when standard input is a terminal.
    input_is_terminal: Bool
    # True when standard output is a terminal.
    output_is_terminal: Bool
    # True when standard error is a terminal.
    error_is_terminal: Bool
    # True when `raw_mode` can succeed on this host and the streams are terminals.
    raw_mode: Bool
    # True when raw terminals deliver `Resize` events.
    resize_events: Bool
    # Supported color count, or 0 when color output should be avoided.
    colors: Int

# One decoded terminal input event. `Text` carries printable characters typed
# together. `Key` names a non-printing or modified key: `enter`, `tab`,
# `backspace`, `escape`, `space`, `up`, `down`, `left`, `right`, `home`, `end`,
# `insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with
# `ctrl` or `alt` set. `Resize` carries the new size.
export type TerminalEvent:
    # Printable characters typed together.
    case Text(
        # The typed characters in order, as valid UTF-8 text.
        text: String
    )
    # A named or modified key press.
    case Key(
        # The key name, such as `enter`, `up`, or a lowercase letter.
        name: String,
        # True when Control was held.
        ctrl: Bool,
        # True when Alt was held.
        alt: Bool,
        # True when Shift was held for a named key.
        shift: Bool
    )
    # The terminal window changed size.
    case Resize(
        # The new width in columns.
        columns: Int,
        # The new height in rows.
        rows: Int
    )

# The part of the screen cleared by `RawTerminal.erase`.
export type EraseRegion:
    # Every cell of the screen; the cursor does not move.
    case Screen
    # The whole cursor line.
    case Line
    # From the cursor to the end of the line.
    case LineEnd
    # From the start of the line to the cursor.
    case LineStart

# Queries the terminal and enters raw input mode.
interface Terminal:
    # Reports terminal availability and color support without changing terminal state.
    fn capabilities() TerminalCapabilities
    # Returns the terminal size, or `NotTerminal` when output is redirected.
    fn size() TerminalSize!
    # Acquires raw input with an optional alternate screen; returns `Busy` while another raw terminal is open and `NotTerminal` when streams are redirected.
    fn raw_mode(alternate_screen: Bool) RawTerminal!

# The runtime handle behind a `RawTerminal`.
export extern type NativeRawTerminal

# Raw terminal input and cursor control. Closing it, or leaving the
# scope that acquired it by return, error, fault, or cancellation, restores the
# original terminal settings, shows the cursor, and leaves the alternate screen.
# In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
export type RawTerminal:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeRawTerminal

impl Closeable for RawTerminal:
    # Restores the terminal; closing again does nothing.
    var fn close() Unit!:
        msstd_terminal_raw_terminal_close(self.native)
        return ok(unit)

impl RawTerminal:
    # Waits for the next event; none means the timeout elapsed. Waits honor cancellation and concurrent callers are serialized.
    fn next_event(timeout: Duration?) TerminalEvent?!:
        let ready = try msstd_terminal_raw_terminal_next_event(self.native, timeout)
        if ready.is_none(): return ok(none)

        let kind = msstd_terminal_event_kind()
        if kind == 0: return ok(TerminalEvent.Text(msstd_terminal_event_text()))
        if kind == 1: return ok(
            TerminalEvent.Key(
                msstd_terminal_event_text(), msstd_terminal_event_ctrl(),
                msstd_terminal_event_alt(), msstd_terminal_event_shift()
            )
        )

        return ok(
            TerminalEvent.Resize(
                msstd_terminal_event_columns(), msstd_terminal_event_rows()
            )
        )

    # Returns the current terminal size, or `Closed` after close.
    fn size() TerminalSize!:
        try msstd_terminal_raw_terminal_size_status(self.native)
        return ok(
            TerminalSize(
                columns: msstd_terminal_raw_terminal_size_columns(
                    self.native
                ),
                rows: msstd_terminal_raw_terminal_size_rows(self.native)
            )
        )

    # Moves the cursor to a zero-based row and column; negative or very large values return `InvalidInput`.
    fn move_cursor(row: Int, column: Int) Unit!:
        return msstd_terminal_raw_terminal_move_cursor(self.native, row, column)

    # Shows or hides the cursor until the terminal is restored on close.
    fn show_cursor(visible: Bool) Unit!:
        return msstd_terminal_raw_terminal_show_cursor(self.native, visible)

    # Erases the selected screen region without moving the cursor.
    fn erase(region: EraseRegion) Unit!:
        match region:
            Screen: return msstd_terminal_raw_terminal_erase(self.native, 0)
            Line: return msstd_terminal_raw_terminal_erase(self.native, 1)
            LineEnd: return msstd_terminal_raw_terminal_erase(self.native, 2)
            LineStart: return msstd_terminal_raw_terminal_erase(self.native, 3)

# Returns terminal operations for the current process.
fn host_terminal() Terminal:
    return msstd_io_terminal()

# Reports terminal availability and color support without changing terminal state.
export fn terminal_capabilities() TerminalCapabilities:
    return host_terminal().capabilities()

# Returns the terminal size, or `NotTerminal` when output is redirected.
export fn terminal_size() TerminalSize!:
    return host_terminal().size()

# Acquires raw input with an optional alternate screen; returns `Busy` while another raw terminal is open and `NotTerminal` when streams are redirected.
export fn raw_mode(alternate_screen: Bool) RawTerminal!:
    return host_terminal().raw_mode(alternate_screen)

# Opens path for read-only access; native missing, denied, and other open failures become Unavailable.
export fn open_read(path: String) File!:
    return host_files().open(path)
