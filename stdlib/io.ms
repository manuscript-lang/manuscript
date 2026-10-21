import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"

# A file-like byte stream that returns `none` at end of input.
export interface File:
    # Releases the file resource; retained aliases do not extend its open lifetime.
    fn close() Unit
    # Returns a byte chunk or none at EOF; max_bytes is a positive chunk size, not a total budget.
    # Omission/none uses the native 64 KiB chunk; source implementations define their own buffering.
    fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]

# Opens read-only file resources using the current host's default filesystem.
# Native open failures (including missing paths and permission denial) become IoError.Unavailable.
export interface Files:
    # Opens path for read-only access; native missing, denied, and other open failures become Unavailable.
    fn open(path: String) Result[File, IoError]

# Errors returned while reading, writing, or closing an I/O resource.
export type IoError:
    # The stream or shared native handle was closed before the operation completed.
    case Closed
    # An explicit chunk size, byte limit, or handle mode is invalid for this operation.
    case InvalidInput
    # The native service could not open or provide the requested stream.
    case Unavailable
    # Read bytes are invalid for the requested decoding, such as malformed UTF-8 text.
    case InvalidData
    # A supplied byte budget was exceeded; already consumed input may not be recoverable.
    case LimitExceeded
    # A native or adapter failure outside the more specific I/O cases.
    case Failed(
        # Original diagnostic text; message() returns it unchanged rather than redacting it.
        message: String
    )

# A readable byte stream. Each read returns a chunk or `none` at end of stream.
export interface ReadStream:
    # Releases this implementation's read resource; ownership of underlying handles is implementation-defined.
    fn close() Unit
    # Returns a chunk or none at EOF; a final nonempty chunk can precede EOF.
    # A supplied positive max_bytes requests a chunk size; native omission/none uses 64 KiB.
    fn read(max_bytes: Optional[Int] = none) Result[Optional[Bytes], IoError]

# A writable byte stream. Successful write accepts all bytes; failure may leave an external prefix.
# Buffering/flush depends on the implementation: native stderr is unbuffered and native stdout is buffered when not a terminal (flush drains it),
# while FileHandle.writer().flush synchronizes the file. Success does not acknowledge peer processing.
export interface WriteStream:
    # Releases this implementation's write resource; close does not imply a successful flush.
    fn close() Unit
    # Completes implementation-specific buffering or synchronization; native stdout drains its buffer and stderr has none.
    # File-handle writers synchronize the file, and failures retain IoError identity.
    fn flush() Result[Unit, IoError]
    # Accepts the complete input on success; a source implementation may buffer until flush.
    fn write(data: String) Result[Unit, IoError]
    # Accepts the complete bytes on success, with the buffering rules of write.
    fn write_bytes(data: Bytes) Result[Unit, IoError]

# Copies bytes until end of input or the supplied byte limit; returns bytes copied.
export fn copy(
    input: ReadStream,
    output: WriteStream,
    max_bytes: Optional[Int] = none
) Result[Int, IoError]:

# Reads a stream completely into memory. Supply a limit for untrusted streams.
export fn read_all(
    input: ReadStream,
    max_bytes: Optional[Int] = none
) Result[Bytes, IoError]:

# Reads one line, omitting its line ending; returns `none` at end of stream.
export fn read_line(
    input: ReadStream,
    max_bytes: Optional[Int] = none
) Result[Optional[String], IoError]:

impl Error for IoError:
    # Returns original Failed text, or an I/O-prefixed diagnostic for the other cases.
    fn message() String:

# Returns the process standard-input stream.
export fn stdin() ReadStream:

# Returns the process standard-output stream.
export fn stdout() WriteStream:

# Returns the process standard-error stream.
export fn stderr() WriteStream:

# Returns file operations for the current host.
export fn files() Files:

# Errors returned by terminal queries and raw-mode operations.
export type TerminalError:
    # An argument is outside its valid range.
    case InvalidInput
    # The required standard stream is redirected rather than a terminal.
    case NotTerminal
    # This host or platform has no terminal support for the operation.
    case Unsupported
    # Another raw terminal already holds the terminal.
    case Busy
    # The raw terminal was already closed.
    case Closed
    # The host call failed.
    case Failed(
        # The host diagnostic text reported by the failed call.
        message: String
    )

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
export interface Terminal:
    # Reports terminal availability and color support without changing terminal state.
    fn capabilities() TerminalCapabilities
    # Returns the terminal size, or `NotTerminal` when output is redirected.
    fn size() Result[TerminalSize, TerminalError]
    # Acquires raw input with an optional alternate screen; returns `Busy` while another raw terminal is open and `NotTerminal` when streams are redirected.
    fn raw_mode(alternate_screen: Bool) Result[RawTerminal, TerminalError]

# Raw terminal input and cursor control. Closing it, or leaving the `with`
# scope that acquired it by return, error, fault, or cancellation, restores the
# original terminal settings, shows the cursor, and leaves the alternate screen.
# In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
export interface RawTerminal:
    # Restores the terminal; closing again does nothing.
    fn close() Unit
    # Waits for the next event; none means the timeout elapsed. Waits honor cancellation and concurrent callers are serialized.
    fn next_event(
        timeout: Optional[Duration] = none
    ) Result[Optional[TerminalEvent], TerminalError]
    # Returns the current terminal size, or `Closed` after close.
    fn size() Result[TerminalSize, TerminalError]
    # Moves the cursor to a zero-based row and column; negative or very large values return `InvalidInput`.
    fn move_cursor(row: Int, column: Int) Result[Unit, TerminalError]
    # Shows or hides the cursor until the terminal is restored on close.
    fn show_cursor(visible: Bool) Result[Unit, TerminalError]
    # Erases the selected screen region without moving the cursor.
    fn erase(region: EraseRegion) Result[Unit, TerminalError]

impl Error for TerminalError:
    # Returns a fixed diagnostic, or the host message for `Failed`.
    fn message() String:

# Returns terminal operations for the current process.
export fn terminal() Terminal:
