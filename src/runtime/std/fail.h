/* runtime/std/fail.h: how the natives that call the operating system report a failure. A native keeps an MsFail while
 * it works, sets it where the host refuses, and ends with ms_fail_finish, which returns the status and fills the `err`
 * slot (the caller reads the slot whatever the status: empty unless the status is MS_STATUS_FAILED, whose text it
 * carries, or the path a status names). Host errors are libuv statuses (negative UV_E* codes). */
#ifndef MS_RUNTIME_STD_FAIL_H
#define MS_RUNTIME_STD_FAIL_H

#include "abi/status.h"
#include "base/string.h"

typedef struct MsFail {
  uint8_t status;   /* MS_STATUS_OK while nothing failed */
  MsString message; /* only for MS_STATUS_FAILED */
} MsFail;

MsFail ms_fail_new(void);
bool ms_fail_failed(const MsFail *fail);
void ms_fail_free(MsFail *fail);
void ms_fail_status(MsFail *fail, uint8_t status);
/* MS_STATUS_FAILED with `text`. */
void ms_fail_text(MsFail *fail, const char *text);
/* The status a libuv failure maps to: not found, exists, not empty, invalid, permission, unsupported, or
 * MS_STATUS_FAILED for the rest. */
uint8_t ms_fail_classify(int code);
/* A libuv failure (a negative UV_* code) of `operation` on `name` (empty for none): a status that has a meaning of its
 * own carries no text, the rest are MS_STATUS_FAILED with `operation name: reason`. */
void ms_fail_uv(MsFail *fail, int code, const char *operation, MsSpan name);
/* The same, but always MS_STATUS_FAILED with its text whatever the code means (streams report every failure so). */
void ms_fail_uv_text(MsFail *fail, int code, const char *operation, MsSpan name);

/* Ends a native: returns the failure's status and fills `err`. A status other than MS_STATUS_FAILED stores `detail`
 * (the path of the operation, or nothing). A pending stop request is delivered by cancelling the task: the text is
 * dropped first. A success is returned as it is, with `err` empty. */
/* Whether ms_fail_finish would deliver a stop request instead of returning: it never returns, so a caller frees what it
 * owns before it, never after. */
bool ms_fail_cancel_pending(const MsFail *fail);
uint8_t ms_fail_finish(MsFail *fail, MsString *err);
uint8_t ms_fail_finish_at(MsFail *fail, MsSpan detail, MsString *err);
/* The end of a native entry (an `msstd_` function the compiled code calls) whose work ran in layers below that only
 * return: a failed `status` while a stop request is pending ends the call by the cancel, with `err` dropped first;
 * anything else returns as it is. Layers beneath an entry never end a call by the cancel: a cancelled wait reaches
 * them as a failed status and each frees what it holds on its ordinary error path. */
uint8_t ms_native_return(uint8_t status, MsString *err);
/* Ends a native with a call's `status` and the text it left, which moves into the failure. */
uint8_t ms_fail_finish_with(uint8_t status, MsString *text, MsString *err);

/* Whether a stop request is pending for the running task; never true on a pool thread, where a job runs to its end. */
bool ms_fail_cancel_requested(void);
/* A pending stop request as a failure: true, with `fail` set to "cancelled", when one is pending. */
bool ms_fail_poll_cancel(MsFail *fail);

#endif
