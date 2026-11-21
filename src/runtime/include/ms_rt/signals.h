/* ms_rt/signals.h: the signal-watcher natives of @std/process (src/runtime/std/signals.c over src/runtime/sys signal.c files).
 * Fallible functions return a status (0 ok, otherwise the runtime's STATUS_* code; STATUS_FAILED carries its text
 * through `err`) and write results only on success. A watcher (`handle`) is an MsObj whose drop stops the
 * observation. Symbols are listed in src/runtime/symbols/signals.txt. */
#ifndef MS_RT_SIGNALS_H
#define MS_RT_SIGNALS_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms: domain process */

/* ms-sig: msstd_process_watch_signals(signals: *const VecVal, has_capacity: HasRaw, capacity: i64, out: *mut *mut ObjCell<Watcher>, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_watch_signals(const MsVec *signals, uint8_t has_capacity, int64_t capacity, MsObj **out, MsStr *err);
/* ms-sig: msstd_process_signal_next(handle h: *mut ObjCell<Watcher>, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_signal_next(MsObj *object, int64_t *out, MsStr *err);
/* ms-sig: msstd_process_signal_close(handle h: *mut ObjCell<Watcher>) @domain=process */
void msstd_process_signal_close(MsObj *object);

/* Holds SIGINT and SIGTERM back from the calling task until the matching release (`hold_stop` in @std/os/process.ms),
 * so it can forward them and keep waiting. Holds nest. */
/* ms-sig: msstd_process_stop_hold() @domain=process @leaf */
void msstd_process_stop_hold(void);
/* ms-sig: msstd_process_stop_release() @domain=process @leaf */
void msstd_process_stop_release(void);

#endif
