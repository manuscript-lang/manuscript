/* runtime/std/signals.h: the signal-watcher natives of @std/process (signals.c over sys/process.h). Fallible functions
 * return a status (0 ok, otherwise the runtime's MS_STATUS_* code; MS_STATUS_FAILED carries its text through `err`) and
 * write results only on success. A watcher (`handle`) is an MsObj whose drop stops the observation. */
#ifndef MS_RUNTIME_STD_SIGNALS_H
#define MS_RUNTIME_STD_SIGNALS_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/list.h"
#include "base/string.h"

/* ms-sig: msstd_process_watch_signals(signals: *const VecVal, has_capacity: HasRaw, capacity: i64, out: *mut *mut ObjCell<Watcher>, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_watch_signals(const MsList *signals, uint8_t has_capacity, int64_t capacity, MsObj **out,
                                    MsString *err);
/* ms-sig: msstd_process_signal_next(handle h: *mut ObjCell<Watcher>, out: *mut i64, err: ErrSlot) -> u8 @domain=process */
uint8_t msstd_process_signal_next(MsObj *object, int64_t *out, MsString *err);
/* ms-sig: msstd_process_signal_close(handle h: *mut ObjCell<Watcher>) @domain=process */
void msstd_process_signal_close(MsObj *object);

#endif
