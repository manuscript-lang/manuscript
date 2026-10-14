+++
title = "terminal"
+++

# @std/terminal.ms

Import each required symbol with `import Name from "@std/terminal.ms"`.

## EraseRegion {data-api-kind="Alternative"}

```manuscript
type EraseRegion:
    case Screen
    case Line
    case LineEnd
    case LineStart
```

## RawTerminal {data-api-kind="Interface"}

```manuscript
interface RawTerminal:
    fn close() -> Unit
    fn next_event(timeout: Optional[Duration] = none) -> Result[Optional[TerminalEvent], TerminalError]
    fn size() -> Result[TerminalSize, TerminalError]
    fn move_cursor(row: Int, column: Int) -> Result[Unit, TerminalError]
    fn show_cursor(visible: Bool) -> Result[Unit, TerminalError]
    fn erase(region: EraseRegion) -> Result[Unit, TerminalError]
```

## Terminal {data-api-kind="Interface"}

```manuscript
interface Terminal:
    fn capabilities() -> TerminalCapabilities
    fn size() -> Result[TerminalSize, TerminalError]
    fn raw_mode(alternate_screen: Bool) -> Result[RawTerminal, TerminalError]
```

## TerminalCapabilities {data-api-kind="Record"}

```manuscript
type TerminalCapabilities:
    input_is_terminal: Bool
    output_is_terminal: Bool
    error_is_terminal: Bool
    raw_mode: Bool
    resize_events: Bool
    colors: Int
```

## TerminalError {data-api-kind="Alternative"}

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

## TerminalEvent {data-api-kind="Alternative"}

```manuscript
type TerminalEvent:
    case Text(text: String)
    case Key(name: String, ctrl: Bool, alt: Bool, shift: Bool)
    case Resize(columns: Int, rows: Int)
```

## TerminalSize {data-api-kind="Record"}

```manuscript
type TerminalSize:
    columns: Int
    rows: Int
```

## terminal {data-api-kind="Function"}

```manuscript
fn terminal() -> Terminal:
```

