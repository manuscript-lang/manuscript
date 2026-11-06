/*
Terminal detection, size, and raw input with cursor control.

`terminal_capabilities` reports whether the standard streams are terminals and how many colors they support. `raw_mode` acquires a `RawTerminal` whose `events()` stream yields keys, text and resizes.
*/
import Closeable from "@std/core.ms"
import ReadStream, Source from "@std/io/io.ms"
import (
    msstd_terminal_raw_terminal_next_event,
    msstd_terminal_event_kind,
    msstd_terminal_event_text,
    msstd_terminal_event_ctrl,
    msstd_terminal_event_alt,
    msstd_terminal_event_shift,
    msstd_terminal_event_columns,
    msstd_terminal_event_rows,
    msstd_terminal_raw_terminal_close,
    msstd_terminal_raw_terminal_share,
    msstd_terminal_raw_terminal_size_status,
    msstd_terminal_raw_terminal_size_columns,
    msstd_terminal_raw_terminal_size_rows,
    msstd_terminal_raw_terminal_move_cursor,
    msstd_terminal_raw_terminal_show_cursor,
    msstd_terminal_raw_terminal_erase,
    msstd_terminal_capabilities_input_is_terminal,
    msstd_terminal_capabilities_output_is_terminal,
    msstd_terminal_capabilities_error_is_terminal,
    msstd_terminal_capabilities_raw_mode,
    msstd_terminal_capabilities_resize_events,
    msstd_terminal_capabilities_colors,
    msstd_terminal_size_status,
    msstd_terminal_size_columns,
    msstd_terminal_size_rows,
    msstd_terminal_raw_mode
) from "@std/internal/io.ms"

// Character columns and rows of a terminal window.
export type TerminalSize:
    // Width in character columns.
    columns: Int
    // Height in character rows.
    rows: Int

/*
What the current process can do with its standard streams as a terminal.
`colors` is 0 when output is not a terminal, `NO_COLOR` is set, or `TERM` is
`dumb`; otherwise 16, 256, or 16777216 from `TERM` and `COLORTERM`.
*/
export type TerminalCapabilities:
    // True when standard input is a terminal.
    input_is_terminal: Bool
    // True when standard output is a terminal.
    output_is_terminal: Bool
    // True when standard error is a terminal.
    error_is_terminal: Bool
    // True when `raw_mode` can succeed on this host and the streams are terminals.
    raw_mode: Bool
    // True when raw terminals deliver `Resize` events.
    resize_events: Bool
    // Supported color count, or 0 when color output should be avoided.
    colors: Int

/*
One decoded terminal input event. `Text` carries printable characters typed
together. `Key` names a non-printing or modified key: `enter`, `tab`,
`backspace`, `escape`, `space`, `up`, `down`, `left`, `right`, `home`, `end`,
`insert`, `delete`, `page_up`, `page_down`, `f1` to `f12`, or a letter with
`ctrl` or `alt` set. `Resize` carries the new size.
*/
export enum TerminalEvent:
    // Printable characters typed together.
    Text(
        // The typed characters in order, as valid UTF-8 text.
        text: String
    )
    // A named or modified key press.
    Key(
        // The key name, such as `enter`, `up`, or a lowercase letter.
        name: String,
        // True when Control was held.
        ctrl: Bool,
        // True when Alt was held.
        alt: Bool,
        // True when Shift was held for a named key.
        shift: Bool
    )
    // The terminal window changed size.
    Resize(
        // The new width in columns.
        columns: Int,
        // The new height in rows.
        rows: Int
    )

// The part of the screen cleared by `RawTerminal.erase`.
export enum EraseRegion:
    Screen  // Every cell of the screen; the cursor does not move.
    Line  // The whole cursor line.
    LineEnd  // From the cursor to the end of the line.
    LineStart  // From the start of the line to the cursor.

// Reads decoded events from a raw terminal's native handle.
type TerminalEvents:
    handle: RawHandle

impl Source[TerminalEvent] for TerminalEvents:
    var fn next() TerminalEvent?!:
        let ready = try msstd_terminal_raw_terminal_next_event(self.handle.native, none)
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

    var fn close() Unit!:
        return ok(unit)

