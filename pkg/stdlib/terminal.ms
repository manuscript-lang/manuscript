# Canonical standard-library declarations. Implementations are native.

import Duration from "@std/time.ms"
import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Result from "@std/result.ms"

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
    fn capabilities() -> TerminalCapabilities
    # Returns the terminal size, or `NotTerminal` when output is redirected.
    fn size() -> Result[TerminalSize, TerminalError]
    # Acquires raw input with an optional alternate screen; returns `Busy` while another raw terminal is open and `NotTerminal` when streams are redirected.
    fn raw_mode(alternate_screen: Bool) -> Result[RawTerminal, TerminalError]

# Raw terminal input and cursor control. Closing it, or leaving the `with`
# scope that acquired it by return, error, fault, or cancellation, restores the
# original terminal settings, shows the cursor, and leaves the alternate screen.
# In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
export interface RawTerminal:
    # Restores the terminal; closing again does nothing.
    fn close() -> Unit
    # Waits for the next event; none means the timeout elapsed. Waits honor cancellation and concurrent callers are serialized.
    fn next_event(
        timeout: Optional[Duration] = none
    ) -> Result[Optional[TerminalEvent], TerminalError]
    # Returns the current terminal size, or `Closed` after close.
    fn size() -> Result[TerminalSize, TerminalError]
    # Moves the cursor to a zero-based row and column; negative or very large values return `InvalidInput`.
    fn move_cursor(row: Int, column: Int) -> Result[Unit, TerminalError]
    # Shows or hides the cursor until the terminal is restored on close.
    fn show_cursor(visible: Bool) -> Result[Unit, TerminalError]
    # Erases the selected screen region without moving the cursor.
    fn erase(region: EraseRegion) -> Result[Unit, TerminalError]

impl Error for TerminalError:
    # Returns a fixed diagnostic, or the host message for `Failed`.
    fn message() -> String:

# Returns terminal operations for the current process.
export fn terminal() -> Terminal:
