import NativeRawTerminal from "@std/cli/terminal.ms"

export extern fn msstd_io_redirect_null(which: Int) Unit!

export extern fn msstd_io_stdout_status(flush: Bool) Unit!

export extern fn msstd_terminal_raw_mode() NativeRawTerminal!

export extern fn msstd_terminal_capabilities_input_is_terminal() Bool

export extern fn msstd_terminal_capabilities_output_is_terminal() Bool

export extern fn msstd_terminal_capabilities_error_is_terminal() Bool

export extern fn msstd_terminal_capabilities_raw_mode() Bool

export extern fn msstd_terminal_capabilities_resize_events() Bool

export extern fn msstd_terminal_capabilities_colors() Int

export extern fn msstd_terminal_size_status() Unit!

export extern fn msstd_terminal_size_columns() Int

export extern fn msstd_terminal_size_rows() Int

export extern fn msstd_terminal_raw_terminal_close(handle: NativeRawTerminal) Unit

export extern fn msstd_terminal_raw_terminal_share(
	handle: NativeRawTerminal
) NativeRawTerminal

export extern fn msstd_terminal_raw_terminal_read(
	handle: NativeRawTerminal,
	quick: Bool,
) Unit?!

export extern fn msstd_terminal_input_text() String

export extern fn msstd_terminal_raw_terminal_set_restore(
	handle: NativeRawTerminal,
	text: String,
) Unit

export extern fn msstd_terminal_raw_terminal_size_status(
	handle: NativeRawTerminal
) Unit!

export extern fn msstd_terminal_raw_terminal_size_columns(handle: NativeRawTerminal) Int

export extern fn msstd_terminal_raw_terminal_size_rows(handle: NativeRawTerminal) Int

export extern fn msstd_terminal_raw_terminal_write(
	handle: NativeRawTerminal,
	text: String,
) Unit!
