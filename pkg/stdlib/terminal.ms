import Duration from "@std/time.ms"

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
# documentation documentation/standard-library/terminal.md
# +++
# title = "Terminal input and cursor control"
# weight = 19
# +++
#
# # Terminal input and cursor control
#
# API reference: [terminal](reference/terminal.md).
#
# Use `@std/terminal.ms` for programs that react to single key presses, redraw the screen, or follow window resizes. It supplies portable primitives, not a widget framework: your program decides what to draw. Plain output still goes through [`stdout`](streams.md).
#
# ## Check what the terminal can do
#
# `terminal()` returns the host terminal service. `capabilities()` reports whether stdin, stdout, and stderr are terminals, whether raw mode and resize events are available, and how many `colors` output supports (0, 16, 256, or 16777216, from `NO_COLOR`, `TERM`, and `COLORTERM`). `size()` returns the `columns` and `rows` of the window. Redirected streams are not terminals: `size()` returns `NotTerminal`, and `capabilities()` says so instead of failing.
#
# ## Read keys in raw mode
#
# `raw_mode(alternate_screen)` acquires a `RawTerminal` with `with`. It requires stdin and stdout to be terminals; otherwise it returns `NotTerminal`, and hosts without terminal support return `Unsupported`. Only one `RawTerminal` can be open at a time (`Busy`).
#
# This program needs an interactive terminal, so the guide shows it without running it. Ctrl-C quits:
#
# ```text
# import {terminal, TerminalError, TerminalEvent, EraseRegion} from "@std/terminal.ms"
# import Result from "@std/result.ms"
# import panic from "@std/faults.ms"
#
# fn is_quit(event: TerminalEvent) -> Bool:
#     match event:
#         TerminalEvent.Key(name, ctrl, _, _):
#             return ctrl and name == "c"
#         _:
#             return false
#
# fn run() -> Result[Unit, TerminalError]:
#     with screen = try terminal().raw_mode(alternate_screen: true):
#         screen.show_cursor(visible: false)
#         screen.erase(region: EraseRegion.Screen)
#         screen.move_cursor(row: 0, column: 0)
#         while true:
#             let event = try screen.next_event()
#             match event:
#                 some(found):
#                     if is_quit(found): return ok(value: unit)
#                 none:
#                     screen.erase(region: EraseRegion.Line)
#     return ok(value: unit)
#
# export fn main() -> Int:
#     match run():
#         ok(_):
#             return 0
#         error(cause):
#             return panic(message: cause.message())
# ```
#
# The drawing calls return `Result`; this sketch ignores their errors to stay short, while `raw_mode` and `next_event` propagate with `try`.
#
# Leaving the `with` scope by return, error, fault, or cancellation restores the original terminal settings, shows the cursor, and leaves the alternate screen. The CLI also restores an unclosed terminal at process exit. Closing is idempotent, and operations after close return `Closed`.
#
# Raw mode turns off line editing, echo, and signal keys. Ctrl-C therefore arrives as a `c` key with `ctrl` set and does not interrupt the program; handle it yourself. Output post-processing stays on, so `\n` still moves to the next line start. Do not read the `stdin` stream while a `RawTerminal` is open; both would consume the same bytes.
#
# ## Events
#
# `next_event(timeout)` returns the next event, or `none` when the optional `timeout` elapses first (a zero timeout polls). Cancelling the caller interrupts the wait. Concurrent callers take turns.
#
# | Event | Meaning |
# | --- | --- |
# | `Text(text)` | Printable characters typed together. UTF-8 split across reads is rejoined; invalid bytes become U+FFFD. |
# | `Key(name, ctrl, alt, shift)` | A non-printing or modified key: `enter`, `tab`, `backspace`, `escape`, `space`, arrows, `home`, `end`, `insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with `ctrl` or `alt`. |
# | `Resize(columns, rows)` | The window changed size. Several quick changes may coalesce into one event. |
#
# A lone escape byte becomes the `escape` key after a short pause with no continuation, so escape sequences split across reads decode correctly. Unrecognized escape sequences are dropped rather than delivered as text. Resize events use `SIGWINCH` on Unix and size polling on Windows, and are unavailable (`resize_events` is false) on hosts without it.
#
# ## Cursor and screen operations
#
# `move_cursor(row, column)` uses zero-based positions. `show_cursor(visible)` hides or shows the cursor. `erase(region)` clears the `Screen`, the whole `Line`, or the part of the line before (`LineStart`) or after (`LineEnd`) the cursor. Each returns `Closed` after the terminal is closed.
#
# ## Current limits
#
# Linux, macOS, and Windows support raw mode, size, and resize events. On Windows the console must support virtual terminal sequences (Windows 10 1809 or later, Windows Terminal, or conhost); older consoles report `Unsupported`. Other hosts report `Unsupported`. Paste, mouse, and focus events, text styles, and key release or kitty-protocol keys are not part of this API yet.
# end-documentation
