# Canonical standard-library declarations. Implementations are native.

import Duration from "@std/time.ms"
import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Result from "@std/result.ms"

# Errors returned by terminal queries and raw-mode operations.
export type TerminalError:
    case InvalidInput
    case NotTerminal
    case Unsupported
    case Busy
    case Closed
    case Failed(message: String)

# Character columns and rows of a terminal window.
export type TerminalSize:
    columns: Int
    rows: Int

# What the current process can do with its standard streams as a terminal.
# `colors` is 0 when output is not a terminal, `NO_COLOR` is set, or `TERM` is
# `dumb`; otherwise 16, 256, or 16777216 from `TERM` and `COLORTERM`.
export type TerminalCapabilities:
    input_is_terminal: Bool
    output_is_terminal: Bool
    error_is_terminal: Bool
    raw_mode: Bool
    resize_events: Bool
    colors: Int

# One decoded terminal input event. `Text` carries printable characters typed
# together. `Key` names a non-printing or modified key: `enter`, `tab`,
# `backspace`, `escape`, `space`, `up`, `down`, `left`, `right`, `home`, `end`,
# `insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with
# `ctrl` or `alt` set. `Resize` carries the new size.
export type TerminalEvent:
    case Text(text: String)
    case Key(name: String, ctrl: Bool, alt: Bool, shift: Bool)
    case Resize(columns: Int, rows: Int)

# The part of the screen cleared by `RawTerminal.erase`.
export type EraseRegion:
    case Screen
    case Line
    case LineEnd
    case LineStart

# Queries the terminal and enters raw input mode.
export interface Terminal:
    fn capabilities() -> TerminalCapabilities
    fn size() -> Result[TerminalSize, TerminalError]
    fn raw_mode(alternate_screen: Bool) -> Result[RawTerminal, TerminalError]

# Raw terminal input and cursor control. Closing it, or leaving the `with`
# scope that acquired it by return, error, fault, or cancellation, restores the
# original terminal settings, shows the cursor, and leaves the alternate screen.
# In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
export interface RawTerminal:
    fn close() -> Unit
    fn next_event(timeout: Optional[Duration] = none) -> Result[Optional[TerminalEvent], TerminalError]
    fn size() -> Result[TerminalSize, TerminalError]
    fn move_cursor(row: Int, column: Int) -> Result[Unit, TerminalError]
    fn show_cursor(visible: Bool) -> Result[Unit, TerminalError]
    fn erase(region: EraseRegion) -> Result[Unit, TerminalError]

impl Error for TerminalError:
    fn message() -> String:

# Returns terminal operations for the current process.
export fn terminal() -> Terminal:
