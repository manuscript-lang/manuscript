+++
title = "terminal"
+++

# @std/terminal.ms

Import each required symbol with `import Name from "@std/terminal.ms"`.

## EraseRegion {data-api-kind="Alternative"}

The part of the screen cleared by `RawTerminal.erase`.

```manuscript
type EraseRegion:
    case Screen
    case Line
    case LineEnd
    case LineStart
```

### EraseRegion.Line

The whole cursor line.

```manuscript
case Line
```

### EraseRegion.LineEnd

From the cursor to the end of the line.

```manuscript
case LineEnd
```

### EraseRegion.LineStart

From the start of the line to the cursor.

```manuscript
case LineStart
```

### EraseRegion.Screen

Every cell of the screen; the cursor does not move.

```manuscript
case Screen
```

## RawTerminal {data-api-kind="Interface"}

Raw terminal input and cursor control. Closing it, or leaving the `with`
scope that acquired it by return, error, fault, or cancellation, restores the
original terminal settings, shows the cursor, and leaves the alternate screen.
In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.

```manuscript
interface RawTerminal:
    fn close() -> Unit
    fn next_event(timeout: Optional[Duration] = none) -> Result[Optional[TerminalEvent], TerminalError]
    fn size() -> Result[TerminalSize, TerminalError]
    fn move_cursor(row: Int, column: Int) -> Result[Unit, TerminalError]
    fn show_cursor(visible: Bool) -> Result[Unit, TerminalError]
    fn erase(region: EraseRegion) -> Result[Unit, TerminalError]
```

### RawTerminal.close

Restores the terminal; closing again does nothing.

```manuscript
fn close() -> Unit
```

### RawTerminal.erase

Erases the selected screen region without moving the cursor.

```manuscript
fn erase(region: EraseRegion) -> Result[Unit, TerminalError]
```

### RawTerminal.move_cursor

Moves the cursor to a zero-based row and column; negative or very large values return `InvalidInput`.

```manuscript
fn move_cursor(row: Int, column: Int) -> Result[Unit, TerminalError]
```

### RawTerminal.next_event

Waits for the next event; none means the timeout elapsed. Waits honor cancellation and concurrent callers are serialized.

```manuscript
fn next_event(timeout: Optional[Duration] = none) -> Result[Optional[TerminalEvent], TerminalError]
```

### RawTerminal.show_cursor

Shows or hides the cursor until the terminal is restored on close.

```manuscript
fn show_cursor(visible: Bool) -> Result[Unit, TerminalError]
```

### RawTerminal.size

Returns the current terminal size, or `Closed` after close.

```manuscript
fn size() -> Result[TerminalSize, TerminalError]
```

## Terminal {data-api-kind="Interface"}

Queries the terminal and enters raw input mode.

```manuscript
interface Terminal:
    fn capabilities() -> TerminalCapabilities
    fn size() -> Result[TerminalSize, TerminalError]
    fn raw_mode(alternate_screen: Bool) -> Result[RawTerminal, TerminalError]
```

### Terminal.capabilities

Reports terminal availability and color support without changing terminal state.

```manuscript
fn capabilities() -> TerminalCapabilities
```

### Terminal.raw_mode

Acquires raw input with an optional alternate screen; returns `Busy` while another raw terminal is open and `NotTerminal` when streams are redirected.

```manuscript
fn raw_mode(alternate_screen: Bool) -> Result[RawTerminal, TerminalError]
```

### Terminal.size

Returns the terminal size, or `NotTerminal` when output is redirected.

```manuscript
fn size() -> Result[TerminalSize, TerminalError]
```

## TerminalCapabilities {data-api-kind="Record"}

What the current process can do with its standard streams as a terminal.
`colors` is 0 when output is not a terminal, `NO_COLOR` is set, or `TERM` is
`dumb`; otherwise 16, 256, or 16777216 from `TERM` and `COLORTERM`.

```manuscript
type TerminalCapabilities:
    input_is_terminal: Bool
    output_is_terminal: Bool
    error_is_terminal: Bool
    raw_mode: Bool
    resize_events: Bool
    colors: Int
```

### TerminalCapabilities.colors

Supported color count, or 0 when color output should be avoided.

```manuscript
colors: Int
```

### TerminalCapabilities.error_is_terminal

True when standard error is a terminal.

```manuscript
error_is_terminal: Bool
```

### TerminalCapabilities.input_is_terminal

True when standard input is a terminal.

```manuscript
input_is_terminal: Bool
```

### TerminalCapabilities.output_is_terminal

True when standard output is a terminal.

```manuscript
output_is_terminal: Bool
```

### TerminalCapabilities.raw_mode

True when `raw_mode` can succeed on this host and the streams are terminals.

```manuscript
raw_mode: Bool
```

### TerminalCapabilities.resize_events

True when raw terminals deliver `Resize` events.

```manuscript
resize_events: Bool
```

## TerminalError {data-api-kind="Alternative"}

Errors returned by terminal queries and raw-mode operations.

```manuscript
type TerminalError:
    case InvalidInput
    case NotTerminal
    case Unsupported
    case Busy
    case Closed
    case Failed(message: String)
```

```manuscript
impl Error for TerminalError:
    fn message() -> String:
```

### TerminalError.Busy

Another raw terminal already holds the terminal.

```manuscript
case Busy
```

### TerminalError.Closed

The raw terminal was already closed.

```manuscript
case Closed
```

### TerminalError.Failed

The host call failed.

```manuscript
case Failed(message: String)
```

### TerminalError.InvalidInput

An argument is outside its valid range.

```manuscript
case InvalidInput
```

### TerminalError.NotTerminal

The required standard stream is redirected rather than a terminal.

```manuscript
case NotTerminal
```

### TerminalError.Unsupported

This host or platform has no terminal support for the operation.

```manuscript
case Unsupported
```

### TerminalError.Failed.message

The host diagnostic text reported by the failed call.

```manuscript
message: String
```

### TerminalError.Error.message

Returns a fixed diagnostic, or the host message for `Failed`.

```manuscript
fn message() -> String:
```

## TerminalEvent {data-api-kind="Alternative"}

One decoded terminal input event. `Text` carries printable characters typed
together. `Key` names a non-printing or modified key: `enter`, `tab`,
`backspace`, `escape`, `space`, `up`, `down`, `left`, `right`, `home`, `end`,
`insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with
`ctrl` or `alt` set. `Resize` carries the new size.

```manuscript
type TerminalEvent:
    case Text(text: String)
    case Key(name: String, ctrl: Bool, alt: Bool, shift: Bool)
    case Resize(columns: Int, rows: Int)
```

### TerminalEvent.Key

A named or modified key press.

```manuscript
case Key(name: String, ctrl: Bool, alt: Bool, shift: Bool)
```

### TerminalEvent.Resize

The terminal window changed size.

```manuscript
case Resize(columns: Int, rows: Int)
```

### TerminalEvent.Text

Printable characters typed together.

```manuscript
case Text(text: String)
```

### TerminalEvent.Key.alt

True when Alt was held.

```manuscript
alt: Bool
```

### TerminalEvent.Key.ctrl

True when Control was held.

```manuscript
ctrl: Bool
```

### TerminalEvent.Key.name

The key name, such as `enter`, `up`, or a lowercase letter.

```manuscript
name: String
```

### TerminalEvent.Key.shift

True when Shift was held for a named key.

```manuscript
shift: Bool
```

### TerminalEvent.Resize.columns

The new width in columns.

```manuscript
columns: Int
```

### TerminalEvent.Resize.rows

The new height in rows.

```manuscript
rows: Int
```

### TerminalEvent.Text.text

The typed characters in order, as valid UTF-8 text.

```manuscript
text: String
```

## TerminalSize {data-api-kind="Record"}

Character columns and rows of a terminal window.

```manuscript
type TerminalSize:
    columns: Int
    rows: Int
```

### TerminalSize.columns

Width in character columns.

```manuscript
columns: Int
```

### TerminalSize.rows

Height in character rows.

```manuscript
rows: Int
```

## terminal {data-api-kind="Function"}

Returns terminal operations for the current process.

```manuscript
fn terminal() -> Terminal:
```

