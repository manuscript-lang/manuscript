/* runtime/std/terminal.h: the raw terminal of @std/io. libuv's uv_tty does the terminal work on every platform: raw mode
 * and its restore, the window size, and writes that Windows consoles understand. Reading is one libuv loop per terminal
 * that runs on a pool thread for the length of one wait, so a task that waits for a key parks no scheduler thread
 * (terminal_read.c). Decoding keys and pastes from the text is Manuscript (stdlib/cli/terminal.ms).
 *
 * One raw terminal holds the host terminal at a time. Closing it (explicitly, by the last handle's drop, or at process
 * exit) writes the text the program registered (leaving the alternate screen and so on) and puts the saved settings
 * back. Natives return a status (MS_STATUS_*); a stop request ends a wait by cancelling the task. */
#ifndef MS_RUNTIME_STD_TERMINAL_H
#define MS_RUNTIME_STD_TERMINAL_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/string.h"

/* ms-sig: msstd_terminal_capabilities_input_is_terminal() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_input_is_terminal(void);
/* ms-sig: msstd_terminal_capabilities_output_is_terminal() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_output_is_terminal(void);
/* ms-sig: msstd_terminal_capabilities_error_is_terminal() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_error_is_terminal(void);
/* ms-sig: msstd_terminal_capabilities_raw_mode() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_raw_mode(void);
/* ms-sig: msstd_terminal_capabilities_resize_events() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_resize_events(void);
/* Colors that standard output supports: 0, 16, 256 or 16777216. */
/* ms-sig: msstd_terminal_capabilities_colors() -> i64 @domain=terminal */
int64_t msstd_terminal_capabilities_colors(void);

/* The size of the terminal behind standard output: not a terminal, or unsupported, or OK with columns and rows. */
/* ms-sig: msstd_terminal_size_status() -> u8 @domain=terminal */
uint8_t msstd_terminal_size_status(void);
/* ms-sig: msstd_terminal_size_columns() -> i64 @domain=terminal */
int64_t msstd_terminal_size_columns(void);
/* ms-sig: msstd_terminal_size_rows() -> i64 @domain=terminal */
int64_t msstd_terminal_size_rows(void);

/* Puts the terminal in raw mode: not a terminal, busy (one raw terminal at a time), or a handle. */
/* ms-sig: msstd_terminal_raw_mode(out: *mut *mut ObjCell<RawH>, err: ErrSlot) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_mode(MsObj **out, MsString *err);
/* Another handle on the same raw terminal; the last handle's drop closes it. */
/* ms-sig: msstd_terminal_raw_terminal_share(handle h: *const ObjCell<RawH>) -> *mut ObjCell<RawH> @domain=terminal @end */
MsObj *msstd_terminal_raw_terminal_share(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_close(handle h: *const ObjCell<RawH>) @domain=terminal */
void msstd_terminal_raw_terminal_close(const MsObj *handle);
/* The text written when the terminal closes. */
/* ms-sig: msstd_terminal_raw_terminal_set_restore(handle h: *const ObjCell<RawH>, text: *const StrVal) @domain=terminal */
void msstd_terminal_raw_terminal_set_restore(const MsObj *handle, const MsString *text);
/* ms-sig: msstd_terminal_raw_terminal_size_status(handle h: *const ObjCell<RawH>) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_terminal_size_status(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_size_columns(handle h: *const ObjCell<RawH>) -> i64 @domain=terminal */
int64_t msstd_terminal_raw_terminal_size_columns(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_size_rows(handle h: *const ObjCell<RawH>) -> i64 @domain=terminal */
int64_t msstd_terminal_raw_terminal_size_rows(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_write(handle h: *const ObjCell<RawH>, text: *const StrVal, err: ErrSlot) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_terminal_write(const MsObj *handle, const MsString *text, MsString *err);
/* Waits for input: OK (the text is `msstd_terminal_input_text`), NONE (nothing came: a resize, or `quick` ran out), CLOSED, or
 * TIMED_OUT. `quick` ends the wait after 40 ms, which resolves a lone escape byte. */
/* ms-sig: msstd_terminal_raw_terminal_read(handle h: *const ObjCell<RawH>, quick: u8) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_terminal_read(const MsObj *handle, uint8_t quick);
/* The text the last successful read of the raw terminal delivered; empty without one. */
/* ms-sig: msstd_terminal_input_text(out: *mut StrVal) @domain=terminal */
void msstd_terminal_input_text(MsString *out);

#endif