// The runtime handle behind a `RawTerminal`.
export extern type NativeRawTerminal

/*
Raw terminal input and cursor control. Closing it, or leaving the
scope that acquired it by return, error, fault, or cancellation, restores the
original terminal settings, shows the cursor, and leaves the alternate screen.
In raw mode, Ctrl-C arrives as a `c` key with `ctrl` set instead of cancelling.
*/
export type RawTerminal:
    // The runtime handle; the event stream holds another on the same terminal.
    handle: RawHandle

// What the native `raw_mode` returns: the runtime handle itself.
export type RawHandle:
    // The runtime terminal handle.
    native: NativeRawTerminal

impl Closeable for RawTerminal:
    // Restores the terminal; closing again does nothing.
    var fn close() Unit!:
        msstd_terminal_raw_terminal_close(self.handle.native)
        return ok(unit)

impl RawTerminal:
    // Input events as a stream: keys, text and resizes, one per read. Waits honor cancellation and promise timeouts.
    // The stream ends with an error once the terminal is closed; closing the stream leaves the terminal open.
    fn events() ReadStream[TerminalEvent]:
        return ReadStream[TerminalEvent](
            TerminalEvents(
                RawHandle(
                    msstd_terminal_raw_terminal_share(
                        self.handle.native
                    )
                )
            )
        )

    // Returns the current terminal size, or `EBADF` after close.
    fn size() TerminalSize!:
        try msstd_terminal_raw_terminal_size_status(self.handle.native)
        return ok(
            TerminalSize(
                columns: msstd_terminal_raw_terminal_size_columns(
                    self.handle.native
                ),
                rows: msstd_terminal_raw_terminal_size_rows(
                    self.handle.native
                )
            )
        )

    // Moves the cursor to a zero-based row and column; negative or very large values return `EINVAL`.
    fn move_cursor(row: Int, column: Int) Unit!:
        return msstd_terminal_raw_terminal_move_cursor(self.handle.native, row, column)

    // Shows or hides the cursor until the terminal is restored on close.
    fn show_cursor(visible: Bool) Unit!:
        return msstd_terminal_raw_terminal_show_cursor(self.handle.native, visible)

    // Erases the selected screen region without moving the cursor.
    fn erase(region: EraseRegion) Unit!:
        match region:
            Screen: return msstd_terminal_raw_terminal_erase(self.handle.native, 0)
            Line: return msstd_terminal_raw_terminal_erase(self.handle.native, 1)
            LineEnd: return msstd_terminal_raw_terminal_erase(self.handle.native, 2)
            LineStart: return msstd_terminal_raw_terminal_erase(self.handle.native, 3)

// Reports terminal availability and color support without changing terminal state.
// ms: effect std.console.read
export fn terminal_capabilities() TerminalCapabilities:
    return TerminalCapabilities(
        input_is_terminal: msstd_terminal_capabilities_input_is_terminal(),
        output_is_terminal: msstd_terminal_capabilities_output_is_terminal(),
        error_is_terminal: msstd_terminal_capabilities_error_is_terminal(),
        raw_mode: msstd_terminal_capabilities_raw_mode(),
        resize_events: msstd_terminal_capabilities_resize_events(),
        colors: msstd_terminal_capabilities_colors()
    )

// Returns the terminal size, or `ENOTTY` when output is redirected.
// ms: effect std.console.read
export fn terminal_size() TerminalSize!:
    try msstd_terminal_size_status()
    return ok(
        TerminalSize(
            columns: msstd_terminal_size_columns(), rows: msstd_terminal_size_rows()
        )
    )

// Acquires raw input with an optional alternate screen; returns `EBUSY` while another raw terminal is open and `ENOTTY` when streams are redirected.
// ms: effect std.console.read
// ms: effect std.console.write
export fn raw_mode(alternate_screen: Bool) RawTerminal!:
    let native = try msstd_terminal_raw_mode(alternate_screen)
    return ok(RawTerminal(handle: RawHandle(native)))
