+++
title = "Terminal input and cursor control"
weight = 19
+++

# Terminal input and cursor control

API reference: [terminal](reference/terminal.md).

Use `@std/terminal.ms` for programs that react to single key presses, redraw the screen, or follow window resizes. It supplies portable primitives, not a widget framework: your program decides what to draw. Plain output still goes through [`stdout`](streams.md).

## Check what the terminal can do

`terminal()` returns the host terminal service. `capabilities()` reports whether stdin, stdout, and stderr are terminals, whether raw mode and resize events are available, and how many `colors` output supports (0, 16, 256, or 16777216, from `NO_COLOR`, `TERM`, and `COLORTERM`). `size()` returns the `columns` and `rows` of the window. Redirected streams are not terminals: `size()` returns `NotTerminal`, and `capabilities()` says so instead of failing.

## Read keys in raw mode

`raw_mode(alternate_screen)` acquires a `RawTerminal` with `with`. It requires stdin and stdout to be terminals; otherwise it returns `NotTerminal`, and hosts without terminal support return `Unsupported`. Only one `RawTerminal` can be open at a time (`Busy`).

This program needs an interactive terminal, so the guide shows it without running it. Ctrl-C quits:

```text
import {terminal, TerminalError, TerminalEvent, EraseRegion} from "@std/terminal.ms"
import Result from "@std/result.ms"
import panic from "@std/faults.ms"

fn is_quit(event: TerminalEvent) -> Bool:
    match event:
        TerminalEvent.Key(name, ctrl, _, _):
            return ctrl and name == "c"
        _:
            return false

fn run() -> Result[Unit, TerminalError]:
    with screen = try terminal().raw_mode(alternate_screen: true):
        screen.show_cursor(visible: false)
        screen.erase(region: EraseRegion.Screen)
        screen.move_cursor(row: 0, column: 0)
        while true:
            let event = try screen.next_event()
            match event:
                some(found):
                    if is_quit(found): return ok(value: unit)
                none:
                    screen.erase(region: EraseRegion.Line)
    return ok(value: unit)

export fn main() -> Int:
    match run():
        ok(_):
            return 0
        error(cause):
            return panic(message: cause.message())
```

The drawing calls return `Result`; this sketch ignores their errors to stay short, while `raw_mode` and `next_event` propagate with `try`.

Leaving the `with` scope by return, error, fault, or cancellation restores the original terminal settings, shows the cursor, and leaves the alternate screen. The CLI also restores an unclosed terminal at process exit. Closing is idempotent, and operations after close return `Closed`.

Raw mode turns off line editing, echo, and signal keys. Ctrl-C therefore arrives as a `c` key with `ctrl` set and does not interrupt the program; handle it yourself. Output post-processing stays on, so `\n` still moves to the next line start. Do not read the `stdin` stream while a `RawTerminal` is open; both would consume the same bytes.

## Events

`next_event(timeout)` returns the next event, or `none` when the optional `timeout` elapses first (a zero timeout polls). Cancelling the caller interrupts the wait. Concurrent callers take turns.

| Event | Meaning |
| --- | --- |
| `Text(text)` | Printable characters typed together. UTF-8 split across reads is rejoined; invalid bytes become U+FFFD. |
| `Key(name, ctrl, alt, shift)` | A non-printing or modified key: `enter`, `tab`, `backspace`, `escape`, `space`, arrows, `home`, `end`, `insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with `ctrl` or `alt`. |
| `Resize(columns, rows)` | The window changed size. Several quick changes may coalesce into one event. |

A lone escape byte becomes the `escape` key after a short pause with no continuation, so escape sequences split across reads decode correctly. Unrecognized escape sequences are dropped rather than delivered as text. Resize events use `SIGWINCH` on Unix and size polling on Windows, and are unavailable (`resize_events` is false) on hosts without it.

## Cursor and screen operations

`move_cursor(row, column)` uses zero-based positions. `show_cursor(visible)` hides or shows the cursor. `erase(region)` clears the `Screen`, the whole `Line`, or the part of the line before (`LineStart`) or after (`LineEnd`) the cursor. Each returns `Closed` after the terminal is closed.

## Current limits

Linux, macOS, and Windows support raw mode, size, and resize events. On Windows the console must support virtual terminal sequences (Windows 10 1809 or later, Windows Terminal, or conhost); older consoles report `Unsupported`. Other hosts report `Unsupported`. Paste, mouse, and focus events, text styles, and key release or kitty-protocol keys are not part of this API yet.
