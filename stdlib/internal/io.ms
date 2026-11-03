import (
    NativeRawTerminal,
    Terminal
) from "@std/io/io.ms"
import Duration from "@std/os/time.ms"

export extern fn msstd_terminal_event_kind() Int

export extern fn msstd_terminal_event_text() String

export extern fn msstd_terminal_event_ctrl() Bool

export extern fn msstd_terminal_event_alt() Bool

export extern fn msstd_terminal_event_shift() Bool

export extern fn msstd_terminal_event_columns() Int

export extern fn msstd_terminal_event_rows() Int

export extern fn msstd_io_redirect_null(which: Int) Unit!

export extern fn msstd_io_terminal() Terminal

export extern fn msstd_terminal_raw_terminal_close(handle: NativeRawTerminal) Unit

export extern fn msstd_terminal_raw_terminal_share(handle: NativeRawTerminal) NativeRawTerminal

export extern fn msstd_terminal_raw_terminal_next_event(
    handle: NativeRawTerminal,
    timeout: Duration?
) Unit?!

export extern fn msstd_terminal_raw_terminal_size_status(
    handle: NativeRawTerminal
) Unit!

export extern fn msstd_terminal_raw_terminal_size_columns(handle: NativeRawTerminal) Int

export extern fn msstd_terminal_raw_terminal_size_rows(handle: NativeRawTerminal) Int

export extern fn msstd_terminal_raw_terminal_move_cursor(
    handle: NativeRawTerminal,
    row: Int,
    column: Int
) Unit!

export extern fn msstd_terminal_raw_terminal_show_cursor(
    handle: NativeRawTerminal,
    visible: Bool
) Unit!

export extern fn msstd_terminal_raw_terminal_erase(
    handle: NativeRawTerminal,
    region: Int
) Unit!
