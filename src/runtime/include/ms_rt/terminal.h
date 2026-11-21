/* ms_rt/terminal.h: the @std/io terminal natives (src/runtime/std/terminal.c) over libuv's uv_tty. The raw terminal is a
 * handle (a MsObj whose `drop` releases it); `share` makes a second handle on the same terminal, which closes once
 * the last handle is gone. Fallible functions return a status (0 ok, STATUS_NONE when a read found nothing,
 * STATUS_NOT_TERMINAL when standard input or output is not a terminal, STATUS_BUSY while another raw terminal is
 * open); STATUS_FAILED carries its text through `err`. Symbols are listed in src/runtime/symbols/terminal.txt. */
/* ms: domain terminal */
#ifndef MS_RT_TERMINAL_H
#define MS_RT_TERMINAL_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms-sig: msstd_terminal_capabilities_colors() -> i64 @domain=terminal */
int64_t msstd_terminal_capabilities_colors(void);
/* ms-sig: msstd_terminal_capabilities_error_is_terminal() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_error_is_terminal(void);
/* ms-sig: msstd_terminal_capabilities_input_is_terminal() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_input_is_terminal(void);
/* ms-sig: msstd_terminal_capabilities_output_is_terminal() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_output_is_terminal(void);
/* ms-sig: msstd_terminal_capabilities_raw_mode() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_raw_mode(void);
/* ms-sig: msstd_terminal_capabilities_resize_events() -> u8 @domain=terminal */
uint8_t msstd_terminal_capabilities_resize_events(void);
/* The text the last successful read of the terminal delivered. */
/* ms-sig: msstd_terminal_input_text(handle h: *const ObjCell<RawH>, out: *mut StrVal) @domain=terminal */
void msstd_terminal_input_text(const MsObj *handle, MsStr *out);
/* ms-sig: msstd_terminal_raw_mode(out: *mut *mut ObjCell<RawH>, err: ErrSlot) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_mode(MsObj **out, MsStr *err);
/* ms-sig: msstd_terminal_raw_terminal_close(handle h: *const ObjCell<RawH>) @domain=terminal */
void msstd_terminal_raw_terminal_close(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_read(handle h: *const ObjCell<RawH>, quick: u8) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_terminal_read(const MsObj *handle, uint8_t quick);
/* ms-sig: msstd_terminal_raw_terminal_set_restore(handle h: *const ObjCell<RawH>, text: *const StrVal) @domain=terminal */
void msstd_terminal_raw_terminal_set_restore(const MsObj *handle, const MsStr *text);
/* ms-sig: msstd_terminal_raw_terminal_share(handle h: *const ObjCell<RawH>) -> *mut ObjCell<RawH> @handle @domain=terminal */
MsObj *msstd_terminal_raw_terminal_share(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_size_columns(handle h: *const ObjCell<RawH>) -> i64 @domain=terminal */
int64_t msstd_terminal_raw_terminal_size_columns(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_size_rows(handle h: *const ObjCell<RawH>) -> i64 @domain=terminal */
int64_t msstd_terminal_raw_terminal_size_rows(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_size_status(handle h: *const ObjCell<RawH>) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_terminal_size_status(const MsObj *handle);
/* ms-sig: msstd_terminal_raw_terminal_write(handle h: *const ObjCell<RawH>, text: *const StrVal, err: ErrSlot) -> u8 @domain=terminal */
uint8_t msstd_terminal_raw_terminal_write(const MsObj *handle, const MsStr *text, MsStr *err);
/* ms-sig: msstd_terminal_size_columns() -> i64 @domain=terminal */
int64_t msstd_terminal_size_columns(void);
/* ms-sig: msstd_terminal_size_rows() -> i64 @domain=terminal */
int64_t msstd_terminal_size_rows(void);
/* ms-sig: msstd_terminal_size_status() -> u8 @domain=terminal */
uint8_t msstd_terminal_size_status(void);

#endif
